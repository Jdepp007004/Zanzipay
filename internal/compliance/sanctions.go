package compliance

import (
	"context"
	"strings"

	"github.com/Jdepp007004/Zanzipay/internal/compliance/lists"
)

// screenSanctions checks the given names against sanctions lists.
func (e *Engine) screenSanctions(ctx context.Context, names []string) (*SanctionsResult, error) {
	result := &SanctionsResult{}
	for _, listType := range []string{"OFAC", "EU", "UN"} {
		entries, err := e.store.ReadSanctionsList(ctx, listType)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			for _, name := range names {
				score := lists.JaroWinkler(strings.ToLower(name), strings.ToLower(entry.Name))
				if score >= 0.85 {
					result.Matches = append(result.Matches, SanctionsMatch{
						ListType: listType, MatchedName: entry.Name, QueryName: name, Score: score,
					})
					result.Matched = true
					if score > result.RiskScore {
						result.RiskScore = score
					}
				}
			}
		}
	}
	return result, nil
}
