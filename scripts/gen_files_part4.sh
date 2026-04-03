#!/usr/bin/env bash
# Part 4: internal/storage/ — interface + memory + postgres
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/storage/interface.go ───────────────────────────────────────────
cat > internal/storage/interface.go << 'ENDOFFILE'
// Package storage defines the storage interfaces for ZanziPay backends.
package storage

import (
	"context"
	"time"

	"github.com/youorg/zanzipay/pkg/types"
)

// Revision is a logical transaction counter used for zookie consistency.
type Revision = types.Revision

// Backend is the combined storage interface for all ZanziPay subsystems.
type Backend interface {
	TupleStore
	PolicyStore
	ComplianceStore
	AuditStore
	ChangelogStore
	Close() error
}

// WatchEvent represents a change to a relationship tuple.
type WatchEvent struct {
	Type      WatchEventType
	Tuple     types.Tuple
	Revision  Revision
	Timestamp time.Time
}

// WatchEventType enumerates the kinds of watch events.
type WatchEventType string

const (
	WatchEventCreate WatchEventType = "CREATE"
	WatchEventDelete WatchEventType = "DELETE"
	WatchEventTouch  WatchEventType = "TOUCH"
)

// TupleIterator iterates over tuples returned from a query.
type TupleIterator interface {
	Next() (*types.Tuple, error)
	Close() error
}

// TupleStore manages relationship tuples.
type TupleStore interface {
	WriteTuples(ctx context.Context, tuples []types.Tuple) (Revision, error)
	DeleteTuples(ctx context.Context, filter types.TupleFilter) (Revision, error)
	ReadTuples(ctx context.Context, filter types.TupleFilter, snapshot Revision) (TupleIterator, error)
	Watch(ctx context.Context, afterRevision Revision) (<-chan WatchEvent, error)
	CurrentRevision(ctx context.Context) (Revision, error)
}

// PolicyVersion represents a stored policy version.
type PolicyVersion struct {
	Policies  string
	Version   string
	CreatedAt time.Time
}

// PolicyStore stores Cedar policy sets.
type PolicyStore interface {
	WritePolicies(ctx context.Context, policies string, version string) error
	ReadPolicies(ctx context.Context) (policies string, version string, err error)
	PolicyHistory(ctx context.Context, limit int) ([]PolicyVersion, error)
}

// SanctionsEntry is a single entry from a sanctions list.
type SanctionsEntry struct {
	ListType  string
	EntityID  string
	Name      string
	Aliases   []string
	Country   string
	Reason    string
	ListedAt  time.Time
}

// AccountFreeze represents a freeze placed on an account.
type AccountFreeze struct {
	AccountID string
	Reason    string
	Authority string
	FrozenAt  time.Time
	LiftedAt  *time.Time
}

// RegulatoryOverride represents a court order or regulatory hold.
type RegulatoryOverride struct {
	ResourceID  string
	ResourceType string
	Reason      string
	Authority   string
	IssuedAt    time.Time
	ExpiresAt   *time.Time
	Active      bool
}

// ComplianceStore manages compliance data.
type ComplianceStore interface {
	WriteSanctionsList(ctx context.Context, listType string, entries []SanctionsEntry) error
	ReadSanctionsList(ctx context.Context, listType string) ([]SanctionsEntry, error)
	WriteFreeze(ctx context.Context, freeze AccountFreeze) error
	ReadFreezes(ctx context.Context, accountID string) ([]AccountFreeze, error)
	WriteRegulatoryOverride(ctx context.Context, override RegulatoryOverride) error
	ReadRegulatoryOverrides(ctx context.Context, resourceID string) ([]RegulatoryOverride, error)
}

// DecisionRecord is a single authorization decision written to the audit log.
type DecisionRecord struct {
	ID             string
	Timestamp      time.Time
	SubjectType    string
	SubjectID      string
	ResourceType   string
	ResourceID     string
	Action         string
	Allowed        bool
	Verdict        string
	DecisionToken  string
	Reasoning      string
	EvalDurationNs int64
	ClientID       string
	SourceIP       string
	UserAgent      string
}

// AuditFilter restricts audit log queries.
type AuditFilter struct {
	StartTime  *time.Time
	EndTime    *time.Time
	SubjectID  string
	ResourceID string
	Verdict    string
	ClientID   string
	Limit      int
	Cursor     string
}

// AuditStore is an append-only audit log. There are NO update/delete methods.
type AuditStore interface {
	AppendDecisions(ctx context.Context, records []DecisionRecord) error
	QueryDecisions(ctx context.Context, filter AuditFilter) ([]DecisionRecord, error)
}

// ChangeEntry represents a data change event in the changelog.
type ChangeEntry struct {
	Revision  Revision
	Type      WatchEventType
	Tuple     types.Tuple
	Timestamp time.Time
}

// ChangelogStore tracks ordered changes for the Watch API.
type ChangelogStore interface {
	AppendChange(ctx context.Context, change ChangeEntry) error
	ReadChanges(ctx context.Context, afterRevision Revision, limit int) ([]ChangeEntry, error)
}
ENDOFFILE
echo "  [OK] internal/storage/interface.go"

# ─── internal/storage/memory/memory.go ───────────────────────────────────────
cat > internal/storage/memory/memory.go << 'ENDOFFILE'
// Package memory provides an in-memory storage backend for testing.
package memory

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/pkg/types"
)

// Backend is the in-memory storage backend.
type Backend struct {
	mu sync.RWMutex

	// Tuple store
	tuples    []types.Tuple
	changelog []storage.ChangeEntry
	revision  int64

	// Policy store
	policies       string
	policyVersion  string
	policyHistory  []storage.PolicyVersion

	// Compliance store
	sanctions   map[string][]storage.SanctionsEntry
	freezes     map[string][]storage.AccountFreeze
	overrides   map[string][]storage.RegulatoryOverride

	// Audit store
	auditLog []storage.DecisionRecord

	// Watch subscribers
	watchers []chan storage.WatchEvent
}

// New creates a new in-memory backend.
func New() *Backend {
	return &Backend{
		sanctions: make(map[string][]storage.SanctionsEntry),
		freezes:   make(map[string][]storage.AccountFreeze),
		overrides: make(map[string][]storage.RegulatoryOverride),
	}
}

func (b *Backend) Close() error { return nil }

// ── TupleStore ────────────────────────────────────────────────────────────────

func (b *Backend) WriteTuples(_ context.Context, tuples []types.Tuple) (storage.Revision, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	rev := storage.Revision(atomic.AddInt64(&b.revision, 1))
	for _, t := range tuples {
		b.tuples = append(b.tuples, t)
		change := storage.ChangeEntry{
			Revision:  rev,
			Type:      storage.WatchEventCreate,
			Tuple:     t,
			Timestamp: time.Now(),
		}
		b.changelog = append(b.changelog, change)
		b.notifyWatchers(storage.WatchEvent{
			Type: storage.WatchEventCreate, Tuple: t, Revision: rev, Timestamp: change.Timestamp,
		})
	}
	return rev, nil
}

func (b *Backend) DeleteTuples(_ context.Context, filter types.TupleFilter) (storage.Revision, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	rev := storage.Revision(atomic.AddInt64(&b.revision, 1))
	remaining := b.tuples[:0]
	for _, t := range b.tuples {
		if matchesFilter(t, filter) {
			b.notifyWatchers(storage.WatchEvent{
				Type: storage.WatchEventDelete, Tuple: t, Revision: rev, Timestamp: time.Now(),
			})
		} else {
			remaining = append(remaining, t)
		}
	}
	b.tuples = remaining
	return rev, nil
}

func (b *Backend) ReadTuples(_ context.Context, filter types.TupleFilter, _ storage.Revision) (storage.TupleIterator, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var result []types.Tuple
	for _, t := range b.tuples {
		if matchesFilter(t, filter) {
			result = append(result, t)
		}
	}
	return &sliceIterator{tuples: result}, nil
}

func (b *Backend) Watch(ctx context.Context, _ storage.Revision) (<-chan storage.WatchEvent, error) {
	ch := make(chan storage.WatchEvent, 100)
	b.mu.Lock()
	b.watchers = append(b.watchers, ch)
	b.mu.Unlock()
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (b *Backend) CurrentRevision(_ context.Context) (storage.Revision, error) {
	return storage.Revision(atomic.LoadInt64(&b.revision)), nil
}

func (b *Backend) notifyWatchers(e storage.WatchEvent) {
	for _, ch := range b.watchers {
		select {
		case ch <- e:
		default:
		}
	}
}

// ── PolicyStore ───────────────────────────────────────────────────────────────

func (b *Backend) WritePolicies(_ context.Context, policies, version string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.policyHistory = append(b.policyHistory, storage.PolicyVersion{
		Policies: b.policies, Version: b.policyVersion, CreatedAt: time.Now(),
	})
	b.policies = policies
	b.policyVersion = version
	return nil
}

func (b *Backend) ReadPolicies(_ context.Context) (string, string, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.policies, b.policyVersion, nil
}

func (b *Backend) PolicyHistory(_ context.Context, limit int) ([]storage.PolicyVersion, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	if limit > len(b.policyHistory) {
		limit = len(b.policyHistory)
	}
	return b.policyHistory[:limit], nil
}

// ── ComplianceStore ───────────────────────────────────────────────────────────

func (b *Backend) WriteSanctionsList(_ context.Context, listType string, entries []storage.SanctionsEntry) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sanctions[listType] = entries
	return nil
}

func (b *Backend) ReadSanctionsList(_ context.Context, listType string) ([]storage.SanctionsEntry, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.sanctions[listType], nil
}

func (b *Backend) WriteFreeze(_ context.Context, freeze storage.AccountFreeze) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.freezes[freeze.AccountID] = append(b.freezes[freeze.AccountID], freeze)
	return nil
}

func (b *Backend) ReadFreezes(_ context.Context, accountID string) ([]storage.AccountFreeze, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.freezes[accountID], nil
}

func (b *Backend) WriteRegulatoryOverride(_ context.Context, override storage.RegulatoryOverride) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.overrides[override.ResourceID] = append(b.overrides[override.ResourceID], override)
	return nil
}

func (b *Backend) ReadRegulatoryOverrides(_ context.Context, resourceID string) ([]storage.RegulatoryOverride, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.overrides[resourceID], nil
}

// ── AuditStore ────────────────────────────────────────────────────────────────

func (b *Backend) AppendDecisions(_ context.Context, records []storage.DecisionRecord) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.auditLog = append(b.auditLog, records...)
	return nil
}

func (b *Backend) QueryDecisions(_ context.Context, filter storage.AuditFilter) ([]storage.DecisionRecord, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var result []storage.DecisionRecord
	for _, r := range b.auditLog {
		if filter.SubjectID != "" && r.SubjectID != filter.SubjectID {
			continue
		}
		if filter.ResourceID != "" && r.ResourceID != filter.ResourceID {
			continue
		}
		if filter.Verdict != "" && r.Verdict != filter.Verdict {
			continue
		}
		result = append(result, r)
	}
	if filter.Limit > 0 && len(result) > filter.Limit {
		result = result[:filter.Limit]
	}
	return result, nil
}

// ── ChangelogStore ────────────────────────────────────────────────────────────

func (b *Backend) AppendChange(_ context.Context, change storage.ChangeEntry) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.changelog = append(b.changelog, change)
	return nil
}

func (b *Backend) ReadChanges(_ context.Context, afterRevision storage.Revision, limit int) ([]storage.ChangeEntry, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var result []storage.ChangeEntry
	for _, c := range b.changelog {
		if c.Revision > afterRevision {
			result = append(result, c)
			if limit > 0 && len(result) >= limit {
				break
			}
		}
	}
	return result, nil
}

// ── helpers ───────────────────────────────────────────────────────────────────

func matchesFilter(t types.Tuple, f types.TupleFilter) bool {
	if f.ResourceType != "" && !strings.EqualFold(t.ResourceType, f.ResourceType) {
		return false
	}
	if f.ResourceID != "" && t.ResourceID != f.ResourceID {
		return false
	}
	if f.Relation != "" && t.Relation != f.Relation {
		return false
	}
	if f.SubjectType != "" && !strings.EqualFold(t.SubjectType, f.SubjectType) {
		return false
	}
	if f.SubjectID != "" && t.SubjectID != f.SubjectID {
		return false
	}
	return true
}

// sliceIterator iterates over a pre-fetched slice of tuples.
type sliceIterator struct {
	tuples []types.Tuple
	pos    int
}

func (it *sliceIterator) Next() (*types.Tuple, error) {
	if it.pos >= len(it.tuples) {
		return nil, fmt.Errorf("EOF")
	}
	t := it.tuples[it.pos]
	it.pos++
	return &t, nil
}

func (it *sliceIterator) Close() error { return nil }
ENDOFFILE
echo "  [OK] internal/storage/memory/memory.go"

cat > internal/storage/memory/memory_test.go << 'ENDOFFILE'
package memory_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

func TestWriteAndReadTuples(t *testing.T) {
	ctx := context.Background()
	b := memory.New()

	tuple := types.Tuple{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner",
		SubjectType: "user", SubjectID: "alice",
	}

	rev, err := b.WriteTuples(ctx, []types.Tuple{tuple})
	if err != nil {
		t.Fatalf("WriteTuples() error = %v", err)
	}
	if rev <= 0 {
		t.Errorf("WriteTuples() rev = %d, want > 0", rev)
	}

	iter, err := b.ReadTuples(ctx, types.TupleFilter{ResourceType: "account"}, rev)
	if err != nil {
		t.Fatalf("ReadTuples() error = %v", err)
	}
	defer iter.Close()

	got, err := iter.Next()
	if err != nil {
		t.Fatalf("Next() error = %v", err)
	}
	if got.SubjectID != "alice" {
		t.Errorf("got SubjectID = %s, want alice", got.SubjectID)
	}
}

func TestDeleteTuples(t *testing.T) {
	ctx := context.Background()
	b := memory.New()

	tuple := types.Tuple{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner",
		SubjectType: "user", SubjectID: "alice",
	}
	b.WriteTuples(ctx, []types.Tuple{tuple})

	_, err := b.DeleteTuples(ctx, types.TupleFilter{ResourceType: "account", ResourceID: "acme"})
	if err != nil {
		t.Fatalf("DeleteTuples() error = %v", err)
	}

	rev, _ := b.CurrentRevision(ctx)
	iter, _ := b.ReadTuples(ctx, types.TupleFilter{ResourceType: "account"}, rev)
	defer iter.Close()
	got, err := iter.Next()
	if err == nil && got != nil {
		t.Error("expected no tuples after delete")
	}
}

func TestAuditAppendAndQuery(t *testing.T) {
	ctx := context.Background()
	b := memory.New()

	from storage "github.com/youorg/zanzipay/internal/storage"
	records := []storage.DecisionRecord{{
		ID: "01", SubjectID: "alice", ResourceID: "acme", Verdict: "ALLOWED", Allowed: true,
	}}
	if err := b.AppendDecisions(ctx, records); err != nil {
		t.Fatalf("AppendDecisions() error = %v", err)
	}
	results, err := b.QueryDecisions(ctx, storage.AuditFilter{SubjectID: "alice"})
	if err != nil {
		t.Fatalf("QueryDecisions() error = %v", err)
	}
	if len(results) != 1 {
		t.Errorf("QueryDecisions() got %d results, want 1", len(results))
	}
}
ENDOFFILE
echo "  [OK] internal/storage/memory/memory_test.go"

echo "=== internal/storage/ done ==="
ENDOFFILE
echo "Part 4 script written"
