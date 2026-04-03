package compliance_test

import (
	"context"
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/compliance"
	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
)

func TestComplianceAllClear(t *testing.T) {
	store := memory.New()
	engine := compliance.NewEngine(store, nil)
	ctx := context.Background()

	dec, err := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID: "alice", ResourceType: "account", ResourceID: "acme", Action: "view",
	})
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if !dec.Allowed {
		t.Errorf("expected ALLOWED, violations: %v", dec.Violations)
	}
}

func TestComplianceSanctionsHit(t *testing.T) {
	store := memory.New()
	ctx := context.Background()
	store.WriteSanctionsList(ctx, "OFAC", []storage.SanctionsEntry{
		{Name: "Vladimir Putin", ListType: "OFAC"},
	})
	engine := compliance.NewEngine(store, nil)

	dec, err := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID: "Vladimir Putin", ResourceType: "account", ResourceID: "acme", Action: "view",
	})
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if dec.Allowed {
		t.Error("sanctions hit should DENY")
	}
}

func TestComplianceKYCBlocks(t *testing.T) {
	store := memory.New()
	engine := compliance.NewEngine(store, func(_ context.Context, _ string) (compliance.KYCTier, error) {
		return compliance.KYCTier1, nil
	})
	ctx := context.Background()

	dec, _ := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID: "bob", Action: "transfer",
	})
	if dec.Allowed {
		t.Error("Tier1 subject should not pass Tier2 transfer action")
	}
}

func TestComplianceFreezeBlocks(t *testing.T) {
	store := memory.New()
	ctx := context.Background()
	store.WriteFreeze(ctx, storage.AccountFreeze{
		AccountID: "frozen-acct", Reason: "fraud", Authority: "compliance", FrozenAt: time.Now(),
	})
	engine := compliance.NewEngine(store, nil)
	dec, _ := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID: "alice", ResourceID: "frozen-acct", Action: "view",
	})
	if dec.Allowed {
		t.Error("frozen account should be DENIED")
	}
}

func TestComplianceRegulatoryBlocks(t *testing.T) {
	store := memory.New()
	ctx := context.Background()
	store.WriteRegulatoryOverride(ctx, storage.RegulatoryOverride{
		ResourceID: "locked-acct", Reason: "AML investigation", Authority: "FinCEN",
		IssuedAt: time.Now().Add(-time.Hour), Active: true,
	})
	engine := compliance.NewEngine(store, nil)
	dec, _ := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID: "alice", ResourceID: "locked-acct", Action: "view",
	})
	if dec.Allowed {
		t.Error("regulatory hold should be DENIED")
	}
}
