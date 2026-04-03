package compliance

import (
	"context"
	"time"
)

// RegulatoryResult holds the result of a regulatory override check.
type RegulatoryResult struct {
	Blocked   bool
	Reason    string
	Authority string
}

func (e *Engine) checkRegulatory(ctx context.Context, resourceID string) (*RegulatoryResult, error) {
	overrides, err := e.store.ReadRegulatoryOverrides(ctx, resourceID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	for _, o := range overrides {
		if !o.Active {
			continue
		}
		if o.ExpiresAt != nil && now.After(*o.ExpiresAt) {
			continue
		}
		return &RegulatoryResult{Blocked: true, Reason: o.Reason, Authority: o.Authority}, nil
	}
	return &RegulatoryResult{Blocked: false}, nil
}
