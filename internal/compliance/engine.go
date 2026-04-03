// Package compliance implements the financial compliance engine.
package compliance

import (
	"context"
	"sync"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

// SanctionsResult holds the result of a sanctions check.
type SanctionsResult struct {
	Matched   bool
	Matches   []SanctionsMatch
	RiskScore float64
}

// SanctionsMatch is a single positive result from a sanctions check.
type SanctionsMatch struct {
	ListType    string
	MatchedName string
	QueryName   string
	Score       float64
}

// ComplianceRequest is the input to the compliance engine.
type ComplianceRequest struct {
	SubjectType  string
	SubjectID    string
	SubjectNames []string
	ResourceType string
	ResourceID   string
	Action       string
	Context      map[string]interface{}
}

// ComplianceDecision is the output of the compliance engine.
type ComplianceDecision struct {
	Allowed    bool
	Violations []string
	RiskScore  float64
	Sanctions  *SanctionsResult
	KYC        *KYCResult
	Regulatory *RegulatoryResult
	Freeze     *FreezeResult
}

// Engine is the compliance engine.
type Engine struct {
	store       storage.ComplianceStore
	kycResolver func(context.Context, string) (KYCTier, error)
}

// NewEngine creates a new compliance engine.
func NewEngine(store storage.ComplianceStore, kycResolver func(context.Context, string) (KYCTier, error)) *Engine {
	if kycResolver == nil {
		kycResolver = func(_ context.Context, _ string) (KYCTier, error) { return KYCTier1, nil }
	}
	return &Engine{store: store, kycResolver: kycResolver}
}

// Evaluate runs all compliance checks in parallel.
func (e *Engine) Evaluate(ctx context.Context, req *ComplianceRequest) (*ComplianceDecision, error) {
	decision := &ComplianceDecision{Allowed: true}
	var mu sync.Mutex
	var wg sync.WaitGroup
	var firstErr error

	addViolation := func(v string) {
		mu.Lock()
		decision.Violations = append(decision.Violations, v)
		decision.Allowed = false
		mu.Unlock()
	}

	// Sanctions screening
	wg.Add(1)
	go func() {
		defer wg.Done()
		names := req.SubjectNames
		if len(names) == 0 {
			names = []string{req.SubjectID}
		}
		result, err := e.screenSanctions(ctx, names)
		if err != nil {
			mu.Lock()
			firstErr = err
			mu.Unlock()
			return
		}
		mu.Lock()
		decision.Sanctions = result
		if result.Matched {
			decision.Allowed = false
			decision.Violations = append(decision.Violations, "SANCTIONS: entity matched sanctions list")
			if result.RiskScore > decision.RiskScore {
				decision.RiskScore = result.RiskScore
			}
		}
		mu.Unlock()
	}()

	// KYC check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.checkKYC(ctx, req.SubjectID, req.Action)
		if err != nil {
			return
		}
		mu.Lock()
		decision.KYC = result
		mu.Unlock()
		if !result.Passed {
			addViolation("KYC: " + result.Reason)
		}
	}()

	// Regulatory override check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.checkRegulatory(ctx, req.ResourceID)
		if err != nil {
			return
		}
		mu.Lock()
		decision.Regulatory = result
		mu.Unlock()
		if result.Blocked {
			addViolation("REGULATORY: " + result.Reason)
		}
	}()

	// Account freeze check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.checkFreeze(ctx, req.ResourceID)
		if err != nil {
			return
		}
		mu.Lock()
		decision.Freeze = result
		mu.Unlock()
		if result.Frozen {
			addViolation("FREEZE: " + result.Reason)
		}
	}()

	wg.Wait()
	return decision, firstErr
}

