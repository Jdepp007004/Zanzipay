// Package policy implements the Cedar-based policy engine.
package policy

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"
	"sync"
	"time"
)

// PolicyEffect is either permit or forbid.
type PolicyEffect string

const (
	EffectPermit PolicyEffect = "permit"
	EffectForbid PolicyEffect = "forbid"
)

// CedarPolicy represents a single parsed Cedar policy.
type CedarPolicy struct {
	ID         string
	Effect     PolicyEffect
	Principal  string
	Action     string
	Resource   string
	Conditions []string
	Raw        string
}

// PolicyStore manages Cedar policy versions.
type PolicyStore struct {
	mu      sync.RWMutex
	current string
	version string
}

// NewPolicyStore creates an empty policy store.
func NewPolicyStore() *PolicyStore { return &PolicyStore{} }

// Write stores a new policy set and returns the version hash.
func (s *PolicyStore) Write(_ context.Context, policies string) (string, error) {
	version := fmt.Sprintf("%x", sha256.Sum256([]byte(policies)))[:12]
	s.mu.Lock()
	s.current = policies
	s.version = version
	s.mu.Unlock()
	return version, nil
}

// Read returns the current policy set and version.
func (s *PolicyStore) Read(_ context.Context) (string, string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.current, s.version, nil
}

// ParseCedarPolicies is a simplified Cedar policy parser.
func ParseCedarPolicies(source string) ([]CedarPolicy, error) {
	var policies []CedarPolicy
	raw := strings.TrimSpace(source)
	if raw == "" {
		return nil, nil
	}
	var blocks []string
	rest := raw
	for {
		permitIdx := strings.Index(rest, "permit")
		forbidIdx := strings.Index(rest, "forbid")
		if permitIdx == -1 && forbidIdx == -1 {
			break
		}
		var start int
		switch {
		case permitIdx == -1:
			start = forbidIdx
		case forbidIdx == -1:
			start = permitIdx
		case permitIdx < forbidIdx:
			start = permitIdx
		default:
			start = forbidIdx
		}
		endIdx := strings.Index(rest[start:], ";")
		if endIdx == -1 {
			blocks = append(blocks, rest[start:])
			break
		}
		blocks = append(blocks, rest[start:start+endIdx+1])
		rest = rest[start+endIdx+1:]
	}
	for i, block := range blocks {
		p, err := parseSinglePolicy(block, i)
		if err != nil {
			return nil, err
		}
		policies = append(policies, p)
	}
	return policies, nil
}

func parseSinglePolicy(block string, idx int) (CedarPolicy, error) {
	block = strings.TrimSpace(block)
	p := CedarPolicy{ID: fmt.Sprintf("policy_%d", idx), Raw: block}
	if strings.HasPrefix(block, "permit") {
		p.Effect = EffectPermit
	} else if strings.HasPrefix(block, "forbid") {
		p.Effect = EffectForbid
	} else {
		return p, fmt.Errorf("unknown policy effect in block %d", idx)
	}
	openParen := strings.Index(block, "(")
	closeParen := strings.Index(block, ")")
	if openParen != -1 && closeParen > openParen {
		scope := block[openParen+1 : closeParen]
		parts := strings.SplitN(scope, ",", 3)
		if len(parts) >= 1 {
			p.Principal = strings.TrimSpace(parts[0])
		}
		if len(parts) >= 2 {
			p.Action = strings.TrimSpace(parts[1])
		}
		if len(parts) >= 3 {
			p.Resource = strings.TrimSpace(parts[2])
		}
	}
	if whenIdx := strings.Index(block, "when {"); whenIdx != -1 {
		endBrace := strings.LastIndex(block, "}")
		if endBrace > whenIdx {
			cond := strings.TrimSpace(block[whenIdx+6 : endBrace])
			p.Conditions = []string{cond}
		}
	}
	return p, nil
}

// CedarRequest is a Cedar authorization request.
type CedarRequest struct {
	PrincipalType string
	PrincipalID   string
	Action        string
	ResourceType  string
	ResourceID    string
	Context       map[string]interface{}
}

// CedarResponse is the result of Cedar policy evaluation.
type CedarResponse struct {
	Allowed       bool
	MatchedPermit []string
	MatchedForbid []string
}

// CedarEvaluator evaluates Cedar policies against requests.
type CedarEvaluator struct {
	policies []CedarPolicy
}

// NewCedarEvaluator creates an evaluator from parsed policies.
func NewCedarEvaluator(policies []CedarPolicy) *CedarEvaluator {
	return &CedarEvaluator{policies: policies}
}

// IsAuthorized implements the Cedar deny-overrides algorithm.
func (ce *CedarEvaluator) IsAuthorized(_ context.Context, req CedarRequest) (*CedarResponse, error) {
	resp := &CedarResponse{}
	for _, p := range ce.policies {
		if !policyMatchesScope(p, req) {
			continue
		}
		if !evalConditions(p.Conditions, req.Context) {
			continue
		}
		switch p.Effect {
		case EffectPermit:
			resp.MatchedPermit = append(resp.MatchedPermit, p.ID)
		case EffectForbid:
			resp.MatchedForbid = append(resp.MatchedForbid, p.ID)
		}
	}
	if len(resp.MatchedForbid) > 0 {
		resp.Allowed = false
		return resp, nil
	}
	resp.Allowed = len(resp.MatchedPermit) > 0
	return resp, nil
}

func policyMatchesScope(p CedarPolicy, req CedarRequest) bool {
	if p.Principal != "principal" && p.Principal != "" {
		if !strings.Contains(p.Principal, req.PrincipalType) {
			return false
		}
	}
	if p.Action != "action" && p.Action != "" {
		if !strings.Contains(p.Action, req.Action) && !strings.Contains(req.Action, extractActionName(p.Action)) {
			return false
		}
	}
	return true
}

func extractActionName(actionExpr string) string {
	if idx := strings.Index(actionExpr, `::"`); idx != -1 {
		s := actionExpr[idx+3:]
		if end := strings.Index(s, `"`); end != -1 {
			return s[:end]
		}
	}
	return actionExpr
}

func evalConditions(conditions []string, ctx map[string]interface{}) bool {
	for _, cond := range conditions {
		if !evalSingleCondition(cond, ctx) {
			return false
		}
	}
	return true
}

func evalSingleCondition(cond string, ctx map[string]interface{}) bool {
	return EvalCondition(cond, ctx)
}

// PolicyEvalRequest is the input to the policy engine.
type PolicyEvalRequest struct {
	PrincipalType string
	PrincipalID   string
	Action        string
	ResourceType  string
	ResourceID    string
	Context       map[string]interface{}
}

// PolicyDecision is the output of the policy engine.
type PolicyDecision struct {
	Allowed         bool
	MatchedPolicies []string
	DeniedBy        string
	EvalDuration    time.Duration
}

// Engine is the Cedar-based policy engine.
type Engine struct {
	store *PolicyStore
}

// NewEngine creates a new policy engine.
func NewEngine(store *PolicyStore) *Engine {
	return &Engine{store: store}
}

// Evaluate runs Cedar policies against the request.
func (e *Engine) Evaluate(ctx context.Context, req *PolicyEvalRequest) (*PolicyDecision, error) {
	start := time.Now()
	policies, _, err := e.store.Read(ctx)
	if err != nil {
		return nil, fmt.Errorf("reading policies: %w", err)
	}
	if policies == "" {
		return &PolicyDecision{Allowed: false, EvalDuration: time.Since(start)}, nil
	}
	parsed, err := ParseCedarPolicies(policies)
	if err != nil {
		return nil, fmt.Errorf("parsing policies: %w", err)
	}
	eval := NewCedarEvaluator(parsed)
	resp, err := eval.IsAuthorized(ctx, CedarRequest{
		PrincipalType: req.PrincipalType,
		PrincipalID:   req.PrincipalID,
		Action:        req.Action,
		ResourceType:  req.ResourceType,
		ResourceID:    req.ResourceID,
		Context:       req.Context,
	})
	if err != nil {
		return nil, err
	}
	decision := &PolicyDecision{
		Allowed:         resp.Allowed,
		MatchedPolicies: append(resp.MatchedPermit, resp.MatchedForbid...),
		EvalDuration:    time.Since(start),
	}
	if len(resp.MatchedForbid) > 0 {
		decision.DeniedBy = resp.MatchedForbid[0]
	}
	return decision, nil
}

// DeployPolicies validates and stores a new policy set.
func (e *Engine) DeployPolicies(ctx context.Context, policySource string) (string, []string, error) {
	if _, err := ParseCedarPolicies(policySource); err != nil {
		return "", nil, fmt.Errorf("parsing policies: %w", err)
	}
	version, err := e.store.Write(ctx, policySource)
	if err != nil {
		return "", nil, err
	}
	return version, nil, nil
}
