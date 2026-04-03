package index_test

import (
	"context"
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/index"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

func TestMaterializerLookup(t *testing.T) {
	store := memory.New()
	mat, err := index.NewMaterializer(store)
	if err != nil {
		t.Fatalf("NewMaterializer() error = %v", err)
	}

	key := index.IndexKey{SubjectType: "user", SubjectID: "alice", ResourceType: "account", Permission: "view"}
	mat.IndexSet(key, "acme")
	mat.IndexSet(key, "initech")

	ctx := context.Background()
	results, err := mat.LookupResources(ctx, "user", "alice", "account", "view")
	if err != nil {
		t.Fatalf("LookupResources() error = %v", err)
	}
	if len(results) != 2 {
		t.Errorf("expected 2 results, got %d", len(results))
	}
}

func TestMaterializerStats(t *testing.T) {
	store := memory.New()
	mat, _ := index.NewMaterializer(store)
	stats := mat.Stats()
	if stats["total_entries"] != 0 {
		t.Errorf("expected 0 entries, got %d", stats["total_entries"])
	}
	mat.IndexSet(index.IndexKey{SubjectType: "user", SubjectID: "x", ResourceType: "account", Permission: "view"}, "y")
	stats = mat.Stats()
	if stats["total_entries"] != 1 {
		t.Errorf("expected 1 entry, got %d", stats["total_entries"])
	}
}

func TestMaterializerWatchIntegration(t *testing.T) {
	store := memory.New()
	mat, _ := index.NewMaterializer(store)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	mat.Start(ctx)

	store.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "acme", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
	})
	time.Sleep(100 * time.Millisecond)

	results, _ := mat.LookupResources(ctx, "user", "alice", "account", "owner")
	if len(results) != 1 || results[0] != "acme" {
		t.Errorf("expected [acme], got %v", results)
	}
}
