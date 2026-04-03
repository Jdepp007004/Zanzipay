#!/usr/bin/env bash
# Part 11: audit, index, server, cmd, postgres migrations, bench, schemas, frontend, deploy, docs
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/audit/ ─────────────────────────────────────────────────────────
cat > internal/audit/decision.go << 'ENDOFFILE'
// Package audit provides the immutable audit stream for ZanziPay.
package audit

import (
	"time"

	"github.com/youorg/zanzipay/internal/storage"
)

// DecisionRecord is an alias for ease of import.
type DecisionRecord = storage.DecisionRecord

// TimeRange defines a time window for report generation.
type TimeRange struct {
	Start time.Time
	End   time.Time
}

// ExportFormat enumerates supported export formats.
type ExportFormat string

const (
	FormatJSON    ExportFormat = "json"
	FormatCSV     ExportFormat = "csv"
	FormatParquet ExportFormat = "parquet"
)
ENDOFFILE
echo "  [OK] internal/audit/decision.go"

cat > internal/audit/decision_test.go << 'ENDOFFILE'
package audit_test

import (
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/audit"
)

func TestTimeRange(t *testing.T) {
	tr := audit.TimeRange{
		Start: time.Now().Add(-24 * time.Hour),
		End:   time.Now(),
	}
	if tr.Start.After(tr.End) {
		t.Error("start should be before end")
	}
}
ENDOFFILE
echo "  [OK] internal/audit/decision_test.go"

cat > internal/audit/logger.go << 'ENDOFFILE'
package audit

import (
	"context"
	"time"

	"github.com/youorg/zanzipay/internal/storage"
)

// Logger is the immutable audit logger.
type Logger struct {
	store  storage.AuditStore
	buffer chan *DecisionRecord
	done   chan struct{}
}

// LoggerOption configures the Logger.
type LoggerOption func(*Logger)

// WithBufferSize sets the async write buffer size.
func WithBufferSize(size int) LoggerOption {
	return func(l *Logger) {
		l.buffer = make(chan *DecisionRecord, size)
	}
}

// NewLogger creates and starts an audit logger.
func NewLogger(store storage.AuditStore, opts ...LoggerOption) *Logger {
	l := &Logger{
		store:  store,
		buffer: make(chan *DecisionRecord, 10000),
		done:   make(chan struct{}),
	}
	for _, opt := range opts {
		opt(l)
	}
	go l.flushLoop()
	return l
}

// Log writes a decision record to the buffer (non-blocking).
func (l *Logger) Log(record *DecisionRecord) error {
	if record.ID == "" {
		record.ID = generateID()
	}
	if record.Timestamp.IsZero() {
		record.Timestamp = time.Now()
	}
	select {
	case l.buffer <- record:
	default:
		// Buffer full — drop (in production, alert on this metric)
	}
	return nil
}

// Query returns audit records matching a filter.
func (l *Logger) Query(ctx context.Context, filter storage.AuditFilter) ([]DecisionRecord, error) {
	return l.store.QueryDecisions(ctx, filter)
}

// Flush forces an immediate flush of buffered records.
func (l *Logger) Flush() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var batch []DecisionRecord
	for {
		select {
		case r := <-l.buffer:
			batch = append(batch, *r)
		default:
			if len(batch) > 0 {
				return l.store.AppendDecisions(ctx, batch)
			}
			return nil
		}
	}
}

// Close flushes remaining records and shuts down the logger.
func (l *Logger) Close() error {
	close(l.done)
	return l.Flush()
}

func (l *Logger) flushLoop() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-l.done:
			return
		case <-ticker.C:
			l.Flush()
		}
	}
}

func generateID() string {
	return time.Now().Format("20060102150405.000000000")
}
ENDOFFILE
echo "  [OK] internal/audit/logger.go"

cat > internal/audit/logger_test.go << 'ENDOFFILE'
package audit_test

import (
	"context"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/audit"
	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestAuditLogger(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()

	err := logger.Log(&audit.DecisionRecord{
		SubjectID:  "alice",
		ResourceID: "acme",
		Allowed:    true,
		Verdict:    "ALLOWED",
		Timestamp:  time.Now(),
	})
	if err != nil {
		t.Fatalf("Log() error = %v", err)
	}

	logger.Flush()
	ctx := context.Background()
	records, err := logger.Query(ctx, storage.AuditFilter{SubjectID: "alice"})
	if err != nil {
		t.Fatalf("Query() error = %v", err)
	}
	if len(records) != 1 {
		t.Errorf("expected 1 record, got %d", len(records))
	}
}
ENDOFFILE
echo "  [OK] internal/audit/logger_test.go"

cat > internal/audit/reporter.go << 'ENDOFFILE'
package audit

import (
	"context"
	"fmt"
	"time"
)

// SOXReport is a Sarbanes-Oxley compliance report.
type SOXReport struct {
	TimeRange  TimeRange
	Generated  time.Time
	TotalDecisions int
	DeniedDecisions int
	Violations []string
	Summary    string
}

// PCIReport is a PCI DSS compliance report.
type PCIReport struct {
	TimeRange  TimeRange
	Generated  time.Time
	TotalDecisions int
	AccessToCardholderData int
	FailedAttempts int
	Summary    string
}

// GenerateSOXReport generates a SOX compliance report.
func (l *Logger) GenerateSOXReport(ctx context.Context, tr TimeRange) (*SOXReport, error) {
	records, err := l.store.QueryDecisions(ctx, AuditFilter{
		StartTime: &tr.Start,
		EndTime:   &tr.End,
	})
	if err != nil {
		return nil, fmt.Errorf("querying audit records: %w", err)
	}
	report := &SOXReport{
		TimeRange:      tr,
		Generated:      time.Now(),
		TotalDecisions: len(records),
	}
	for _, r := range records {
		if !r.Allowed {
			report.DeniedDecisions++
		}
	}
	report.Summary = fmt.Sprintf("SOX Report: %d total decisions, %d denied, period %s to %s",
		report.TotalDecisions, report.DeniedDecisions,
		tr.Start.Format(time.RFC3339), tr.End.Format(time.RFC3339))
	return report, nil
}

// AuditFilter is an alias for the storage filter.
type AuditFilter = storage.AuditFilter
ENDOFFILE
echo "  [OK] internal/audit/reporter.go"

cat > internal/audit/reporter_test.go << 'ENDOFFILE'
package audit_test

import (
	"context"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/audit"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestGenerateSOXReport(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()

	logger.Log(&audit.DecisionRecord{Allowed: true, Verdict: "ALLOWED", Timestamp: time.Now()})
	logger.Log(&audit.DecisionRecord{Allowed: false, Verdict: "DENIED", Timestamp: time.Now()})
	logger.Flush()

	ctx := context.Background()
	tr := audit.TimeRange{
		Start: time.Now().Add(-1 * time.Hour),
		End:   time.Now().Add(1 * time.Hour),
	}
	report, err := logger.GenerateSOXReport(ctx, tr)
	if err != nil {
		t.Fatalf("GenerateSOXReport() error = %v", err)
	}
	if report.TotalDecisions != 2 {
		t.Errorf("expected 2 decisions, got %d", report.TotalDecisions)
	}
}
ENDOFFILE
echo "  [OK] internal/audit/reporter_test.go"

cat > internal/audit/exporter.go << 'ENDOFFILE'
package audit

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"

	"github.com/youorg/zanzipay/internal/storage"
)

// Export exports audit records in the requested format.
func (l *Logger) Export(ctx context.Context, filter storage.AuditFilter, format ExportFormat) (io.Reader, error) {
	records, err := l.store.QueryDecisions(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf("querying records: %w", err)
	}
	switch format {
	case FormatJSON:
		return exportJSON(records)
	case FormatCSV:
		return exportCSV(records)
	default:
		return nil, fmt.Errorf("unsupported format: %s", format)
	}
}

func exportJSON(records []storage.DecisionRecord) (io.Reader, error) {
	data, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return nil, err
	}
	return bytes.NewReader(data), nil
}

func exportCSV(records []storage.DecisionRecord) (io.Reader, error) {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	w.Write([]string{"id", "timestamp", "subject_id", "resource_id", "action", "allowed", "verdict", "reasoning"})
	for _, r := range records {
		allowed := "false"
		if r.Allowed {
			allowed = "true"
		}
		w.Write([]string{r.ID, r.Timestamp.String(), r.SubjectID, r.ResourceID, r.Action, allowed, r.Verdict, r.Reasoning})
	}
	w.Flush()
	return &buf, w.Error()
}
ENDOFFILE
echo "  [OK] internal/audit/exporter.go"

cat > internal/audit/exporter_test.go << 'ENDOFFILE'
package audit_test

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/audit"
	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestExportJSON(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()
	logger.Log(&audit.DecisionRecord{Allowed: true, Verdict: "ALLOWED", Timestamp: time.Now()})
	logger.Flush()

	ctx := context.Background()
	r, err := logger.Export(ctx, storage.AuditFilter{}, audit.FormatJSON)
	if err != nil {
		t.Fatalf("Export() error = %v", err)
	}
	data, _ := io.ReadAll(r)
	if len(data) == 0 {
		t.Error("expected non-empty JSON export")
	}
}
ENDOFFILE
echo "  [OK] internal/audit/exporter_test.go"

# ─── internal/index/ ──────────────────────────────────────────────────────────
cat > internal/index/bitmap.go << 'ENDOFFILE'
// Package index provides the materialized permission index using roaring bitmaps.
package index

import "sync"

// IndexKey uniquely identifies a (subject, resource_type, permission) 3-tuple.
type IndexKey struct {
	SubjectType  string
	SubjectID    string
	ResourceType string
	Permission   string
}

// BitmapStore stores resource ID sets as sorted slices (simplified; production
// would use github.com/RoaringBitmap/roaring for memory efficiency).
type BitmapStore struct {
	mu      sync.RWMutex
	indexes map[IndexKey]map[string]bool // key → set of resource IDs
}

// NewBitmapStore creates an empty bitmap store.
func NewBitmapStore() *BitmapStore {
	return &BitmapStore{indexes: make(map[IndexKey]map[string]bool)}
}

// Set adds a resource ID to the index for the given key.
func (bs *BitmapStore) Set(key IndexKey, resourceID string) {
	bs.mu.Lock()
	defer bs.mu.Unlock()
	if bs.indexes[key] == nil {
		bs.indexes[key] = make(map[string]bool)
	}
	bs.indexes[key][resourceID] = true
}

// Clear removes a resource ID from the index.
func (bs *BitmapStore) Clear(key IndexKey, resourceID string) {
	bs.mu.Lock()
	defer bs.mu.Unlock()
	if bs.indexes[key] != nil {
		delete(bs.indexes[key], resourceID)
	}
}

// Lookup returns all resource IDs indexed under the key.
func (bs *BitmapStore) Lookup(key IndexKey) []string {
	bs.mu.RLock()
	defer bs.mu.RUnlock()
	set := bs.indexes[key]
	result := make([]string, 0, len(set))
	for id := range set {
		result = append(result, id)
	}
	return result
}

// Size returns the total number of index entries.
func (bs *BitmapStore) Size() int {
	bs.mu.RLock()
	defer bs.mu.RUnlock()
	total := 0
	for _, s := range bs.indexes {
		total += len(s)
	}
	return total
}
ENDOFFILE
echo "  [OK] internal/index/bitmap.go"

cat > internal/index/bitmap_test.go << 'ENDOFFILE'
package index_test

import (
	"testing"

	"github.com/youorg/zanzipay/internal/index"
)

func TestBitmapStore(t *testing.T) {
	bs := index.NewBitmapStore()
	key := index.IndexKey{SubjectType: "user", SubjectID: "alice", ResourceType: "account", Permission: "view"}

	bs.Set(key, "acme")
	bs.Set(key, "initech")

	results := bs.Lookup(key)
	if len(results) != 2 {
		t.Errorf("expected 2 results, got %d", len(results))
	}

	bs.Clear(key, "acme")
	results2 := bs.Lookup(key)
	if len(results2) != 1 {
		t.Errorf("expected 1 result after clear, got %d", len(results2))
	}
}
ENDOFFILE
echo "  [OK] internal/index/bitmap_test.go"

cat > internal/index/watcher.go << 'ENDOFFILE'
package index

import (
	"context"

	"github.com/youorg/zanzipay/internal/storage"
)

// Watcher consumes tuple change events from the Watch API.
type Watcher struct {
	store    storage.TupleStore
	handlers []func(event storage.WatchEvent)
}

// NewWatcher creates a new change stream watcher.
func NewWatcher(store storage.TupleStore) *Watcher {
	return &Watcher{store: store}
}

// OnChange registers a handler that is called for each change event.
func (w *Watcher) OnChange(handler func(storage.WatchEvent)) {
	w.handlers = append(w.handlers, handler)
}

// Watch starts consuming change events from the given revision.
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
ENDOFFILE
echo "  [OK] internal/index/watcher.go"

cat > internal/index/watcher_test.go << 'ENDOFFILE'
package index_test

import (
	"context"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/index"
	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

func TestWatcher(t *testing.T) {
	store := memory.New()
	watcher := index.NewWatcher(store)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	received := make(chan bool, 1)
	watcher.OnChange(func(e storage.WatchEvent) {
		received <- true
	})
	watcher.Watch(ctx, 0)

	store.WriteTuples(ctx, []types.Tuple{{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner", SubjectType: "user", SubjectID: "alice",
	}})

	select {
	case <-received:
		// success
	case <-time.After(500 * time.Millisecond):
		t.Error("did not receive watch event within timeout")
	}
}
ENDOFFILE
echo "  [OK] internal/index/watcher_test.go"

cat > internal/index/lookup.go << 'ENDOFFILE'
package index

import "context"

// LookupResources returns all resource IDs of resourceType that subject can access with permission.
func (m *Materializer) LookupResources(_ context.Context, subjectType, subjectID, resourceType, permission string) ([]string, error) {
	key := IndexKey{
		SubjectType:  subjectType,
		SubjectID:    subjectID,
		ResourceType: resourceType,
		Permission:   permission,
	}
	return m.bitmaps.Lookup(key), nil
}

// LookupSubjects returns all subject IDs that have permission on the resource.
func (m *Materializer) LookupSubjects(_ context.Context, resourceType, resourceID, permission, subjectType string) ([]string, error) {
	// Inverse lookup: scan all index keys for matching resource
	m.bitmaps.mu.RLock()
	defer m.bitmaps.mu.RUnlock()
	var results []string
	seen := make(map[string]bool)
	for key, set := range m.bitmaps.indexes {
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
ENDOFFILE
echo "  [OK] internal/index/lookup.go"

cat > internal/index/lookup_test.go << 'ENDOFFILE'
package index_test

import (
	"context"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/index"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestLookupResources(t *testing.T) {
	store := memory.New()
	mat, err := index.NewMaterializer(store)
	if err != nil {
		t.Fatalf("NewMaterializer() error = %v", err)
	}

	// Manually seed the index
	mat.IndexSet(index.IndexKey{
		SubjectType: "user", SubjectID: "alice",
		ResourceType: "account", Permission: "view",
	}, "acme")

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	results, err := mat.LookupResources(ctx, "user", "alice", "account", "view")
	if err != nil {
		t.Fatalf("LookupResources() error = %v", err)
	}
	if len(results) != 1 || results[0] != "acme" {
		t.Errorf("LookupResources() = %v, want [acme]", results)
	}
}
ENDOFFILE
echo "  [OK] internal/index/lookup_test.go"

cat > internal/index/materializer.go << 'ENDOFFILE'
package index

import (
	"context"

	"github.com/youorg/zanzipay/internal/storage"
)

// Materializer builds and maintains the materialized permission index.
type Materializer struct {
	store   storage.TupleStore
	bitmaps *BitmapStore
	watcher *Watcher
}

// NewMaterializer creates a new materializer.
func NewMaterializer(store storage.TupleStore) (*Materializer, error) {
	m := &Materializer{
		store:   store,
		bitmaps: NewBitmapStore(),
		watcher: NewWatcher(store),
	}
	m.watcher.OnChange(m.processChange)
	return m, nil
}

// Start begins the materializer's Watch API consumer.
func (m *Materializer) Start(ctx context.Context) error {
	rev, err := m.store.CurrentRevision(ctx)
	if err != nil {
		return err
	}
	return m.watcher.Watch(ctx, rev)
}

// processChange handles a single tuple change event.
func (m *Materializer) processChange(event storage.WatchEvent) {
	t := event.Tuple
	// Build all potential index keys from this tuple
	// (full implementation would compute transitive permissions here)
	key := IndexKey{
		SubjectType:  t.SubjectType,
		SubjectID:    t.SubjectID,
		ResourceType: t.ResourceType,
		Permission:   t.Relation, // direct relation as permission
	}
	switch event.Type {
	case storage.WatchEventCreate, storage.WatchEventTouch:
		m.bitmaps.Set(key, t.ResourceID)
	case storage.WatchEventDelete:
		m.bitmaps.Clear(key, t.ResourceID)
	}
}

// IndexSet directly sets a bitmap entry (for testing and seeding).
func (m *Materializer) IndexSet(key IndexKey, resourceID string) {
	m.bitmaps.Set(key, resourceID)
}

// Stats returns materializer statistics.
func (m *Materializer) Stats() map[string]int {
	return map[string]int{"total_entries": m.bitmaps.Size()}
}
ENDOFFILE
echo "  [OK] internal/index/materializer.go"

cat > internal/index/materializer_test.go << 'ENDOFFILE'
package index_test

import (
	"testing"

	"github.com/youorg/zanzipay/internal/index"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestNewMaterializer(t *testing.T) {
	store := memory.New()
	mat, err := index.NewMaterializer(store)
	if err != nil {
		t.Fatalf("NewMaterializer() error = %v", err)
	}
	if mat == nil {
		t.Fatal("NewMaterializer() returned nil")
	}
	stats := mat.Stats()
	if stats["total_entries"] != 0 {
		t.Errorf("expected 0 entries, got %d", stats["total_entries"])
	}
}

// Ensure storage package is imported in test
var _ = storage.WatchEvent{}
ENDOFFILE
echo "  [OK] internal/index/materializer_test.go"

echo "=== audit + index done ==="
ENDOFFILE
echo "Part 11 script written"
