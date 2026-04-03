package policy

import (
	"time"
)

// IsBusinessHours returns true if t is between 09:00 and 17:00 on a weekday in the given timezone.
func IsBusinessHours(t time.Time, timezone string) bool {
	loc, err := time.LoadLocation(timezone)
	if err != nil {
		loc = time.UTC
	}
	localTime := t.In(loc)

	if localTime.Weekday() == time.Saturday || localTime.Weekday() == time.Sunday {
		return false
	}

	hour := localTime.Hour()
	if hour >= 9 && hour < 17 {
		return true
	}
	return false
}

// IsValidDayOfWeek returns true if t's day of week is in the allowedDays list.
func IsValidDayOfWeek(t time.Time, allowedDays []string) bool {
	day := t.Weekday().String()
	for _, d := range allowedDays {
		if d == day {
			return true
		}
	}
	return false
}

// IsTokenValid returns true if time.Now() is before expiresAt.
func IsTokenValid(expiresAt time.Time) bool {
	return time.Now().Before(expiresAt)
}

// EnrichContextWithTime adds temporal properties to the context map.
func EnrichContextWithTime(ctx map[string]interface{}) map[string]interface{} {
	if ctx == nil {
		ctx = make(map[string]interface{})
	}
	now := time.Now()
	ctx["hour"] = now.Hour()
	ctx["minute"] = now.Minute()
	ctx["day_of_week"] = now.Weekday().String()
	ctx["is_business_hours"] = IsBusinessHours(now, "UTC")
	ctx["current_time"] = now.Format(time.RFC3339)
	return ctx
}
