// Package orchestrator fans out authorization requests to all engines and merges verdicts.
package orchestrator

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"sync"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/audit"
	"github.com/Jdepp007004/Zanzipay/internal/compliance"
	"github.com/Jdepp007004/Zanzipay/internal/policy"
	"github.com/Jdepp007004/Zanzipay/internal/rebac"
	"github.com/Jdepp007004/Zanzipay/internal/storage"
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

// Decision is the merged verdict from all three engines.
type Decision struct {
	Allowed       bool
	ReBAC         *rebac.CheckResponse
	Policy        *policy.PolicyDecision
	Compliance    *compliance.ComplianceDecision
	DecisionToken string
	Reasoning     string
}

// Orchestrator is the central authorization coordinator.
type Orchestrator struct {
	rebac      *rebac.Engine
	policy     *policy.Engine
	compliance *compliance.Engine
	audit      *audit.Logger
	hmacKey    []byte
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
		hmacKey:    hmacKey,
	}
}

// Authorize is the main authorization entry point.
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
			rebacResp = &rebac.CheckResponse{Result: rebac.CheckDenied, Verdict: "DENIED", Reasoning: fmt.Sprintf("rebac error: %v", err)}
		} else {
			rebacResp = resp
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		engCtx, cancel := context.WithTimeout(ctx, defaultEngineTimeout)
		defer cancel()
		dec, err := o.policy.Evaluate(engCtx, &policy.PolicyEvalRequest{
			PrincipalType: req.SubjectType, PrincipalID: req.SubjectID,
			Action: req.Action, ResourceType: req.ResourceType, ResourceID: req.ResourceID,
			Context: policy.EnrichContextWithTime(req.PolicyContext),
		})
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			policyDec = &policy.PolicyDecision{Allowed: false, DeniedBy: "policy engine error"}
		} else {
			policyDec = dec
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		engCtx, cancel := context.WithTimeout(ctx, defaultEngineTimeout)
		defer cancel()
		dec, err := o.compliance.Evaluate(engCtx, &compliance.ComplianceRequest{
			SubjectType:  req.SubjectType, SubjectID: req.SubjectID,
			SubjectNames: req.SubjectNames,
			ResourceType: req.ResourceType, ResourceID: req.ResourceID,
			Action: req.Action,
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
	decisionToken := mintToken(o.hmacKey, req.ResourceID+req.SubjectID, start, allowed)

	decision := &Decision{
		Allowed:       allowed,
		ReBAC:         rebacResp,
		Policy:        policyDec,
		Compliance:    compDec,
		DecisionToken: decisionToken,
		Reasoning:     reasoning,
	}

	if o.audit != nil {
		verdict := "DENIED"
		if allowed {
			verdict = "ALLOWED"
		}
		_ = o.audit.Log(&storage.DecisionRecord{
			SubjectType: req.SubjectType, SubjectID: req.SubjectID,
			ResourceType: req.ResourceType, ResourceID: req.ResourceID,
			Action: req.Action, Allowed: allowed, Verdict: verdict,
			DecisionToken: decisionToken, Reasoning: reasoning,
			EvalDurationNs: time.Since(start).Nanoseconds(),
			ClientID: req.ClientID, SourceIP: req.SourceIP, UserAgent: req.UserAgent,
		})
	}
	return decision, nil
}

func mergeVerdicts(r *rebac.CheckResponse, p *policy.PolicyDecision, c *compliance.ComplianceDecision) (bool, string) {
	if c != nil && !c.Allowed {
		v := "compliance violation"
		if len(c.Violations) > 0 {
			v = c.Violations[0]
		}
		return false, "DENIED by compliance: " + v
	}
	if r != nil && r.Result != rebac.CheckAllowed {
		return false, "DENIED by ReBAC: " + r.Reasoning
	}
	if p != nil && !p.Allowed {
		reason := "policy evaluation"
		if p.DeniedBy != "" {
			reason = p.DeniedBy
		}
		return false, "DENIED by policy: " + reason
	}
	return true, "ALLOWED: all engines passed"
}

func mintToken(key []byte, seed string, ts time.Time, allowed bool) string {
	payload := fmt.Sprintf("%s:%d:%v", seed, ts.UnixNano(), allowed)
	h := sha256.New()
	h.Write(key)
	h.Write([]byte(payload))
	return base64.URLEncoding.EncodeToString(h.Sum(nil))[:24]
}
