package orchestrator_test

import (
	"context"
	"testing"

	"github.com/Jdepp007004/Zanzipay/internal/audit"
	"github.com/Jdepp007004/Zanzipay/internal/compliance"
	"github.com/Jdepp007004/Zanzipay/internal/orchestrator"
	"github.com/Jdepp007004/Zanzipay/internal/policy"
	"github.com/Jdepp007004/Zanzipay/internal/rebac"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

func setupOrchestrator(t *testing.T) (*orchestrator.Orchestrator, *memory.Backend) {
	t.Helper()
	store := memory.New()
	ctx := context.Background()

	rebacEngine, err := rebac.NewEngine(store)
	if err != nil {
		t.Fatalf("NewEngine() error = %v", err)
	}
	rebacEngine.WriteSchema(ctx, `
definition user {}
definition account {
	relation owner: user
	permission manage = owner
	permission view = owner
}`)
	store.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "acme", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
	})

	policyStore := policy.NewPolicyStore()
	policyStore.Write(ctx, `permit(principal, action, resource);`)
	policyEngine := policy.NewEngine(policyStore)

	compEngine := compliance.NewEngine(store, nil)
	auditLogger := audit.NewLogger(store)

	orch := orchestrator.New(rebacEngine, policyEngine, compEngine, auditLogger,
		[]byte("test-hmac-key-32-bytes-long!!!!!"))
	return orch, store
}

func TestOrchestratorAliceAllowed(t *testing.T) {
	orch, _ := setupOrchestrator(t)
	ctx := context.Background()
	dec, err := orch.Authorize(ctx, &orchestrator.AuthzRequest{
		ResourceType: "account", ResourceID: "acme",
		Permission: "manage", Action: "manage",
		SubjectType: "user", SubjectID: "alice",
	})
	if err != nil {
		t.Fatalf("Authorize() error = %v", err)
	}
	if !dec.Allowed {
		t.Errorf("alice should be ALLOWED: %s", dec.Reasoning)
	}
	if dec.DecisionToken == "" {
		t.Error("DecisionToken should be set")
	}
}

func TestOrchestratorBobDenied(t *testing.T) {
	orch, _ := setupOrchestrator(t)
	ctx := context.Background()
	dec, _ := orch.Authorize(ctx, &orchestrator.AuthzRequest{
		ResourceType: "account", ResourceID: "acme",
		Permission: "manage", Action: "manage",
		SubjectType: "user", SubjectID: "bob",
	})
	if dec.Allowed {
		t.Error("bob should be DENIED (no relationship)")
	}
}
