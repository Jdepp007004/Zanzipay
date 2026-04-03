package rebac_test

import (
	"context"
	"testing"

	"github.com/Jdepp007004/Zanzipay/internal/rebac"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

const testSchema = `
definition user {}

definition team {
	relation member: user
	relation admin: user
	permission access = admin + member
}

definition account {
	relation owner: user
	relation viewer: user
	relation org: team
	permission manage = owner
	permission view = owner + viewer + org->access
}
`

func TestEngineSimpleCheck(t *testing.T) {
	store := memory.New()
	engine, err := rebac.NewEngine(store)
	if err != nil {
		t.Fatalf("NewEngine() error = %v", err)
	}
	ctx := context.Background()

	if err := engine.WriteSchema(ctx, testSchema); err != nil {
		t.Fatalf("WriteSchema() error = %v", err)
	}

	_, err = engine.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "acme", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
	})
	if err != nil {
		t.Fatalf("WriteTuples() error = %v", err)
	}

	resp, err := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    rebac.SubjectRef{Type: "user", ID: "alice"},
	})
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if resp.Result != rebac.CheckAllowed {
		t.Errorf("alice should be ALLOWED to manage; got %s: %s", resp.Verdict, resp.Reasoning)
	}

	resp2, _ := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    rebac.SubjectRef{Type: "user", ID: "bob"},
	})
	if resp2.Result != rebac.CheckDenied {
		t.Error("bob should be DENIED")
	}
}

func TestEngineUnionPermission(t *testing.T) {
	store := memory.New()
	engine, _ := rebac.NewEngine(store)
	ctx := context.Background()
	engine.WriteSchema(ctx, testSchema)

	engine.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "doc", Relation: "viewer", SubjectType: "user", SubjectID: "bob"},
	})

	resp, _ := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "doc"},
		Permission: "view",
		Subject:    rebac.SubjectRef{Type: "user", ID: "bob"},
	})
	if resp.Result != rebac.CheckAllowed {
		t.Errorf("bob (viewer) should have view permission; got %s", resp.Verdict)
	}
}

func TestEngineArrowPermission(t *testing.T) {
	store := memory.New()
	engine, _ := rebac.NewEngine(store)
	ctx := context.Background()
	engine.WriteSchema(ctx, testSchema)

	// alice is member of eng team
	engine.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "team", ResourceID: "eng", Relation: "member", SubjectType: "user", SubjectID: "alice"},
		{ResourceType: "account", ResourceID: "acme", Relation: "org", SubjectType: "team", SubjectID: "eng"},
	})

	// alice should have view via org->access (team#member included in access)
	resp, err := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "view",
		Subject:    rebac.SubjectRef{Type: "user", ID: "alice"},
	})
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if resp.Result != rebac.CheckAllowed {
		t.Errorf("alice (via team->org) should have view; got %s", resp.Verdict)
	}
}

func TestEngineZookie(t *testing.T) {
	store := memory.New()
	engine, _ := rebac.NewEngine(store)
	ctx := context.Background()
	engine.WriteSchema(ctx, testSchema)

	zookie, err := engine.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "z", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
	})
	if err != nil {
		t.Fatalf("WriteTuples() error = %v", err)
	}
	if zookie == "" {
		t.Fatal("expected non-empty zookie")
	}
	if len(zookie) < 10 {
		t.Errorf("zookie too short: %q", zookie)
	}
}
