package rebac

import (
	"context"
	"fmt"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// evaluateCheck performs the recursive Zanzibar check algorithm.
func (e *Engine) evaluateCheck(ctx context.Context, req *CheckRequest, snapshot storage.Revision) (CheckResult, error) {
	e.schemaMu.RLock()
	schema := e.schema
	e.schemaMu.RUnlock()
	if schema == nil {
		return CheckDenied, nil
	}

	typeDef, ok := schema.Definitions[req.Resource.Type]
	if !ok {
		return CheckDenied, fmt.Errorf("unknown resource type: %s", req.Resource.Type)
	}

	relDef, ok := typeDef.Relations[req.Permission]
	if !ok {
		return CheckDenied, nil
	}

	return e.evalExpression(ctx, req, relDef, snapshot, 0)
}

const maxRecursionDepth = 25

func (e *Engine) evalExpression(ctx context.Context, req *CheckRequest, rel *RelationDef, snapshot storage.Revision, depth int) (CheckResult, error) {
	if depth > maxRecursionDepth {
		return CheckDenied, fmt.Errorf("max recursion depth exceeded")
	}
	if !rel.IsPermission {
		// Direct relation check: is req.Subject directly related?
		return e.checkDirectRelation(ctx, req, req.Resource, rel.Name, req.Subject, snapshot)
	}
	if rel.Expression == nil {
		return CheckDenied, nil
	}
	return e.evalSetExpr(ctx, req, rel.Expression, snapshot, depth)
}

func (e *Engine) evalSetExpr(ctx context.Context, req *CheckRequest, expr *SetExpression, snapshot storage.Revision, depth int) (CheckResult, error) {
	switch expr.Op {
	case "computed":
		return e.evalComputedRef(ctx, req, expr.Ref, snapshot, depth)
	case "union":
		for _, child := range expr.Children {
			result, err := e.evalSetExpr(ctx, req, child, snapshot, depth+1)
			if err != nil {
				return CheckDenied, err
			}
			if result == CheckAllowed {
				return CheckAllowed, nil
			}
		}
		return CheckDenied, nil
	case "intersection":
		for _, child := range expr.Children {
			result, err := e.evalSetExpr(ctx, req, child, snapshot, depth+1)
			if err != nil {
				return CheckDenied, err
			}
			if result != CheckAllowed {
				return CheckDenied, nil
			}
		}
		return CheckAllowed, nil
	case "exclusion":
		if len(expr.Children) < 2 {
			return CheckDenied, nil
		}
		left, err := e.evalSetExpr(ctx, req, expr.Children[0], snapshot, depth+1)
		if err != nil || left != CheckAllowed {
			return left, err
		}
		right, err := e.evalSetExpr(ctx, req, expr.Children[1], snapshot, depth+1)
		if err != nil {
			return CheckDenied, err
		}
		if right == CheckAllowed {
			return CheckDenied, nil
		}
		return CheckAllowed, nil
	case "arrow":
		return e.evalArrow(ctx, req, expr.Arrow, snapshot, depth)
	}
	return CheckDenied, nil
}

func (e *Engine) evalComputedRef(ctx context.Context, req *CheckRequest, relName string, snapshot storage.Revision, depth int) (CheckResult, error) {
	e.schemaMu.RLock()
	schema := e.schema
	e.schemaMu.RUnlock()

	typeDef, ok := schema.Definitions[req.Resource.Type]
	if !ok {
		return CheckDenied, nil
	}
	relDef, ok := typeDef.Relations[relName]
	if !ok {
		return CheckDenied, nil
	}
	return e.evalExpression(ctx, req, relDef, snapshot, depth+1)
}

func (e *Engine) evalArrow(ctx context.Context, req *CheckRequest, arrow *ArrowExpr, snapshot storage.Revision, depth int) (CheckResult, error) {
	// Step 1: find all objects in tupleset relation
	iter, err := e.storage.ReadTuples(ctx, types.TupleFilter{
		ResourceType: req.Resource.Type,
		ResourceID:   req.Resource.ID,
		Relation:     arrow.TuplesetRelation,
	}, snapshot)
	if err != nil {
		return CheckDenied, err
	}
	defer iter.Close()

	for {
		t, err := iter.Next()
		if err != nil {
			break
		}
		// Step 2: check permission on each related object
		subReq := &CheckRequest{
			Resource:      ObjectRef{Type: t.SubjectType, ID: t.SubjectID},
			Permission:    arrow.ComputedPermission,
			Subject:       req.Subject,
			CaveatContext: req.CaveatContext,
		}
		result, err := e.evaluateCheck(ctx, subReq, snapshot)
		if err != nil {
			continue
		}
		if result == CheckAllowed {
			return CheckAllowed, nil
		}
	}
	return CheckDenied, nil
}

func (e *Engine) checkDirectRelation(ctx context.Context, req *CheckRequest, resource ObjectRef, relation string, subject SubjectRef, snapshot storage.Revision) (CheckResult, error) {
	filter := types.TupleFilter{
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		Relation:     relation,
		SubjectType:  subject.Type,
		SubjectID:    subject.ID,
	}
	iter, err := e.storage.ReadTuples(ctx, filter, snapshot)
	if err != nil {
		return CheckDenied, err
	}
	defer iter.Close()

	for {
		t, err := iter.Next()
		if err != nil || t == nil {
			break
		}
		if t.CaveatName == "" {
			return CheckAllowed, nil
		}
		result, _ := e.caveats.Evaluate(t.CaveatName, t.CaveatContext, req.CaveatContext)
		if result == CaveatSatisfied {
			return CheckAllowed, nil
		} else if result == CaveatMissingContext {
			return CheckConditional, nil
		}
	}

	// Check userset membership: find all groups and check if subject is a member
	return e.checkUsersets(ctx, req, resource, relation, subject, snapshot)
}

func (e *Engine) checkUsersets(ctx context.Context, req *CheckRequest, resource ObjectRef, relation string, subject SubjectRef, snapshot storage.Revision) (CheckResult, error) {
	// Find all usersets related to this resource#relation
	iter, err := e.storage.ReadTuples(ctx, types.TupleFilter{
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		Relation:     relation,
	}, snapshot)
	if err != nil {
		return CheckDenied, err
	}
	defer iter.Close()

	for {
		t, err := iter.Next()
		if err != nil {
			break
		}
		if t.SubjectRelation == "" {
			continue // direct user, already checked above
		}
		// t is a userset (e.g. team:eng#member), recursively check membership
		subReq := &CheckRequest{
			Resource:   ObjectRef{Type: t.SubjectType, ID: t.SubjectID},
			Permission: t.SubjectRelation,
			Subject:    subject,
		}
		result, err := e.evaluateCheck(ctx, subReq, snapshot)
		if err != nil {
			continue
		}
		if result == CheckAllowed {
			return CheckAllowed, nil
		}
	}
	return CheckDenied, nil
}
