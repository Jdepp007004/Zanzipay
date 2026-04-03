// Package memory provides an in-memory storage backend for ZanziPay (testing/dev).
package memory

import (
	"context"
	"fmt"
	"sync"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// Backend is the in-memory implementation of all storage interfaces.
type Backend struct {
	mu           sync.RWMutex
	tuples       []tupleRecord
	revision     storage.Revision
	watchers     []chan storage.WatchEvent
	audit        []storage.DecisionRecord
	sanctions    map[string][]storage.SanctionsEntry
	freezes      map[string][]storage.AccountFreeze
	regulatory   map[string][]storage.RegulatoryOverride
	policySource string
	policyVer    string
}

type tupleRecord struct {
	tuple      types.Tuple
	createdRev storage.Revision
	deletedRev storage.Revision // 0 = active
}

// New creates a new in-memory backend.
func New() *Backend {
	return &Backend{
		sanctions:  make(map[string][]storage.SanctionsEntry),
		freezes:    make(map[string][]storage.AccountFreeze),
		regulatory: make(map[string][]storage.RegulatoryOverride),
	}
}

// WriteTuples adds tuples to the store.
func (b *Backend) WriteTuples(_ context.Context, tuples []types.Tuple) (storage.Revision, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.revision++
	rev := b.revision
	for _, t := range tuples {
		b.tuples = append(b.tuples, tupleRecord{tuple: t, createdRev: rev})
		b.notify(storage.WatchEvent{Type: storage.WatchEventCreate, Tuple: t, Revision: rev})
	}
	return rev, nil
}

// DeleteTuples soft-deletes tuples matching the filter.
func (b *Backend) DeleteTuples(_ context.Context, filter types.TupleFilter) (storage.Revision, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.revision++
	rev := b.revision
	for i, r := range b.tuples {
		if r.deletedRev != 0 {
			continue
		}
		if matchesFilter(r.tuple, filter) {
			b.tuples[i].deletedRev = rev
			b.notify(storage.WatchEvent{Type: storage.WatchEventDelete, Tuple: r.tuple, Revision: rev})
		}
	}
	return rev, nil
}

// ReadTuples returns all active tuples matching the filter at the given snapshot.
func (b *Backend) ReadTuples(_ context.Context, filter types.TupleFilter, snapshot storage.Revision) (storage.TupleIterator, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var results []types.Tuple
	for _, r := range b.tuples {
		if r.createdRev > snapshot {
			continue
		}
		if r.deletedRev != 0 && r.deletedRev <= snapshot {
			continue
		}
		if matchesFilter(r.tuple, filter) {
			results = append(results, r.tuple)
		}
	}
	return &sliceIterator{items: results}, nil
}

// Watch returns a channel of change events after the given revision.
func (b *Backend) Watch(ctx context.Context, afterRevision storage.Revision) (<-chan storage.WatchEvent, error) {
	ch := make(chan storage.WatchEvent, 100)
	b.mu.Lock()
	b.watchers = append(b.watchers, ch)
	b.mu.Unlock()
	go func() {
		<-ctx.Done()
		b.mu.Lock()
		for i, w := range b.watchers {
			if w == ch {
				b.watchers = append(b.watchers[:i], b.watchers[i+1:]...)
				break
			}
		}
		b.mu.Unlock()
		close(ch)
	}()
	return ch, nil
}

// CurrentRevision returns the latest revision.
func (b *Backend) CurrentRevision(_ context.Context) (storage.Revision, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.revision, nil
}

// AppendDecisions stores audit log records.
func (b *Backend) AppendDecisions(_ context.Context, records []storage.DecisionRecord) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.audit = append(b.audit, records...)
	return nil
}

// QueryDecisions filters audit log records.
func (b *Backend) QueryDecisions(_ context.Context, filter storage.AuditFilter) ([]storage.DecisionRecord, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var results []storage.DecisionRecord
	for _, r := range b.audit {
		if filter.SubjectID != "" && r.SubjectID != filter.SubjectID {
			continue
		}
		if filter.ResourceID != "" && r.ResourceID != filter.ResourceID {
			continue
		}
		if filter.StartTime != nil && r.Timestamp.Before(*filter.StartTime) {
			continue
		}
		if filter.EndTime != nil && r.Timestamp.After(*filter.EndTime) {
			continue
		}
		results = append(results, r)
		if filter.Limit > 0 && len(results) >= filter.Limit {
			break
		}
	}
	return results, nil
}

// WriteSanctionsList stores a sanctions list.
func (b *Backend) WriteSanctionsList(_ context.Context, listType string, entries []storage.SanctionsEntry) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sanctions[listType] = entries
	return nil
}

// ReadSanctionsList retrieves a sanctions list.
func (b *Backend) ReadSanctionsList(_ context.Context, listType string) ([]storage.SanctionsEntry, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.sanctions[listType], nil
}

// WriteFreeze records a freeze.
func (b *Backend) WriteFreeze(_ context.Context, freeze storage.AccountFreeze) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.freezes[freeze.AccountID] = append(b.freezes[freeze.AccountID], freeze)
	return nil
}

// ReadFreezes returns all freezes for an account.
func (b *Backend) ReadFreezes(_ context.Context, accountID string) ([]storage.AccountFreeze, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.freezes[accountID], nil
}

// WriteRegulatoryOverride stores a regulatory hold.
func (b *Backend) WriteRegulatoryOverride(_ context.Context, override storage.RegulatoryOverride) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.regulatory[override.ResourceID] = append(b.regulatory[override.ResourceID], override)
	return nil
}

// ReadRegulatoryOverrides returns active overrides for a resource.
func (b *Backend) ReadRegulatoryOverrides(_ context.Context, resourceID string) ([]storage.RegulatoryOverride, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.regulatory[resourceID], nil
}

// WritePolicies stores a new policy version.
func (b *Backend) WritePolicies(_ context.Context, policies, version string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.policySource = policies
	b.policyVer = version
	return nil
}

// ReadPolicies returns the current policy set.
func (b *Backend) ReadPolicies(_ context.Context) (string, string, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.policySource, b.policyVer, nil
}

// AppendChange records a changelog entry.
func (b *Backend) AppendChange(_ context.Context, change storage.ChangeEntry) error { return nil }

// ReadChanges is not implemented for the memory backend.
func (b *Backend) ReadChanges(_ context.Context, after storage.Revision, limit int) ([]storage.ChangeEntry, error) {
	return nil, nil
}

func (b *Backend) notify(event storage.WatchEvent) {
	for _, ch := range b.watchers {
		select {
		case ch <- event:
		default:
		}
	}
}

func matchesFilter(t types.Tuple, f types.TupleFilter) bool {
	if f.ResourceType != "" && t.ResourceType != f.ResourceType {
		return false
	}
	if f.ResourceID != "" && t.ResourceID != f.ResourceID {
		return false
	}
	if f.Relation != "" && t.Relation != f.Relation {
		return false
	}
	if f.SubjectType != "" && t.SubjectType != f.SubjectType {
		return false
	}
	if f.SubjectID != "" && t.SubjectID != f.SubjectID {
		return false
	}
	return true
}

// sliceIterator iterates over a pre-loaded slice of tuples.
type sliceIterator struct {
	items []types.Tuple
	pos   int
}

func (it *sliceIterator) Next() (*types.Tuple, error) {
	if it.pos >= len(it.items) {
		return nil, fmt.Errorf("EOF")
	}
	t := it.items[it.pos]
	it.pos++
	return &t, nil
}

func (it *sliceIterator) Close() error { return nil }
