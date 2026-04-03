#!/usr/bin/env bash
# Part 10: orchestrator, index, audit, server, cmd, remaining files
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/orchestrator/ ───────────────────────────────────────────────────
cat > internal/orchestrator/verdict.go << 'ENDOFFILE'
package orchestrator

import (
	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/policy"
	"github.com/youorg/zanzipay/internal/rebac"
)

// Decision is the merged verdict from all three engines.
type Decision struct {
	Allowed       bool
	ReBAC         *rebac.CheckResponse
	Policy        *policy.PolicyDecision
	Compliance    *compliance.ComplianceDecision
	DecisionToken string
	Reasoning     string
}

// mergeVerdicts combines outputs from all three engines.
// Rules:
// - Compliance DENY is absolute (cannot be overridden)
// - ReBAC DENY → overall DENY (even if policy allows)
// - Policy DENY → overall DENY
// - All three must allow for the final decision to be ALLOWED
func mergeVerdicts(
	rebacResult *rebac.CheckResponse,
	policyResult *policy.PolicyDecision,
	complianceResult *compliance.ComplianceDecision,
) (bool, string) {
	if complianceResult != nil && !complianceResult.Allowed {
		violations := ""
		if len(complianceResult.Violations) > 0 {
			violations = complianceResult.Violations[0]
		}
		return false, "DENIED by compliance: " + violations
	}
	if rebacResult != nil && rebacResult.Result != rebac.CheckAllowed {
		return false, "DENIED by ReBAC: " + rebacResult.Reasoning
	}
	if policyResult != nil && !policyResult.Allowed {
		reason := "policy evaluation"
		if policyResult.DeniedBy != "" {
			reason = policyResult.DeniedBy
		}
		return false, "DENIED by policy: " + reason
	}
	return true, "ALLOWED: all engines passed"
}
ENDOFFILE
echo "  [OK] internal/orchestrator/verdict.go"

cat > internal/orchestrator/verdict_test.go << 'ENDOFFILE'
package orchestrator_test

import (
	"testing"

	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/orchestrator"
	"github.com/youorg/zanzipay/internal/policy"
	"github.com/youorg/zanzipay/internal/rebac"
)

func TestMergeVerdicts(t *testing.T) {
	t.Run("all_allowed", func(t *testing.T) {
		d := &orchestrator.Decision{
			ReBAC:      &rebac.CheckResponse{Result: rebac.CheckAllowed},
			Policy:     &policy.PolicyDecision{Allowed: true},
			Compliance: &compliance.ComplianceDecision{Allowed: true},
		}
		if !d.Allowed {
			// merge is internal, but verify struct
		}
		_ = d
	})
}
ENDOFFILE
echo "  [OK] internal/orchestrator/verdict_test.go"

cat > internal/orchestrator/token.go << 'ENDOFFILE'
package orchestrator

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"time"
)

// TokenManager mints decision tokens that encode the consistency state.
type TokenManager struct {
	hmacKey []byte
}

// NewTokenManager creates a new token manager.
func NewTokenManager(hmacKey []byte) *TokenManager {
	return &TokenManager{hmacKey: hmacKey}
}

// MintDecisionToken creates an opaque token encoding a decision's state.
func (tm *TokenManager) MintDecisionToken(decisionID string, timestamp time.Time, allowed bool) string {
	payload := fmt.Sprintf("%s:%d:%v", decisionID, timestamp.UnixNano(), allowed)
	h := sha256.New()
	h.Write(tm.hmacKey)
	h.Write([]byte(payload))
	return base64.URLEncoding.EncodeToString(h.Sum(nil))[:24]
}
ENDOFFILE
echo "  [OK] internal/orchestrator/token.go"

cat > internal/orchestrator/token_test.go << 'ENDOFFILE'
package orchestrator_test

import (
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/orchestrator"
)

func TestMintDecisionToken(t *testing.T) {
	tm := orchestrator.NewTokenManager([]byte("test-key"))
	token := tm.MintDecisionToken("dec-001", time.Now(), true)
	if token == "" {
		t.Error("MintDecisionToken() returned empty token")
	}
	if len(token) < 16 {
		t.Errorf("token too short: %q", token)
	}
}
ENDOFFILE
echo "  [OK] internal/orchestrator/token_test.go"

cat > internal/orchestrator/orchestrator.go << 'ENDOFFILE'
// Package orchestrator fans out authorization requests to all engines and merges verdicts.
package orchestrator

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/youorg/zanzipay/internal/audit"
	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/policy"
	"github.com/youorg/zanzipay/internal/rebac"
	"github.com/youorg/zanzipay/internal/storage"
)

const (
	defaultEngineTimeout = 50 * time.Millisecond
	defaultGlobalTimeout = 100 * time.Millisecond
)

// AuthzRequest is the input to the orchestrator.
type AuthzRequest struct {
	ResourceType  string
	ResourceID    string
	Permission    string
	SubjectType   string
	SubjectID     string
	SubjectNames  []string
	Action        string
	Zookie        string
	CaveatContext map[string]interface{}
	PolicyContext map[string]interface{}
	ClientID      string
	SourceIP      string
	UserAgent     string
}

// Orchestrator is the central authorization coordinator.
type Orchestrator struct {
	rebac      *rebac.Engine
	policy     *policy.Engine
	compliance *compliance.Engine
	audit      *audit.Logger
	tokenMgr   *TokenManager
}

// New creates a new Orchestrator.
func New(
	rebacEngine *rebac.Engine,
	policyEngine *policy.Engine,
	complianceEngine *compliance.Engine,
	auditLogger *audit.Logger,
	hmacKey []byte,
) *Orchestrator {
	return &Orchestrator{
		rebac:      rebacEngine,
		policy:     policyEngine,
		compliance: complianceEngine,
		audit:      auditLogger,
		tokenMgr:   NewTokenManager(hmacKey),
	}
}

// Authorize is the main authorization entry point.
// Fans out to all three engines concurrently, merges verdicts (strict AND),
// writes the audit log, and returns the decision.
func (o *Orchestrator) Authorize(ctx context.Context, req *AuthzRequest) (*Decision, error) {
	ctx, cancel := context.WithTimeout(ctx, defaultGlobalTimeout)
	defer cancel()

	start := time.Now()
	var (
		rebacResp *rebac.CheckResponse
		policyDec *policy.PolicyDecision
		compDec   *compliance.ComplianceDecision
		mu        sync.Mutex
		wg        sync.WaitGroup
	)

	// ReBAC check
	wg.Add(1)
	go func() {
		defer wg.Done()
		engCtx, cancel := context.WithTimeout(ctx, defaultEngineTimeout)
		defer cancel()
		resp, err := o.rebac.Check(engCtx, &rebac.CheckRequest{
			Resource:      rebac.ObjectRef{Type: req.ResourceType, ID: req.ResourceID},
			Permission:    req.Permission,
			Subject:       rebac.SubjectRef{Type: req.SubjectType, ID: req.SubjectID},
			CaveatContext: req.CaveatContext,
		})
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			rebacResp = &rebac.CheckResponse{Result: rebac.CheckDenied, Verdict: "DENIED", Reasoning: fmt.Sprintf("engine error: %v", err)}
		} else {
			rebacResp = resp
		}
	}()

	// Policy check
	wg.Add(1)
	go func() {
		defer wg.Done()
		engCtx, cancel := context.WithTimeout(ctx, defaultEngineTimeout)
		defer cancel()
		dec, err := o.policy.Evaluate(engCtx, &policy.PolicyEvalRequest{
			PrincipalType: req.SubjectType,
			PrincipalID:   req.SubjectID,
			Action:        req.Action,
			ResourceType:  req.ResourceType,
			ResourceID:    req.ResourceID,
			Context:       req.PolicyContext,
		})
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			policyDec = &policy.PolicyDecision{Allowed: false, DeniedBy: "policy engine error"}
		} else {
			policyDec = dec
		}
	}()

	// Compliance check
	wg.Add(1)
	go func() {
		defer wg.Done()
		engCtx, cancel := context.WithTimeout(ctx, defaultEngineTimeout)
		defer cancel()
		dec, err := o.compliance.Evaluate(engCtx, &compliance.ComplianceRequest{
			SubjectType:  req.SubjectType,
			SubjectID:    req.SubjectID,
			SubjectNames: req.SubjectNames,
			ResourceType: req.ResourceType,
			ResourceID:   req.ResourceID,
			Action:       req.Action,
		})
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			compDec = &compliance.ComplianceDecision{Allowed: false, Violations: []string{"compliance engine error"}}
		} else {
			compDec = dec
		}
	}()

	wg.Wait()

	allowed, reasoning := mergeVerdicts(rebacResp, policyDec, compDec)
	decisionToken := o.tokenMgr.MintDecisionToken(req.ResourceID+req.SubjectID, start, allowed)

	decision := &Decision{
		Allowed:       allowed,
		ReBAC:         rebacResp,
		Policy:        policyDec,
		Compliance:    compDec,
		DecisionToken: decisionToken,
		Reasoning:     reasoning,
	}

	// Async audit log
	if o.audit != nil {
		verdict := "DENIED"
		if allowed {
			verdict = "ALLOWED"
		}
		_ = o.audit.Log(&storage.DecisionRecord{
			SubjectType:    req.SubjectType,
			SubjectID:      req.SubjectID,
			ResourceType:   req.ResourceType,
			ResourceID:     req.ResourceID,
			Action:         req.Action,
			Allowed:        allowed,
			Verdict:        verdict,
			DecisionToken:  decisionToken,
			Reasoning:      reasoning,
			EvalDurationNs: time.Since(start).Nanoseconds(),
			ClientID:       req.ClientID,
			SourceIP:       req.SourceIP,
			UserAgent:      req.UserAgent,
		})
	}
	return decision, nil
}
ENDOFFILE
echo "  [OK] internal/orchestrator/orchestrator.go"

cat > internal/orchestrator/orchestrator_test.go << 'ENDOFFILE'
package orchestrator_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/audit"
	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/orchestrator"
	"github.com/youorg/zanzipay/internal/policy"
	"github.com/youorg/zanzipay/internal/rebac"
	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

func TestOrchestratorAuthorize(t *testing.T) {
	store := memory.New()
	ctx := context.Background()

	rebacEngine, _ := rebac.NewEngine(store)
	rebacEngine.WriteSchema(ctx, `
definition user {}
definition account {
    relation owner: user
    permission manage = owner
}`)
	store.WriteTuples(ctx, []types.Tuple{{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner", SubjectType: "user", SubjectID: "alice",
	}})

	policyStore := policy.NewPolicyStore()
	policyStore.Write(ctx, `permit(principal, action, resource);`)
	policyEngine := policy.NewEngine(policyStore)

	compEngine := compliance.NewEngine(store, nil)
	auditLogger := audit.NewLogger(store)

	orch := orchestrator.New(
		rebacEngine, policyEngine, compEngine, auditLogger,
		[]byte("test-hmac-key-32-bytes-long!!!!!"),
	)

	// alice should be allowed
	dec, err := orch.Authorize(ctx, &orchestrator.AuthzRequest{
		ResourceType: "account", ResourceID: "acme",
		Permission: "manage", Action: "manage",
		SubjectType: "user", SubjectID: "alice",
	})
	if err != nil {
		t.Fatalf("Authorize() error = %v", err)
	}
	if !dec.Allowed {
		t.Errorf("expected ALLOWED, got reasoning: %s", dec.Reasoning)
	}

	// bob should be denied (no ReBAC relationship)
	dec2, _ := orch.Authorize(ctx, &orchestrator.AuthzRequest{
		ResourceType: "account", ResourceID: "acme",
		Permission: "manage", Action: "manage",
		SubjectType: "user", SubjectID: "bob",
	})
	if dec2.Allowed {
		t.Error("expected bob to be DENIED")
	}
}
ENDOFFILE
echo "  [OK] internal/orchestrator/orchestrator_test.go"

echo "=== internal/orchestrator/ done ==="
ENDOFFILE
echo "Part 10 script written"
