package compliance

import (
	"context"
	"fmt"
)

// KYCTier is the minimum KYC verification level.
type KYCTier int

const (
	KYCTier1 KYCTier = 1
	KYCTier2 KYCTier = 2
	KYCTier3 KYCTier = 3
)

// ActionKYCRequirements maps action names to required KYC tiers.
var ActionKYCRequirements = map[string]KYCTier{
	"view":              KYCTier1,
	"read_balance":      KYCTier1,
	"transfer":          KYCTier2,
	"refund":            KYCTier2,
	"initiate_payout":   KYCTier2,
	"large_transfer":    KYCTier3,
	"regulatory_report": KYCTier3,
}

// KYCResult holds the result of a KYC gate check.
type KYCResult struct {
	Passed       bool
	SubjectTier  KYCTier
	RequiredTier KYCTier
	Reason       string
}

func (e *Engine) checkKYC(ctx context.Context, subjectID, action string) (*KYCResult, error) {
	required, ok := ActionKYCRequirements[action]
	if !ok {
		required = KYCTier1
	}
	tier, err := e.kycResolver(ctx, subjectID)
	if err != nil {
		return nil, fmt.Errorf("resolving KYC for %s: %w", subjectID, err)
	}
	result := &KYCResult{SubjectTier: tier, RequiredTier: required}
	if tier >= required {
		result.Passed = true
		result.Reason = fmt.Sprintf("KYC tier %d >= required %d", tier, required)
	} else {
		result.Passed = false
		result.Reason = fmt.Sprintf("KYC tier %d < required %d for %q", tier, required, action)
	}
	return result, nil
}
