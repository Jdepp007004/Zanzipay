package audit

import (
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

func TestGenerateReport(t *testing.T) {
	now := time.Now()
	records := []storage.DecisionRecord{
		{Timestamp: now, Allowed: true, ResourceType: "account", ResourceID: "1", SubjectType: "user", SubjectID: "A"},
		{Timestamp: now, Allowed: false, ResourceType: "account", ResourceID: "1", SubjectType: "user", SubjectID: "B"},
		{Timestamp: now.Add(-24 * time.Hour), Allowed: false}, // Out of range if range starts later
	}

	report := GenerateReport(records, now.Add(-1*time.Hour), now.Add(1*time.Hour))
	if report.TotalDecisions != 2 {
		t.Errorf("expected 2 decisions, got %d", report.TotalDecisions)
	}
	if report.AllowCount != 1 {
		t.Errorf("expected 1 allow, got %d", report.AllowCount)
	}
	if report.DenyCount != 1 {
		t.Errorf("expected 1 deny, got %d", report.DenyCount)
	}
	if len(report.TopDeniedResources) != 1 {
		t.Errorf("expected 1 top denied resource, got %d", len(report.TopDeniedResources))
	}
}

func TestGenerateSOXReport(t *testing.T) {
	now := time.Now()
	records := []storage.DecisionRecord{
		{Timestamp: now, Allowed: true, DecisionToken: "mock-token"},
	}
	report := GenerateSOXReport(records, now.Add(-1*time.Hour), now.Add(1*time.Hour))
	if report.ComplianceScore != 100.0 {
		t.Errorf("expected compliance score 100.0, got %f", report.ComplianceScore)
	}
}
