package audit_test

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/audit"
	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/internal/storage/memory"
)

func TestAuditLogAndQuery(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()

	err := logger.Log(&audit.DecisionRecord{
		SubjectID: "alice", ResourceID: "acme",
		Allowed: true, Verdict: "ALLOWED", Timestamp: time.Now(),
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

func TestAuditExportJSON(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()
	logger.Log(&audit.DecisionRecord{Allowed: true, Verdict: "ALLOWED", Timestamp: time.Now()})
	logger.Flush()

	r, err := logger.Export(context.Background(), storage.AuditFilter{}, audit.FormatJSON)
	if err != nil {
		t.Fatalf("Export(JSON) error = %v", err)
	}
	data, _ := io.ReadAll(r)
	if len(data) == 0 {
		t.Error("expected non-empty JSON export")
	}
}

func TestAuditExportCSV(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()
	logger.Log(&audit.DecisionRecord{Allowed: false, Verdict: "DENIED", Timestamp: time.Now()})
	logger.Flush()

	r, err := logger.Export(context.Background(), storage.AuditFilter{}, audit.FormatCSV)
	if err != nil {
		t.Fatalf("Export(CSV) error = %v", err)
	}
	data, _ := io.ReadAll(r)
	if len(data) == 0 {
		t.Error("expected non-empty CSV export")
	}
}

func TestSOXReport(t *testing.T) {
	store := memory.New()
	logger := audit.NewLogger(store)
	defer logger.Close()
	now := time.Now()
	logger.Log(&audit.DecisionRecord{Allowed: true, Verdict: "ALLOWED", Timestamp: now})
	logger.Log(&audit.DecisionRecord{Allowed: false, Verdict: "DENIED", Timestamp: now})
	logger.Flush()

	tr := audit.TimeRange{Start: now.Add(-time.Hour), End: now.Add(time.Hour)}
	report, err := logger.GenerateSOXReport(context.Background(), tr)
	if err != nil {
		t.Fatalf("GenerateSOXReport() error = %v", err)
	}
	if report.TotalDecisions != 2 {
		t.Errorf("expected 2 decisions, got %d", report.TotalDecisions)
	}
	if report.DeniedDecisions != 1 {
		t.Errorf("expected 1 denied, got %d", report.DeniedDecisions)
	}
}
