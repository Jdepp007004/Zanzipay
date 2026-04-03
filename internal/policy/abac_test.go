package policy

import (
	"testing"
)

func TestEvalCondition(t *testing.T) {
	tests := []struct {
		name      string
		condition string
		ctx       map[string]interface{}
		expected  bool
	}{
		{
			name:      "Numeric > true",
			condition: "context.amount > 5000",
			ctx:       map[string]interface{}{"amount": 8000},
			expected:  true,
		},
		{
			name:      "Numeric > false",
			condition: "context.amount > 5000",
			ctx:       map[string]interface{}{"amount": 3000},
			expected:  false,
		},
		{
			name:      "Numeric <=",
			condition: "context.amount <= 10000",
			ctx:       map[string]interface{}{"amount": 10000},
			expected:  true,
		},
		{
			name:      "String ==",
			condition: "context.kyc_status == \"verified\"",
			ctx:       map[string]interface{}{"kyc_status": "verified"},
			expected:  true,
		},
		{
			name:      "String !=",
			condition: "context.kyc_status != \"verified\"",
			ctx:       map[string]interface{}{"kyc_status": "pending"},
			expected:  true,
		},
		{
			name:      "Bool",
			condition: "context.is_frozen == true",
			ctx:       map[string]interface{}{"is_frozen": true},
			expected:  true,
		},
		{
			name:      "Compound &&",
			condition: "context.amount > 1000 && context.kyc_status == \"verified\"",
			ctx:       map[string]interface{}{"amount": 1500, "kyc_status": "verified"},
			expected:  true,
		},
		{
			name:      "Compound ||",
			condition: "context.is_admin == true || context.role == \"manager\"",
			ctx:       map[string]interface{}{"is_admin": false, "role": "manager"},
			expected:  true,
		},
		{
			name:      "List contains",
			condition: "[\"transfer\",\"payout\"].contains(context.action)",
			ctx:       map[string]interface{}{"action": "transfer"},
			expected:  true,
		},
		{
			name:      "List in",
			condition: "context.day in [\"Monday\",\"Tuesday\"]",
			ctx:       map[string]interface{}{"day": "Monday"},
			expected:  true,
		},
		{
			name:      "Negation",
			condition: "!context.is_frozen",
			ctx:       map[string]interface{}{"is_frozen": false},
			expected:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := EvalCondition(tt.condition, tt.ctx)
			if result != tt.expected {
				t.Errorf("expected %v, got %v for condition %q", tt.expected, result, tt.condition)
			}
		})
	}
}
