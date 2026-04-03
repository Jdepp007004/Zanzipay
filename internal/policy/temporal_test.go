package policy

import (
	"testing"
	"time"
)

func TestTemporal(t *testing.T) {
	// 1. Business hours on Tuesday 10:00 -> true
	t1 := time.Date(2023, 10, 10, 10, 0, 0, 0, time.UTC) // Tuesday 10:00 UTC
	if !IsBusinessHours(t1, "UTC") {
		t.Errorf("expected business hours to be true for Tuesday 10:00")
	}

	// 2. Business hours on Saturday 10:00 -> false
	t2 := time.Date(2023, 10, 14, 10, 0, 0, 0, time.UTC) // Saturday 10:00 UTC
	if IsBusinessHours(t2, "UTC") {
		t.Errorf("expected business hours to be false for Saturday 10:00")
	}

	// 3. Token valid with future expiry -> true
	t3 := time.Now().Add(1 * time.Hour)
	if !IsTokenValid(t3) {
		t.Errorf("expected future token to be valid")
	}

	// 4. Token expired -> false
	t4 := time.Now().Add(-1 * time.Hour)
	if IsTokenValid(t4) {
		t.Errorf("expected past token to be invalid")
	}

	// Additional testing for EnrichContextWithTime
	ctx := make(map[string]interface{})
	ctx = EnrichContextWithTime(ctx)
	if _, ok := ctx["hour"]; !ok {
		t.Errorf("expected context to have 'hour'")
	}
	if _, ok := ctx["minute"]; !ok {
		t.Errorf("expected context to have 'minute'")
	}
}
