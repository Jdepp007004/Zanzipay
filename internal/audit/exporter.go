package audit

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

func ExportJSON(w io.Writer, records []storage.DecisionRecord) error {
	enc := json.NewEncoder(w)
	for _, rec := range records {
		if err := enc.Encode(rec); err != nil {
			return err
		}
	}
	return nil
}

func ExportCSV(w io.Writer, records []storage.DecisionRecord) error {
	cw := csv.NewWriter(w)
	
	header := []string{
		"timestamp", "subject_type", "subject_id", "resource_type", 
		"resource_id", "action", "allowed", "verdict", "decision_token", "reasoning", "eval_duration_ns",
	}
	if err := cw.Write(header); err != nil {
		return err
	}

	for _, rec := range records {
		row := []string{
			rec.Timestamp.Format("2006-01-02T15:04:05Z07:00"),
			rec.SubjectType,
			rec.SubjectID,
			rec.ResourceType,
			rec.ResourceID,
			rec.Action,
			fmt.Sprintf("%t", rec.Allowed),
			rec.Verdict,
			rec.DecisionToken,
			rec.Reasoning,
			fmt.Sprintf("%d", rec.EvalDurationNs),
		}
		if err := cw.Write(row); err != nil {
			return err
		}
	}
	
	cw.Flush()
	return cw.Error()
}
