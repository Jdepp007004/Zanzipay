// Package audit provides the immutable audit stream for ZanziPay.
package audit

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

// DecisionRecord alias for convenience.
type DecisionRecord = storage.DecisionRecord

// TimeRange defines a time window.
type TimeRange struct {
	Start time.Time
	End   time.Time
}

// ExportFormat enumerates supported export formats.
type ExportFormat string

const (
	FormatJSON ExportFormat = "json"
	FormatCSV  ExportFormat = "csv"
)

// AuditFilter alias.
type AuditFilter = storage.AuditFilter

// Logger is the immutable audit logger.
type Logger struct {
	store  storage.AuditStore
	buffer chan *DecisionRecord
	done   chan struct{}
}

// NewLogger creates and starts an audit logger.
func NewLogger(store storage.AuditStore) *Logger {
	l := &Logger{
		store:  store,
		buffer: make(chan *DecisionRecord, 10000),
		done:   make(chan struct{}),
	}
	go l.flushLoop()
	return l
}

// Log writes a decision record to the buffer (non-blocking).
func (l *Logger) Log(record *DecisionRecord) error {
	if record.ID == "" {
		record.ID = fmt.Sprintf("%d", time.Now().UnixNano())
	}
	if record.Timestamp.IsZero() {
		record.Timestamp = time.Now()
	}
	select {
	case l.buffer <- record:
	default:
	}
	return nil
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

// Close flushes and shuts down.
func (l *Logger) Close() error {
	close(l.done)
	return l.Flush()
}

// Query returns audit records matching a filter.
func (l *Logger) Query(ctx context.Context, filter storage.AuditFilter) ([]DecisionRecord, error) {
	return l.store.QueryDecisions(ctx, filter)
}

// Export exports audit records in the requested format.
func (l *Logger) Export(ctx context.Context, filter storage.AuditFilter, format ExportFormat) (io.Reader, error) {
	records, err := l.store.QueryDecisions(ctx, filter)
	if err != nil {
		return nil, err
	}
	switch format {
	case FormatJSON:
		data, err := json.MarshalIndent(records, "", "  ")
		if err != nil {
			return nil, err
		}
		return strings.NewReader(string(data)), nil
	case FormatCSV:
		var sb strings.Builder
		w := csv.NewWriter(&sb)
		w.Write([]string{"id", "timestamp", "subject_id", "resource_id", "action", "allowed", "verdict"})
		for _, r := range records {
			allowed := "false"
			if r.Allowed {
				allowed = "true"
			}
			w.Write([]string{r.ID, r.Timestamp.String(), r.SubjectID, r.ResourceID, r.Action, allowed, r.Verdict})
		}
		w.Flush()
		return strings.NewReader(sb.String()), w.Error()
	}
	return nil, fmt.Errorf("unsupported format: %s", format)
}

// SOXReport is a Sarbanes-Oxley compliance report.
type SOXReport struct {
	TimeRange       TimeRange
	Generated       time.Time
	TotalDecisions  int
	DeniedDecisions int
	Summary         string
}

// GenerateSOXReport generates a SOX compliance report.
func (l *Logger) GenerateSOXReport(ctx context.Context, tr TimeRange) (*SOXReport, error) {
	records, err := l.store.QueryDecisions(ctx, AuditFilter{StartTime: &tr.Start, EndTime: &tr.End})
	if err != nil {
		return nil, err
	}
	report := &SOXReport{TimeRange: tr, Generated: time.Now(), TotalDecisions: len(records)}
	for _, r := range records {
		if !r.Allowed {
			report.DeniedDecisions++
		}
	}
	report.Summary = fmt.Sprintf("SOX: %d total, %d denied, %s to %s",
		report.TotalDecisions, report.DeniedDecisions,
		tr.Start.Format(time.RFC3339), tr.End.Format(time.RFC3339))
	return report, nil
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
