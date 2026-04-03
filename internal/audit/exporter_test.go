package audit

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

func TestExportJSON(t *testing.T) {
	records := []storage.DecisionRecord{
		{SubjectType: "user", SubjectID: "abc", Allowed: true},
	}
	var buf bytes.Buffer
	err := ExportJSON(&buf, records)
	if err != nil {
		t.Fatalf("export failed: %v", err)
	}
	if !strings.Contains(buf.String(), "abc") {
		t.Errorf("output missing subject ID: %s", buf.String())
	}
}

func TestExportCSV(t *testing.T) {
	records := []storage.DecisionRecord{
		{Timestamp: time.Now(), SubjectType: "user", SubjectID: "abc", Allowed: true},
	}
	var buf bytes.Buffer
	err := ExportCSV(&buf, records)
	if err != nil {
		t.Fatalf("export failed: %v", err)
	}
	if !strings.Contains(buf.String(), "abc") {
		t.Errorf("output missing subject ID: %s", buf.String())
	}
}
