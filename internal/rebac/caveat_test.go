package rebac

import (
	"testing"
)

func TestCaveatEvaluator(t *testing.T) {
	evaluator := NewCaveatEvaluator()

	// 1 & 2 & 4. Simple numeric and Missing Context
	err := evaluator.Register(CaveatDefinition{
		Name: "amount_limit",
		Parameters: map[string]CaveatParamType{
			"amount":     TypeInt,
			"max_amount": TypeInt,
		},
		Expression: "amount <= max_amount",
	})
	if err != nil {
		t.Fatalf("failed to register caveat: %v", err)
	}

	// 3. String equality
	err = evaluator.Register(CaveatDefinition{
		Name: "currency_check",
		Parameters: map[string]CaveatParamType{
			"currency":          TypeString,
			"expected_currency": TypeString,
		},
		Expression: "currency == expected_currency",
	})
	if err != nil {
		t.Fatalf("failed to register caveat: %v", err)
	}

	// 5. Compound
	err = evaluator.Register(CaveatDefinition{
		Name: "compound_check",
		Parameters: map[string]CaveatParamType{
			"amount":   TypeInt,
			"max":      TypeInt,
			"currency": TypeString,
		},
		Expression: "amount <= max && currency == \"USD\"",
	})
	if err != nil {
		t.Fatalf("failed to register caveat: %v", err)
	}

	// 6. Bool
	err = evaluator.Register(CaveatDefinition{
		Name: "verification_check",
		Parameters: map[string]CaveatParamType{
			"is_verified": TypeBool,
		},
		Expression: "is_verified == true",
	})
	if err != nil {
		t.Fatalf("failed to register caveat: %v", err)
	}

	tests := []struct {
		name           string
		caveatName     string
		tupleContext   map[string]interface{}
		requestContext map[string]interface{}
		expected       CaveatResult
	}{
		{
			name:       "Simple numeric - Satisfied",
			caveatName: "amount_limit",
			tupleContext: map[string]interface{}{
				"max_amount": 10000,
			},
			requestContext: map[string]interface{}{
				"amount": 5000,
			},
			expected: CaveatSatisfied,
		},
		{
			name:       "Simple numeric fail - NotSatisfied",
			caveatName: "amount_limit",
			tupleContext: map[string]interface{}{
				"max_amount": 10000,
			},
			requestContext: map[string]interface{}{
				"amount": 15000,
			},
			expected: CaveatNotSatisfied,
		},
		{
			name:       "String equality - Satisfied",
			caveatName: "currency_check",
			tupleContext: map[string]interface{}{
				"expected_currency": "USD",
			},
			requestContext: map[string]interface{}{
				"currency": "USD",
			},
			expected: CaveatSatisfied,
		},
		{
			name:       "Missing context - MissingContext",
			caveatName: "amount_limit",
			tupleContext: map[string]interface{}{
				"max_amount": 10000,
			},
			requestContext: map[string]interface{}{},
			expected: CaveatMissingContext,
		},
		{
			name:       "Compound - Satisfied",
			caveatName: "compound_check",
			tupleContext: map[string]interface{}{
				"max": 1000,
			},
			requestContext: map[string]interface{}{
				"amount":   500,
				"currency": "USD",
			},
			expected: CaveatSatisfied,
		},
		{
			name:       "Bool - Satisfied",
			caveatName: "verification_check",
			tupleContext: map[string]interface{}{},
			requestContext: map[string]interface{}{
				"is_verified": true,
			},
			expected: CaveatSatisfied,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := evaluator.Evaluate(tt.caveatName, tt.tupleContext, tt.requestContext)
			if tt.expected == CaveatMissingContext {
				if result != CaveatMissingContext {
					t.Errorf("expected missing context, got %v with error %v", result, err)
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
				if result != tt.expected {
					t.Errorf("expected %v, got %v", tt.expected, result)
				}
			}
		})
	}
}
