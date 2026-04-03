#!/usr/bin/env bash
# Part 8: internal/policy/ — Cedar policy engine
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

cat > internal/policy/store.go << 'ENDOFFILE'
// Package policy implements the Cedar-based policy engine.
package policy

import (
	"context"
	"crypto/sha256"
	"fmt"
	"sync"
)

// PolicyStore manages Cedar policy versions.
type PolicyStore struct {
	mu      sync.RWMutex
	current string
	version string
	history []policyEntry
}

type policyEntry struct {
	Policies string
	Version  string
}

// NewPolicyStore creates an empty policy store.
func NewPolicyStore() *PolicyStore { return &PolicyStore{} }

// Write stores a new policy set.
func (s *PolicyStore) Write(_ context.Context, policies string) (string, error) {
	version := fmt.Sprintf("%x", sha256.Sum256([]byte(policies)))[:12]
	s.mu.Lock()
	s.history = append(s.history, policyEntry{s.current, s.version})
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
ENDOFFILE
echo "  [OK] internal/policy/store.go"

cat > internal/policy/store_test.go << 'ENDOFFILE'
package policy_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestPolicyStore(t *testing.T) {
	s := policy.NewPolicyStore()
	ctx := context.Background()
	ver, err := s.Write(ctx, `permit(principal, action, resource);`)
	if err != nil || ver == "" {
		t.Fatalf("Write() error = %v, ver = %q", err, ver)
	}
	p, v, err := s.Read(ctx)
	if err != nil || p == "" || v != ver {
		t.Fatalf("Read() mismatch: p=%q v=%q err=%v", p, v, err)
	}
}
ENDOFFILE
echo "  [OK] internal/policy/store_test.go"

cat > internal/policy/cedar_parser.go << 'ENDOFFILE'
package policy

import (
	"fmt"
	"strings"
)

// PolicyEffect is either PERMIT or FORBID.
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
	Conditions []string // raw when/unless clause expressions
	Raw        string   // original policy text
}

// ParseCedarPolicies is a simplified Cedar policy parser.
// A full implementation would use an AST parser. This handles the
// common patterns needed for ZanziPay's fintech use cases.
func ParseCedarPolicies(source string) ([]CedarPolicy, error) {
	var policies []CedarPolicy
	// Split by semicolons (rough heuristic for policy boundaries)
	raw := strings.TrimSpace(source)
	if raw == "" {
		return nil, nil
	}

	// Find permit/forbid blocks
	var blocks []string
	rest := raw
	for {
		permitIdx := indexOfKeyword(rest, "permit")
		forbidIdx := indexOfKeyword(rest, "forbid")
		if permitIdx == -1 && forbidIdx == -1 {
			break
		}
		var start int
		if permitIdx == -1 {
			start = forbidIdx
		} else if forbidIdx == -1 {
			start = permitIdx
		} else if permitIdx < forbidIdx {
			start = permitIdx
		} else {
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

func indexOfKeyword(s, keyword string) int {
	idx := strings.Index(s, keyword)
	if idx == -1 {
		return -1
	}
	// Make sure it's at word boundary
	if idx > 0 && (s[idx-1] == '_' || (s[idx-1] >= 'a' && s[idx-1] <= 'z')) {
		return -1
	}
	return idx
}

func parseSinglePolicy(block string, idx int) (CedarPolicy, error) {
	block = strings.TrimSpace(block)
	p := CedarPolicy{
		ID:  fmt.Sprintf("policy_%d", idx),
		Raw: block,
	}
	if strings.HasPrefix(block, "permit") {
		p.Effect = EffectPermit
	} else if strings.HasPrefix(block, "forbid") {
		p.Effect = EffectForbid
	} else {
		return p, fmt.Errorf("unknown policy effect in: %q", block[:min(50, len(block))])
	}

	// Extract principal, action, resource from the scope
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

	// Extract when/unless conditions
	if whenIdx := strings.Index(block, "when {"); whenIdx != -1 {
		endBrace := strings.LastIndex(block, "}")
		if endBrace > whenIdx {
			cond := strings.TrimSpace(block[whenIdx+6 : endBrace])
			p.Conditions = []string{cond}
		}
	} else if unlessIdx := strings.Index(block, "unless {"); unlessIdx != -1 {
		endBrace := strings.LastIndex(block, "}")
		if endBrace > unlessIdx {
			cond := "!(" + strings.TrimSpace(block[unlessIdx+8:endBrace]) + ")"
			p.Conditions = []string{cond}
		}
	}
	return p, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_parser.go"

cat > internal/policy/cedar_parser_test.go << 'ENDOFFILE'
package policy_test

import (
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestParseCedarPolicies(t *testing.T) {
	src := `
permit(principal, action, resource) when {
    principal.kyc_status == "verified"
};

forbid(principal, action == Action::"refund", resource) when {
    resource.frozen == true
};
`
	policies, err := policy.ParseCedarPolicies(src)
	if err != nil {
		t.Fatalf("ParseCedarPolicies() error = %v", err)
	}
	if len(policies) != 2 {
		t.Errorf("got %d policies, want 2", len(policies))
	}
	if policies[0].Effect != policy.EffectPermit {
		t.Errorf("policies[0].Effect = %s, want permit", policies[0].Effect)
	}
	if policies[1].Effect != policy.EffectForbid {
		t.Errorf("policies[1].Effect = %s, want forbid", policies[1].Effect)
	}
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_parser_test.go"

cat > internal/policy/cedar_eval.go << 'ENDOFFILE'
package policy

import (
	"context"
	"strings"
)

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
	Allowed        bool
	MatchedPermit  []string
	MatchedForbid  []string
}

// CedarEvaluator evaluates Cedar policies against requests.
type CedarEvaluator struct {
	policies []CedarPolicy
}

// NewCedarEvaluator creates an evaluator from parsed policies.
func NewCedarEvaluator(policies []CedarPolicy) *CedarEvaluator {
	return &CedarEvaluator{policies: policies}
}

// IsAuthorized implements the Cedar authorization algorithm:
// 1. Collect matching policies
// 2. If any FORBID matches → DENY
// 3. If any PERMIT matches → ALLOW
// 4. Otherwise → DENY (deny by default)
func (ce *CedarEvaluator) IsAuthorized(_ context.Context, req CedarRequest) (*CedarResponse, error) {
	resp := &CedarResponse{}
	for _, p := range ce.policies {
		if !policyMatchesScope(p, req) {
			continue
		}
		if !evaluateConditions(p.Conditions, req.Context) {
			continue
		}
		switch p.Effect {
		case EffectPermit:
			resp.MatchedPermit = append(resp.MatchedPermit, p.ID)
		case EffectForbid:
			resp.MatchedForbid = append(resp.MatchedForbid, p.ID)
		}
	}

	// Forbid always wins
	if len(resp.MatchedForbid) > 0 {
		resp.Allowed = false
		return resp, nil
	}
	if len(resp.MatchedPermit) > 0 {
		resp.Allowed = true
		return resp, nil
	}
	// Deny by default
	resp.Allowed = false
	return resp, nil
}

// policyMatchesScope checks if a policy's scope matches the request.
func policyMatchesScope(p CedarPolicy, req CedarRequest) bool {
	// "principal" wildcard matches anything
	if p.Principal != "principal" && p.Principal != "" {
		// Could do more sophisticated matching here
		if !strings.Contains(p.Principal, req.PrincipalType) {
			return false
		}
	}
	// action wildcard
	if p.Action != "action" && p.Action != "" {
		if !strings.Contains(p.Action, req.Action) && !strings.Contains(req.Action, extractActionName(p.Action)) {
			return false
		}
	}
	return true
}

func extractActionName(actionExpr string) string {
	// Action::"refund" → refund
	if idx := strings.Index(actionExpr, `::"`); idx != -1 {
		s := actionExpr[idx+3:]
		if end := strings.Index(s, `"`); end != -1 {
			return s[:end]
		}
	}
	return actionExpr
}

// evaluateConditions checks if all conditions hold given the request context.
// This is a simplified evaluator — a full implementation would use CEL or
// a proper Cedar expression evaluator.
func evaluateConditions(conditions []string, ctx map[string]interface{}) bool {
	if len(conditions) == 0 {
		return true
	}
	// For now, treat an unknown condition as "passes" (conservative stub)
	// A real implementation would evaluate each condition as a CEL/Cedar expression
	for _, cond := range conditions {
		if !evalSingleCondition(cond, ctx) {
			return false
		}
	}
	return true
}

func evalSingleCondition(cond string, ctx map[string]interface{}) bool {
	// Very simplified evaluator that handles a few common patterns
	cond = strings.TrimSpace(cond)

	// Handle equality: key == "value"
	if strings.Contains(cond, " == ") {
		parts := strings.SplitN(cond, " == ", 2)
		key := strings.TrimSpace(parts[0])
		expected := strings.Trim(strings.TrimSpace(parts[1]), `"`)
		key = strings.TrimPrefix(key, "context.")
		key = strings.TrimPrefix(key, "principal.")
		key = strings.TrimPrefix(key, "resource.")
		if v, ok := ctx[key]; ok {
			return fmt.Sprint(v) == expected
		}
		return true // missing key → pass (conditional)
	}

	// Frozen check: resource.frozen == true
	if strings.Contains(cond, "frozen == true") {
		if frozen, ok := ctx["frozen"]; ok {
			if b, ok := frozen.(bool); ok {
				return b
			}
		}
		return false
	}

	// Default: pass
	return true
}

var fmt_ = struct{ Sprint func(interface{}) string }{
	Sprint: func(v interface{}) string {
		return strings.TrimSpace(strings.Replace(strings.Replace(strings.Replace(strings.Replace(strings.Replace(
			stringOf(v), "{", "", -1), "}", "", -1), "[", "", -1), "]", "", -1), " ", "", -1))
	},
}

func stringOf(v interface{}) string {
	switch val := v.(type) {
	case string:
		return val
	case bool:
		if val {
			return "true"
		}
		return "false"
	case int, int64, float64:
		return strings.TrimSpace(strings.Split(fmt.Sprintf("%v", val), ".")[0])
	default:
		return fmt.Sprintf("%v", val)
	}
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_eval.go"

cat > internal/policy/cedar_eval_test.go << 'ENDOFFILE'
package policy_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestCedarEvalPermit(t *testing.T) {
	policies, _ := policy.ParseCedarPolicies(`
permit(principal, action, resource);
`)
	eval := policy.NewCedarEvaluator(policies)
	resp, err := eval.IsAuthorized(context.Background(), policy.CedarRequest{
		PrincipalType: "user", PrincipalID: "alice",
		Action: "view", ResourceType: "account", ResourceID: "acme",
	})
	if err != nil {
		t.Fatalf("IsAuthorized() error = %v", err)
	}
	if !resp.Allowed {
		t.Error("expected ALLOWED with blanket permit policy")
	}
}

func TestCedarEvalForbidWins(t *testing.T) {
	policies, _ := policy.ParseCedarPolicies(`
permit(principal, action, resource);
forbid(principal, action, resource) when { frozen == true };
`)
	eval := policy.NewCedarEvaluator(policies)
	resp, _ := eval.IsAuthorized(context.Background(), policy.CedarRequest{
		Context: map[string]interface{}{"frozen": true},
	})
	if resp.Allowed {
		t.Error("expected DENIED: forbid should win over permit")
	}
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_eval_test.go"

cat > internal/policy/cedar_analyzer.go << 'ENDOFFILE'
package policy

import "context"

// AnalysisResult holds the result of formal policy analysis.
type AnalysisResult struct {
	Satisfiable bool
	Unreachable []string
	Conflicts   []string
}

// CedarAnalyzer performs static analysis on Cedar policy sets.
type CedarAnalyzer struct{}

// NewCedarAnalyzer creates a new policy analyzer.
func NewCedarAnalyzer() *CedarAnalyzer { return &CedarAnalyzer{} }

// Analyze performs satisfiability and reachability analysis.
// Full implementation would use Z3/CVC5 SMT solver bindings;
// this stub provides the interface contract.
func (ca *CedarAnalyzer) Analyze(_ context.Context, policies []CedarPolicy) (*AnalysisResult, error) {
	result := &AnalysisResult{
		Satisfiable: len(policies) > 0,
	}
	// Detect obvious conflicts: same-scope permit + forbid
	permitActions := map[string]bool{}
	forbidActions := map[string]bool{}
	for _, p := range policies {
		switch p.Effect {
		case EffectPermit:
			permitActions[p.Action] = true
		case EffectForbid:
			forbidActions[p.Action] = true
		}
	}
	for action := range forbidActions {
		if permitActions[action] {
			result.Conflicts = append(result.Conflicts, "permit/forbid overlap on action: "+action)
		}
	}
	return result, nil
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_analyzer.go"

cat > internal/policy/cedar_analyzer_test.go << 'ENDOFFILE'
package policy_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestAnalyzeConflict(t *testing.T) {
	policies := []policy.CedarPolicy{
		{ID: "p1", Effect: policy.EffectPermit, Action: "refund"},
		{ID: "p2", Effect: policy.EffectForbid, Action: "refund"},
	}
	analyzer := policy.NewCedarAnalyzer()
	result, err := analyzer.Analyze(context.Background(), policies)
	if err != nil {
		t.Fatalf("Analyze() error = %v", err)
	}
	if len(result.Conflicts) == 0 {
		t.Error("expected conflict detected")
	}
}
ENDOFFILE
echo "  [OK] internal/policy/cedar_analyzer_test.go"

cat > internal/policy/temporal.go << 'ENDOFFILE'
package policy

import (
	"strings"
	"time"
)

// TemporalCondition types
type TemporalConditionType string

const (
	TemporalWindow      TemporalConditionType = "window"
	TemporalBusinessHrs TemporalConditionType = "business_hours"
	TemporalExpiry      TemporalConditionType = "expiry"
	TemporalDayOfWeek   TemporalConditionType = "day_of_week"
)

// IsWithinBusinessHours checks if now is within business hours in the given timezone.
func IsWithinBusinessHours(now time.Time, timezone, startHHMM, endHHMM string) bool {
	loc, err := time.LoadLocation(timezone)
	if err != nil {
		loc = time.UTC
	}
	local := now.In(loc)
	startH, startM := parseHHMM(startHHMM)
	endH, endM := parseHHMM(endHHMM)
	startMins := startH*60 + startM
	endMins := endH*60 + endM
	nowMins := local.Hour()*60 + local.Minute()
	return nowMins >= startMins && nowMins <= endMins
}

// IsExpired returns true if the expiration timestamp is in the past.
func IsExpired(expiration, now time.Time) bool {
	return now.After(expiration)
}

// IsWeekday returns true if now is a weekday (Mon–Fri).
func IsWeekday(now time.Time) bool {
	d := now.Weekday()
	return d >= time.Monday && d <= time.Friday
}

func parseHHMM(hhmm string) (int, int) {
	parts := strings.SplitN(hhmm, ":", 2)
	if len(parts) != 2 {
		return 0, 0
	}
	var h, m int
	_, _ = parseDigits(parts[0], &h)
	_, _ = parseDigits(parts[1], &m)
	return h, m
}

func parseDigits(s string, out *int) (int, error) {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			break
		}
		n = n*10 + int(c-'0')
	}
	*out = n
	return n, nil
}
ENDOFFILE
echo "  [OK] internal/policy/temporal.go"

cat > internal/policy/temporal_test.go << 'ENDOFFILE'
package policy_test

import (
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestIsWithinBusinessHours(t *testing.T) {
	// Monday 10:00 UTC
	monday10am := time.Date(2024, 1, 8, 10, 0, 0, 0, time.UTC)
	if !policy.IsWithinBusinessHours(monday10am, "UTC", "09:00", "17:00") {
		t.Error("10am should be within 9-5 business hours")
	}
	// Monday 20:00 UTC
	monday8pm := time.Date(2024, 1, 8, 20, 0, 0, 0, time.UTC)
	if policy.IsWithinBusinessHours(monday8pm, "UTC", "09:00", "17:00") {
		t.Error("8pm should be outside 9-5 business hours")
	}
}

func TestIsExpired(t *testing.T) {
	past := time.Now().Add(-1 * time.Hour)
	if !policy.IsExpired(past, time.Now()) {
		t.Error("past time should be expired")
	}
	future := time.Now().Add(1 * time.Hour)
	if policy.IsExpired(future, time.Now()) {
		t.Error("future time should not be expired")
	}
}
ENDOFFILE
echo "  [OK] internal/policy/temporal_test.go"

cat > internal/policy/abac.go << 'ENDOFFILE'
package policy

import "context"

// ABACRequest holds attribute-based access control inputs.
type ABACRequest struct {
	PrincipalAttrs map[string]interface{}
	ResourceAttrs  map[string]interface{}
	Context        map[string]interface{}
}

// ABACResult is the outcome of an ABAC evaluation.
type ABACResult struct {
	Allowed bool
	Reason  string
}

// EvaluateABAC runs attribute-based checks against defined rules.
func EvaluateABAC(_ context.Context, req ABACRequest, rules []ABACRule) ABACResult {
	for _, rule := range rules {
		if !rule.Matches(req) {
			continue
		}
		if rule.Effect == "deny" {
			return ABACResult{Allowed: false, Reason: rule.Name + ": DENY"}
		}
	}
	return ABACResult{Allowed: true, Reason: "all ABAC checks passed"}
}

// ABACRule is a simple attribute-based rule.
type ABACRule struct {
	Name   string
	Effect string // "allow" | "deny"
	// Matcher is a function that returns true when this rule applies.
	Matches func(ABACRequest) bool
}
ENDOFFILE
echo "  [OK] internal/policy/abac.go"

cat > internal/policy/abac_test.go << 'ENDOFFILE'
package policy_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestEvaluateABAC(t *testing.T) {
	rules := []policy.ABACRule{
		{
			Name:   "block_unverified_payouts",
			Effect: "deny",
			Matches: func(req policy.ABACRequest) bool {
				v, _ := req.PrincipalAttrs["kyc_status"].(string)
				return v != "verified"
			},
		},
	}
	req := policy.ABACRequest{
		PrincipalAttrs: map[string]interface{}{"kyc_status": "pending"},
	}
	result := policy.EvaluateABAC(context.Background(), req, rules)
	if result.Allowed {
		t.Error("expected DENY for non-KYC-verified user")
	}

	req2 := policy.ABACRequest{
		PrincipalAttrs: map[string]interface{}{"kyc_status": "verified"},
	}
	result2 := policy.EvaluateABAC(context.Background(), req2, rules)
	if !result2.Allowed {
		t.Error("expected ALLOW for KYC-verified user")
	}
}
ENDOFFILE
echo "  [OK] internal/policy/abac_test.go"

cat > internal/policy/engine.go << 'ENDOFFILE'
package policy

import (
	"context"
	"fmt"
	"time"
)

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
	store    *PolicyStore
	evaluator *CedarEvaluator
	analyzer  *CedarAnalyzer
}

// NewEngine creates a new policy engine.
func NewEngine(store *PolicyStore) *Engine {
	return &Engine{
		store:    store,
		evaluator: NewCedarEvaluator(nil),
		analyzer:  NewCedarAnalyzer(),
	}
}

// Evaluate runs Cedar policies against the request.
func (e *Engine) Evaluate(ctx context.Context, req *PolicyEvalRequest) (*PolicyDecision, error) {
	start := time.Now()

	policies, _, err := e.store.Read(ctx)
	if err != nil {
		return nil, fmt.Errorf("reading policies: %w", err)
	}

	if policies == "" {
		// No policies deployed → deny by default
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
	parsed, err := ParseCedarPolicies(policySource)
	if err != nil {
		return "", nil, fmt.Errorf("parsing policies: %w", err)
	}

	var warnings []string
	if e.evaluator != nil {
		analysis, err := e.analyzer.Analyze(ctx, parsed)
		if err == nil && len(analysis.Conflicts) > 0 {
			for _, c := range analysis.Conflicts {
				warnings = append(warnings, "conflict: "+c)
			}
		}
	}

	version, err := e.store.Write(ctx, policySource)
	if err != nil {
		return "", warnings, err
	}
	return version, warnings, nil
}
ENDOFFILE
echo "  [OK] internal/policy/engine.go"

cat > internal/policy/engine_test.go << 'ENDOFFILE'
package policy_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/policy"
)

func TestPolicyEngineEvaluate(t *testing.T) {
	store := policy.NewPolicyStore()
	engine := policy.NewEngine(store)
	ctx := context.Background()

	// No policies → deny by default
	dec, err := engine.Evaluate(ctx, &policy.PolicyEvalRequest{
		Action: "view",
	})
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if dec.Allowed {
		t.Error("expected DENY with no policies")
	}

	// Deploy a permit-all policy
	_, _, err = engine.DeployPolicies(ctx, `permit(principal, action, resource);`)
	if err != nil {
		t.Fatalf("DeployPolicies() error = %v", err)
	}

	dec2, err := engine.Evaluate(ctx, &policy.PolicyEvalRequest{Action: "view"})
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if !dec2.Allowed {
		t.Error("expected ALLOW with permit-all policy")
	}
}
ENDOFFILE
echo "  [OK] internal/policy/engine_test.go"

echo "=== internal/policy/ done ==="
ENDOFFILE
echo "Part 8 script written"
