package audit

import (
	"sort"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

type ResourceCount struct {
	ResourceType string
	ResourceID   string
	Count        int
}

type SubjectCount struct {
	SubjectType string
	SubjectID   string
	Count       int
}

type ComplianceReport struct {
	TimeRange          [2]time.Time
	TotalDecisions     int
	AllowCount         int
	DenyCount          int
	AllowRate          float64
	TopDeniedResources []ResourceCount
	TopDeniedSubjects  []SubjectCount
	ComplianceScore    float64
}

func GenerateReport(records []storage.DecisionRecord, from, to time.Time) *ComplianceReport {
	report := &ComplianceReport{
		TimeRange: [2]time.Time{from, to},
	}

	resCounts := make(map[string]map[string]int)
	subCounts := make(map[string]map[string]int)

	for _, rec := range records {
		recTime := rec.Timestamp
		if recTime.Before(from) || recTime.After(to) {
			continue
		}
		
		report.TotalDecisions++
		if rec.Allowed {
			report.AllowCount++
		} else {
			report.DenyCount++
			
			if resCounts[rec.ResourceType] == nil {
				resCounts[rec.ResourceType] = make(map[string]int)
			}
			resCounts[rec.ResourceType][rec.ResourceID]++

			if subCounts[rec.SubjectType] == nil {
				subCounts[rec.SubjectType] = make(map[string]int)
			}
			subCounts[rec.SubjectType][rec.SubjectID]++
		}
	}

	if report.TotalDecisions > 0 {
		report.AllowRate = float64(report.AllowCount) / float64(report.TotalDecisions)
	}

	// Calculate Top Denied Resources
	for rType, ids := range resCounts {
		for rID, count := range ids {
			report.TopDeniedResources = append(report.TopDeniedResources, ResourceCount{
				ResourceType: rType,
				ResourceID:   rID,
				Count:        count,
			})
		}
	}
	sort.Slice(report.TopDeniedResources, func(i, j int) bool {
		return report.TopDeniedResources[i].Count > report.TopDeniedResources[j].Count
	})

	// Calculate Top Denied Subjects
	for sType, ids := range subCounts {
		for sID, count := range ids {
			report.TopDeniedSubjects = append(report.TopDeniedSubjects, SubjectCount{
				SubjectType: sType,
				SubjectID:   sID,
				Count:       count,
			})
		}
	}
	sort.Slice(report.TopDeniedSubjects, func(i, j int) bool {
		return report.TopDeniedSubjects[i].Count > report.TopDeniedSubjects[j].Count
	})

	report.ComplianceScore = 1.0 // Default, can be adjusted
	return report
}

func GenerateSOXReport(records []storage.DecisionRecord, from, to time.Time) *ComplianceReport {
	report := GenerateReport(records, from, to)
	
	// Add SOX-specific logic like audit trail completeness check
	// For simplicity, we assume completeness if there are decisions
	if report.TotalDecisions > 0 {
		report.ComplianceScore = 100.0 // 100% complete
	} else {
		report.ComplianceScore = 0.0 // Missing data
	}

	return report
}
