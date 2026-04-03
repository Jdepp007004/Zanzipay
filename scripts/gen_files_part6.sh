#!/usr/bin/env bash
# Part 6: internal/rebac/ — caveat, check, expand, namespace, engine
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/rebac/caveat.go ─────────────────────────────────────────────────
cat > internal/rebac/caveat.go << 'ENDOFFILE'
package rebac

import (
	"fmt"

	"github.com/google/cel-go/cel"
)

// CaveatResult is the outcome of evaluating a caveat.
type CaveatResult int

const (
	CaveatSatisfied    CaveatResult = iota // expression evaluated true
	CaveatNotSatisfied                     // expression evaluated false
	CaveatMissingContext                   // required params missing from context
)

// CaveatEvaluator pre-compiles CEL expressions for fast evaluation.
type CaveatEvaluator struct {
	definitions map[string]*CaveatDefinition
	programs    map[string]cel.Program
	env         *cel.Env
}

// NewCaveatEvaluator creates a new evaluator and compiles all CEL expressions.
func NewCaveatEvaluator(definitions []*CaveatDefinition) (*CaveatEvaluator, error) {
	env, err := cel.NewEnv()
	if err != nil {
		return nil, fmt.Errorf("creating CEL env: %w", err)
	}
	ce := &CaveatEvaluator{
		definitions: make(map[string]*CaveatDefinition),
		programs:    make(map[string]cel.Program),
		env:         env,
	}
	for _, def := range definitions {
		if err := ce.RegisterCaveat(def); err != nil {
			return nil, err
		}
	}
	return ce, nil
}

// RegisterCaveat compiles and registers a caveat definition.
func (ce *CaveatEvaluator) RegisterCaveat(def *CaveatDefinition) error {
	if def.Expression == "" {
		ce.definitions[def.Name] = def
		return nil
	}
	ast, issues := ce.env.Parse(def.Expression)
	if issues != nil && issues.Err() != nil {
		return fmt.Errorf("parsing caveat %q expression: %w", def.Name, issues.Err())
	}
	prog, err := ce.env.Program(ast)
	if err != nil {
		return fmt.Errorf("compiling caveat %q: %w", def.Name, err)
	}
	ce.definitions[def.Name] = def
	ce.programs[def.Name] = prog
	return nil
}

// Evaluate runs a caveat against the merged context.
func (ce *CaveatEvaluator) Evaluate(
	caveatName string,
	tupleCtx map[string]interface{},
	requestCtx map[string]interface{},
) (CaveatResult, error) {
	prog, ok := ce.programs[caveatName]
	if !ok {
		// Unknown caveat — treat as missing context (conditional)
		return CaveatMissingContext, nil
	}

	// Merge contexts (request overrides tuple)
	merged := make(map[string]interface{})
	for k, v := range tupleCtx {
		merged[k] = v
	}
	for k, v := range requestCtx {
		merged[k] = v
	}

	out, _, err := prog.Eval(merged)
	if err != nil {
		// If evaluation fails due to missing key, return MISSING_CONTEXT
		return CaveatMissingContext, nil
	}
	if result, ok := out.Value().(bool); ok {
		if result {
			return CaveatSatisfied, nil
		}
		return CaveatNotSatisfied, nil
	}
	return CaveatNotSatisfied, fmt.Errorf("caveat %q expression did not return bool", caveatName)
}

// AnalyzeMissingFields returns parameter names missing from the provided context.
func (ce *CaveatEvaluator) AnalyzeMissingFields(caveatName string, provided map[string]interface{}) []string {
	def, ok := ce.definitions[caveatName]
	if !ok {
		return nil
	}
	var missing []string
	for param := range def.Parameters {
		if _, present := provided[param]; !present {
			missing = append(missing, param)
		}
	}
	return missing
}
ENDOFFILE
echo "  [OK] internal/rebac/caveat.go"

cat > internal/rebac/caveat_test.go << 'ENDOFFILE'
package rebac

import "testing"

func TestCaveatEvaluate(t *testing.T) {
	defs := []*CaveatDefinition{
		{
			Name:       "amount_limit",
			Parameters: map[string]string{"max_amount": "int"},
			Expression: "max_amount >= 100",
		},
	}
	ce, err := NewCaveatEvaluator(defs)
	if err != nil {
		t.Fatalf("NewCaveatEvaluator() error = %v", err)
	}

	result, err := ce.Evaluate("amount_limit",
		map[string]interface{}{"max_amount": int64(500)},
		map[string]interface{}{},
	)
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if result != CaveatSatisfied {
		t.Errorf("expected SATISFIED, got %d", result)
	}

	result, err = ce.Evaluate("amount_limit",
		map[string]interface{}{"max_amount": int64(50)},
		map[string]interface{}{},
	)
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if result != CaveatNotSatisfied {
		t.Errorf("expected NOT_SATISFIED, got %d", result)
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/caveat_test.go"

# ─── internal/rebac/check.go ─────────────────────────────────────────────────
cat > internal/rebac/check.go << 'ENDOFFILE'
package rebac

import (
	"context"
	"sync"
)

// CheckResult is the outcome of a permission check.
type CheckResult int

const (
	CheckAllowed     CheckResult = iota // Permission is granted
	CheckDenied                         // Permission is denied
	CheckConditional                    // Permission depends on missing caveat context
)

// CheckRequest holds the inputs for a permission check.
type CheckRequest struct {
	Resource      ObjectRef
	Permission    string
	Subject       SubjectRef
	ConsistencyLevel int
	Zookie        string
	CaveatContext map[string]interface{}
}

// CheckResponse holds the result of a permission check.
type CheckResponse struct {
	Result        CheckResult
	Verdict       string
	DecisionToken string
	Reasoning     string
}

// evaluateCheck is the top-level check algorithm.
func (e *Engine) evaluateCheck(ctx context.Context, req *CheckRequest, snapshot Revision) (CheckResult, error) {
	def, ok := e.schema.LookupDefinition(req.Resource.Type)
	if !ok {
		return CheckDenied, nil
	}

	// Check if it's a relation (direct lookup) or permission (rewrite)
	if perm, ok := def.Permissions[req.Permission]; ok {
		return e.evaluateUserset(ctx, perm.Userset, req.Resource, req.Subject, snapshot, req.CaveatContext)
	}
	if _, ok := def.Relations[req.Permission]; ok {
		return e.lookupDirectResult(ctx, req.Resource, req.Permission, req.Subject, snapshot, req.CaveatContext)
	}
	return CheckDenied, nil
}

// evaluateUserset recursively walks the userset rewrite tree.
func (e *Engine) evaluateUserset(
	ctx context.Context,
	userset *UsersetRewrite,
	resource ObjectRef,
	subject SubjectRef,
	snapshot Revision,
	caveatCtx map[string]interface{},
) (CheckResult, error) {
	if userset == nil {
		return CheckDenied, nil
	}

	switch userset.Operation {
	case OpLeaf:
		if userset.This != nil {
			return e.lookupDirectResult(ctx, resource, "", subject, snapshot, caveatCtx)
		}
		if userset.Computed != nil {
			return e.evaluateCheck(ctx, &CheckRequest{
				Resource:      resource,
				Permission:    userset.Computed.Relation,
				Subject:       subject,
				CaveatContext: caveatCtx,
			}, snapshot)
		}
		if userset.Arrow != nil {
			return e.evaluateArrow(ctx, userset.Arrow, resource, subject, snapshot, caveatCtx)
		}
		return CheckDenied, nil

	case OpUnion:
		return e.evaluateUnion(ctx, userset.Children, resource, subject, snapshot, caveatCtx)

	case OpIntersection:
		return e.evaluateIntersection(ctx, userset.Children, resource, subject, snapshot, caveatCtx)

	case OpExclusion:
		if len(userset.Children) < 2 {
			return CheckDenied, nil
		}
		base, err := e.evaluateUserset(ctx, userset.Children[0], resource, subject, snapshot, caveatCtx)
		if err != nil || base == CheckDenied {
			return CheckDenied, err
		}
		subtract, err := e.evaluateUserset(ctx, userset.Children[1], resource, subject, snapshot, caveatCtx)
		if err != nil {
			return CheckDenied, err
		}
		if subtract == CheckAllowed {
			return CheckDenied, nil
		}
		return base, nil
	}
	return CheckDenied, nil
}

// evaluateUnion returns ALLOWED if any child returns ALLOWED (short-circuits).
func (e *Engine) evaluateUnion(
	ctx context.Context,
	children []*UsersetRewrite,
	resource ObjectRef,
	subject SubjectRef,
	snapshot Revision,
	caveatCtx map[string]interface{},
) (CheckResult, error) {
	type result struct {
		r   CheckResult
		err error
	}
	results := make(chan result, len(children))
	ctx2, cancel := context.WithCancel(ctx)
	defer cancel()

	var wg sync.WaitGroup
	for _, child := range children {
		wg.Add(1)
		go func(c *UsersetRewrite) {
			defer wg.Done()
			r, err := e.evaluateUserset(ctx2, c, resource, subject, snapshot, caveatCtx)
			results <- result{r, err}
		}(child)
	}
	go func() { wg.Wait(); close(results) }()

	overall := CheckDenied
	for res := range results {
		if res.err != nil {
			continue
		}
		if res.r == CheckAllowed {
			cancel()
			return CheckAllowed, nil
		}
		if res.r == CheckConditional && overall == CheckDenied {
			overall = CheckConditional
		}
	}
	return overall, nil
}

// evaluateIntersection returns DENIED if any child returns DENIED.
func (e *Engine) evaluateIntersection(
	ctx context.Context,
	children []*UsersetRewrite,
	resource ObjectRef,
	subject SubjectRef,
	snapshot Revision,
	caveatCtx map[string]interface{},
) (CheckResult, error) {
	for _, child := range children {
		r, err := e.evaluateUserset(ctx, child, resource, subject, snapshot, caveatCtx)
		if err != nil || r == CheckDenied {
			return CheckDenied, err
		}
	}
	return CheckAllowed, nil
}

// evaluateArrow follows a relation to another object and checks a permission.
func (e *Engine) evaluateArrow(
	ctx context.Context,
	arrow *ArrowRef,
	resource ObjectRef,
	subject SubjectRef,
	snapshot Revision,
	caveatCtx map[string]interface{},
) (CheckResult, error) {
	// Find tuples for resource#arrow.Relation
	tuples, err := e.storage.ReadTuples(ctx, tupleFilterForRelation(resource, arrow.Relation), snapshot)
	if err != nil {
		return CheckDenied, err
	}
	defer tuples.Close()

	for {
		t, err := tuples.Next()
		if t == nil || err != nil {
			break
		}
		// The subject of the tuple becomes the new resource for the permission check
		innerResource := ObjectRef{Type: t.Subject.Type, ID: t.Subject.ID}
		result, err := e.evaluateCheck(ctx, &CheckRequest{
			Resource:      innerResource,
			Permission:    arrow.Permission,
			Subject:       subject,
			CaveatContext: caveatCtx,
		}, snapshot)
		if err != nil || result == CheckAllowed {
			return result, err
		}
	}
	return CheckDenied, nil
}

// lookupDirectResult checks for direct tuples matching resource#relation@subject.
func (e *Engine) lookupDirectResult(
	ctx context.Context,
	resource ObjectRef,
	relation string,
	subject SubjectRef,
	snapshot Revision,
	caveatCtx map[string]interface{},
) (CheckResult, error) {
	filter := tupleFilterForSubject(resource, relation, subject)
	iter, err := e.storage.ReadTuples(ctx, filter, snapshot)
	if err != nil {
		return CheckDenied, err
	}
	defer iter.Close()

	for {
		t, err := iter.Next()
		if t == nil || err != nil {
			break
		}
		if t.CaveatName != "" && e.caveats != nil {
			cavResult, _ := e.caveats.Evaluate(t.CaveatName, toIfaceMap(t.CaveatContext), caveatCtx)
			if cavResult == CaveatSatisfied {
				return CheckAllowed, nil
			}
			if cavResult == CaveatMissingContext {
				return CheckConditional, nil
			}
			// NOT_SATISFIED — continue looking
		} else {
			return CheckAllowed, nil
		}
	}
	return CheckDenied, nil
}

func tupleFilterForRelation(resource ObjectRef, relation string) storageTupleFilter {
	return storageTupleFilter{
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		Relation:     relation,
	}
}

func tupleFilterForSubject(resource ObjectRef, relation string, subject SubjectRef) storageTupleFilter {
	return storageTupleFilter{
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		Relation:     relation,
		SubjectType:  subject.Type,
		SubjectID:    subject.ID,
	}
}

func toIfaceMap(m map[string]interface{}) map[string]interface{} {
	if m == nil {
		return map[string]interface{}{}
	}
	return m
}
ENDOFFILE
echo "  [OK] internal/rebac/check.go"

cat > internal/rebac/check_test.go << 'ENDOFFILE'
package rebac

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

func TestCheckDirect(t *testing.T) {
	store := memory.New()
	engine, err := NewEngine(store)
	if err != nil {
		t.Fatalf("NewEngine() error = %v", err)
	}

	ctx := context.Background()
	if err := engine.WriteSchema(ctx, `
definition user {}
definition account {
    relation owner: user
    permission manage = owner
}`); err != nil {
		t.Fatalf("WriteSchema() error = %v", err)
	}

	store.WriteTuples(ctx, []types.Tuple{{
		ResourceType: "account", ResourceID: "acme",
		Relation:    "owner",
		SubjectType: "user", SubjectID: "alice",
	}})

	resp, err := engine.Check(ctx, &CheckRequest{
		Resource:   ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    SubjectRef{Type: "user", ID: "alice"},
	})
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if resp.Result != CheckAllowed {
		t.Errorf("expected ALLOWED, got %v (verdict=%s)", resp.Result, resp.Verdict)
	}

	resp2, _ := engine.Check(ctx, &CheckRequest{
		Resource:   ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    SubjectRef{Type: "user", ID: "bob"},
	})
	if resp2.Result != CheckDenied {
		t.Error("expected DENIED for bob")
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/check_test.go"

# ─── internal/rebac/expand.go ─────────────────────────────────────────────────
cat > internal/rebac/expand.go << 'ENDOFFILE'
package rebac

import "context"

// UsersetNode is a node in the expansion tree.
type UsersetNode struct {
	Type     string         // "leaf" | "union" | "intersection" | "exclusion"
	Value    string         // for leaf: "user:alice"
	Children []*UsersetNode // for composite
	Relation string         // which relation this node represents
}

// ExpandRequest holds inputs for the Expand API.
type ExpandRequest struct {
	Resource   ObjectRef
	Permission string
}

// ExpandResponse holds the userset tree.
type ExpandResponse struct {
	Tree *UsersetNode
}

// Expand returns the full userset tree for a resource#permission.
func (e *Engine) Expand(ctx context.Context, req *ExpandRequest) (*ExpandResponse, error) {
	rev, err := e.storage.CurrentRevision(ctx)
	if err != nil {
		return nil, err
	}
	tree, err := e.expandUserset(ctx, req.Resource, req.Permission, rev)
	if err != nil {
		return nil, err
	}
	return &ExpandResponse{Tree: tree}, nil
}

func (e *Engine) expandUserset(ctx context.Context, resource ObjectRef, permission string, snapshot Revision) (*UsersetNode, error) {
	if e.schema == nil {
		return &UsersetNode{Type: "leaf", Value: "schema:missing"}, nil
	}
	def, ok := e.schema.LookupDefinition(resource.Type)
	if !ok {
		return &UsersetNode{Type: "leaf", Value: "type:unknown"}, nil
	}

	// Look for a permission definition
	if perm, ok := def.Permissions[permission]; ok {
		return e.expandRewrite(ctx, perm.Userset, resource, snapshot)
	}

	// Look for a direct relation
	if _, ok := def.Relations[permission]; ok {
		return e.expandDirectTuples(ctx, resource, permission, snapshot)
	}
	return &UsersetNode{Type: "leaf", Value: "unknown"}, nil
}

func (e *Engine) expandRewrite(ctx context.Context, userset *UsersetRewrite, resource ObjectRef, snapshot Revision) (*UsersetNode, error) {
	if userset == nil {
		return &UsersetNode{Type: "leaf", Value: "nil"}, nil
	}
	switch userset.Operation {
	case OpUnion:
		node := &UsersetNode{Type: "union"}
		for _, child := range userset.Children {
			childNode, err := e.expandRewrite(ctx, child, resource, snapshot)
			if err != nil {
				return nil, err
			}
			node.Children = append(node.Children, childNode)
		}
		return node, nil
	case OpLeaf:
		if userset.Computed != nil {
			return e.expandUserset(ctx, resource, userset.Computed.Relation, snapshot)
		}
		if userset.Arrow != nil {
			return e.expandArrow(ctx, userset.Arrow, resource, snapshot)
		}
		return e.expandDirectTuples(ctx, resource, "", snapshot)
	default:
		return &UsersetNode{Type: string(userset.Operation)}, nil
	}
}

func (e *Engine) expandDirectTuples(ctx context.Context, resource ObjectRef, relation string, snapshot Revision) (*UsersetNode, error) {
	iter, err := e.storage.ReadTuples(ctx, tupleFilterForRelation(resource, relation), snapshot)
	if err != nil {
		return nil, err
	}
	defer iter.Close()
	node := &UsersetNode{Type: "union", Relation: relation}
	for {
		t, err := iter.Next()
		if t == nil || err != nil {
			break
		}
		node.Children = append(node.Children, &UsersetNode{
			Type:  "leaf",
			Value: t.Subject.String(),
		})
	}
	return node, nil
}

func (e *Engine) expandArrow(ctx context.Context, arrow *ArrowRef, resource ObjectRef, snapshot Revision) (*UsersetNode, error) {
	iter, err := e.storage.ReadTuples(ctx, tupleFilterForRelation(resource, arrow.Relation), snapshot)
	if err != nil {
		return nil, err
	}
	defer iter.Close()
	node := &UsersetNode{Type: "union", Relation: arrow.Relation + "->" + arrow.Permission}
	for {
		t, err := iter.Next()
		if t == nil || err != nil {
			break
		}
		inner := ObjectRef{Type: t.Subject.Type, ID: t.Subject.ID}
		childNode, err := e.expandUserset(ctx, inner, arrow.Permission, snapshot)
		if err != nil {
			return nil, err
		}
		node.Children = append(node.Children, childNode)
	}
	return node, nil
}
ENDOFFILE
echo "  [OK] internal/rebac/expand.go"

cat > internal/rebac/expand_test.go << 'ENDOFFILE'
package rebac

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

func TestExpand(t *testing.T) {
	store := memory.New()
	engine, _ := NewEngine(store)
	ctx := context.Background()
	engine.WriteSchema(ctx, `
definition user {}
definition account {
    relation owner: user
    permission manage = owner
}`)
	store.WriteTuples(ctx, []types.Tuple{{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner", SubjectType: "user", SubjectID: "alice",
	}})
	resp, err := engine.Expand(ctx, &ExpandRequest{
		Resource:   ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
	})
	if err != nil {
		t.Fatalf("Expand() error = %v", err)
	}
	if resp.Tree == nil {
		t.Error("expected non-nil tree")
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/expand_test.go"

# ─── internal/rebac/namespace.go ─────────────────────────────────────────────
cat > internal/rebac/namespace.go << 'ENDOFFILE'
package rebac

import (
	"context"
	"sync"
)

// NamespaceManager manages per-namespace schema state.
type NamespaceManager struct {
	mu      sync.RWMutex
	schemas map[string]*Schema // namespace → schema
}

// NewNamespaceManager creates an empty namespace manager.
func NewNamespaceManager() *NamespaceManager {
	return &NamespaceManager{schemas: make(map[string]*Schema)}
}

// SetSchema sets the schema for a namespace.
func (nm *NamespaceManager) SetSchema(_ context.Context, namespace string, s *Schema) {
	nm.mu.Lock()
	defer nm.mu.Unlock()
	nm.schemas[namespace] = s
}

// GetSchema returns the schema for a namespace.
func (nm *NamespaceManager) GetSchema(_ context.Context, namespace string) (*Schema, bool) {
	nm.mu.RLock()
	defer nm.mu.RUnlock()
	s, ok := nm.schemas[namespace]
	return s, ok
}

// ListNamespaces returns all registered namespace names.
func (nm *NamespaceManager) ListNamespaces(_ context.Context) []string {
	nm.mu.RLock()
	defer nm.mu.RUnlock()
	names := make([]string, 0, len(nm.schemas))
	for k := range nm.schemas {
		names = append(names, k)
	}
	return names
}
ENDOFFILE
echo "  [OK] internal/rebac/namespace.go"

cat > internal/rebac/namespace_test.go << 'ENDOFFILE'
package rebac

import (
	"context"
	"testing"
)

func TestNamespaceManager(t *testing.T) {
	nm := NewNamespaceManager()
	ctx := context.Background()
	s := &Schema{Definitions: map[string]*TypeDefinition{}}
	nm.SetSchema(ctx, "test", s)

	got, ok := nm.GetSchema(ctx, "test")
	if !ok || got == nil {
		t.Error("GetSchema() not found after SetSchema()")
	}
	names := nm.ListNamespaces(ctx)
	if len(names) != 1 || names[0] != "test" {
		t.Errorf("ListNamespaces() = %v, want [test]", names)
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/namespace_test.go"

echo "=== internal/rebac/ check+expand+namespace done ==="
ENDOFFILE
echo "Part 6 script written"
