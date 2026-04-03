package compliance

import (
	"context"
)

// FreezeResult holds whether an account is frozen.
type FreezeResult struct {
	Frozen bool
	Reason string
}

func (e *Engine) checkFreeze(ctx context.Context, accountID string) (*FreezeResult, error) {
	freezes, err := e.store.ReadFreezes(ctx, accountID)
	if err != nil {
		return nil, err
	}
	for _, f := range freezes {
		if f.LiftedAt == nil {
			return &FreezeResult{Frozen: true, Reason: f.Reason}, nil
		}
	}
	return &FreezeResult{Frozen: false}, nil
}
