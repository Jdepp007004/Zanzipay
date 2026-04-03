// Package index provides the materialized permission index.
package index

import (
	"context"
	"sync"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

// IndexKey uniquely identifies a (subject, resource_type, permission) triple.
type IndexKey struct {
	SubjectType  string
	SubjectID    string
	ResourceType string
	Permission   string
}

// Materializer builds and maintains the materialized permission index.
type Materializer struct {
	store   storage.TupleStore
	mu      sync.RWMutex
	indexes map[IndexKey]map[string]bool
	watcher *Watcher
}

// NewMaterializer creates a new materializer.
func NewMaterializer(store storage.TupleStore) (*Materializer, error) {
	m := &Materializer{
		store:   store,
		indexes: make(map[IndexKey]map[string]bool),
		watcher: NewWatcher(store),
	}
	m.watcher.OnChange(m.processChange)
	return m, nil
}

// Start begins the change consumer.
func (m *Materializer) Start(ctx context.Context) error {
	rev, err := m.store.CurrentRevision(ctx)
	if err != nil {
		return err
	}
	return m.watcher.Watch(ctx, rev)
}

// IndexSet directly sets a bitmap entry (for testing).
func (m *Materializer) IndexSet(key IndexKey, resourceID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.indexes[key] == nil {
		m.indexes[key] = make(map[string]bool)
	}
	m.indexes[key][resourceID] = true
}

// LookupResources returns all resource IDs that subject has permission on.
func (m *Materializer) LookupResources(_ context.Context, subjectType, subjectID, resourceType, permission string) ([]string, error) {
	key := IndexKey{SubjectType: subjectType, SubjectID: subjectID, ResourceType: resourceType, Permission: permission}
	m.mu.RLock()
	defer m.mu.RUnlock()
	set := m.indexes[key]
	result := make([]string, 0, len(set))
	for id := range set {
		result = append(result, id)
	}
	return result, nil
}

// LookupSubjects returns all subjects with permission on a resource.
func (m *Materializer) LookupSubjects(_ context.Context, resourceType, resourceID, permission, subjectType string) ([]string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	seen := make(map[string]bool)
	var results []string
	for key, set := range m.indexes {
		if key.ResourceType != resourceType || key.Permission != permission {
			continue
		}
		if subjectType != "" && key.SubjectType != subjectType {
			continue
		}
		if _, ok := set[resourceID]; ok {
			if !seen[key.SubjectID] {
				results = append(results, key.SubjectID)
				seen[key.SubjectID] = true
			}
		}
	}
	return results, nil
}

// Stats returns index statistics.
func (m *Materializer) Stats() map[string]int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	total := 0
	for _, s := range m.indexes {
		total += len(s)
	}
	return map[string]int{"total_entries": total}
}

func (m *Materializer) processChange(event storage.WatchEvent) {
	t := event.Tuple
	key := IndexKey{
		SubjectType:  t.SubjectType,
		SubjectID:    t.SubjectID,
		ResourceType: t.ResourceType,
		Permission:   t.Relation,
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	switch event.Type {
	case storage.WatchEventCreate, storage.WatchEventTouch:
		if m.indexes[key] == nil {
			m.indexes[key] = make(map[string]bool)
		}
		m.indexes[key][t.ResourceID] = true
	case storage.WatchEventDelete:
		if m.indexes[key] != nil {
			delete(m.indexes[key], t.ResourceID)
		}
	}
}

// Watcher consumes tuple change events.
type Watcher struct {
	store    storage.TupleStore
	handlers []func(storage.WatchEvent)
}

// NewWatcher creates a new watcher.
func NewWatcher(store storage.TupleStore) *Watcher {
	return &Watcher{store: store}
}

// OnChange registers a handler for change events.
func (w *Watcher) OnChange(handler func(storage.WatchEvent)) {
	w.handlers = append(w.handlers, handler)
}

// Watch starts watching from the given revision.
func (w *Watcher) Watch(ctx context.Context, afterRevision storage.Revision) error {
	ch, err := w.store.Watch(ctx, afterRevision)
	if err != nil {
		return err
	}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case event, ok := <-ch:
				if !ok {
					return
				}
				for _, h := range w.handlers {
					h(event)
				}
			}
		}
	}()
	return nil
}
