package memory_test

import (
	"context"
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

func TestWriteAndReadTuples(t *testing.T) {
	b := memory.New()
	ctx := context.Background()

	tuples := []types.Tuple{
		{ResourceType: "account", ResourceID: "acme", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
		{ResourceType: "account", ResourceID: "acme", Relation: "viewer", SubjectType: "user", SubjectID: "bob"},
	}
	rev, err := b.WriteTuples(ctx, tuples)
	if err != nil {
		t.Fatalf("WriteTuples() error = %v", err)
	}
	if rev <= 0 {
		t.Errorf("WriteTuples() revision = %d, want > 0", rev)
	}

	iter, err := b.ReadTuples(ctx, types.TupleFilter{ResourceType: "account", ResourceID: "acme"}, rev)
	if err != nil {
		t.Fatalf("ReadTuples() error = %v", err)
	}
	defer iter.Close()
	count := 0
	for {
		_, err := iter.Next()
		if err != nil {
			break
		}
		count++
	}
	if count != 2 {
		t.Errorf("ReadTuples() count = %d, want 2", count)
	}
}

func TestDeleteTuples(t *testing.T) {
	b := memory.New()
	ctx := context.Background()

	rev1, _ := b.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "acme", Relation: "owner", SubjectType: "user", SubjectID: "alice"},
	})
	rev2, err := b.DeleteTuples(ctx, types.TupleFilter{ResourceType: "account", ResourceID: "acme", Relation: "owner"})
	if err != nil {
		t.Fatalf("DeleteTuples() error = %v", err)
	}

	iter, _ := b.ReadTuples(ctx, types.TupleFilter{ResourceType: "account", ResourceID: "acme"}, rev2)
	defer iter.Close()
	_, err = iter.Next()
	if err == nil {
		t.Error("expected no results after delete")
	}

	// At old snapshot, tuple still visible
	iter2, _ := b.ReadTuples(ctx, types.TupleFilter{ResourceType: "account", ResourceID: "acme"}, rev1)
	defer iter2.Close()
	tup, err := iter2.Next()
	if err != nil || tup == nil {
		t.Error("expected tuple visible at old snapshot")
	}
}

func TestWatchEvents(t *testing.T) {
	b := memory.New()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	ch, err := b.Watch(ctx, 0)
	if err != nil {
		t.Fatalf("Watch() error = %v", err)
	}

	b.WriteTuples(ctx, []types.Tuple{
		{ResourceType: "account", ResourceID: "x", Relation: "owner", SubjectType: "user", SubjectID: "u1"},
	})

	select {
	case event := <-ch:
		if event.Type != storage.WatchEventCreate {
			t.Errorf("event.Type = %s, want CREATE", event.Type)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("did not receive watch event")
	}
}

func TestAuditLog(t *testing.T) {
	b := memory.New()
	ctx := context.Background()
	now := time.Now()

	records := []storage.DecisionRecord{
		{ID: "1", Timestamp: now, SubjectID: "alice", Allowed: true, Verdict: "ALLOWED"},
		{ID: "2", Timestamp: now, SubjectID: "bob", Allowed: false, Verdict: "DENIED"},
	}
	if err := b.AppendDecisions(ctx, records); err != nil {
		t.Fatalf("AppendDecisions() error = %v", err)
	}

	results, err := b.QueryDecisions(ctx, storage.AuditFilter{SubjectID: "alice"})
	if err != nil {
		t.Fatalf("QueryDecisions() error = %v", err)
	}
	if len(results) != 1 || results[0].SubjectID != "alice" {
		t.Errorf("got %d results, want 1 for alice", len(results))
	}
}
