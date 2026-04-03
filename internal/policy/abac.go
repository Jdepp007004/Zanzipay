package policy

import (
	"strconv"
	"strings"
)

// EvalCondition evaluates a Cedar-like condition string against a context map.
func EvalCondition(condition string, ctx map[string]interface{}) bool {
	return evalLogical(condition, ctx)
}

func evalLogical(condition string, ctx map[string]interface{}) bool {
	condition = strings.TrimSpace(condition)

	// Handle ||
	if strings.Contains(condition, "||") {
		parts := strings.SplitN(condition, "||", 2)
		if evalLogical(parts[0], ctx) {
			return true
		}
		return evalLogical(parts[1], ctx)
	}

	// Handle &&
	if strings.Contains(condition, "&&") {
		parts := strings.SplitN(condition, "&&", 2)
		if !evalLogical(parts[0], ctx) {
			return false
		}
		return evalLogical(parts[1], ctx)
	}

	// Handle !
	if strings.HasPrefix(condition, "!") {
		return !evalLogical(condition[1:], ctx)
	}

	// List Contains: ["transfer","payout"].contains(action)
	if idx := strings.Index(condition, ".contains("); idx != -1 {
		listExpr := strings.TrimSpace(condition[:idx])
		elementStr := strings.TrimSpace(condition[idx+len(".contains("):])
		elementStr = strings.TrimSuffix(elementStr, ")")
		return evalContains(listExpr, elementStr, ctx)
	}

	// List In: context.day_of_week in ["Saturday","Sunday"]
	if idx := strings.Index(condition, " in "); idx != -1 {
		elementStr := strings.TrimSpace(condition[:idx])
		listExpr := strings.TrimSpace(condition[idx+len(" in "):])
		return evalIn(elementStr, listExpr, ctx)
	}

	// Comparisons
	operators := []string{"==", "!=", ">=", "<=", ">", "<"}
	for _, op := range operators {
		idx := strings.Index(condition, op)
		if idx != -1 {
			left := strings.TrimSpace(condition[:idx])
			right := strings.TrimSpace(condition[idx+len(op):])
			return evalCompare(left, op, right, ctx)
		}
	}

	// Single boolean evaluation (like "context.is_frozen")
	val := resolveValue(condition, ctx)
	if b, ok := val.(bool); ok {
		return b
	}

	return false
}

func evalCompare(left, op, right string, ctx map[string]interface{}) bool {
	leftVal := resolveValue(left, ctx)
	rightVal := resolveValue(right, ctx)

	// Number coercion if applicable
	if leftNum, ok := leftVal.(float64); ok {
		if rightStr, ok := rightVal.(string); ok {
			if num, err := strconv.ParseFloat(rightStr, 64); err == nil {
				rightVal = num
			}
		} else if rightInt, ok := rightVal.(int); ok {
			rightVal = float64(rightInt)
		} else if rightFloat32, ok := rightVal.(float32); ok {
			rightVal = float64(rightFloat32)
		}
		_ = leftNum // using everything for coercion
	}
	if rightNum, ok := rightVal.(float64); ok {
		if leftStr, ok := leftVal.(string); ok {
			if num, err := strconv.ParseFloat(leftStr, 64); err == nil {
				leftVal = num
			}
		} else if leftInt, ok := leftVal.(int); ok {
			leftVal = float64(leftInt)
		} else if leftFloat32, ok := leftVal.(float32); ok {
			leftVal = float64(leftFloat32)
		}
		_ = rightNum
	}
    // Handle integer matches against float logic
    if lInt, ok := leftVal.(int); ok { leftVal = float64(lInt) }
    if rInt, ok := rightVal.(int); ok { rightVal = float64(rInt) }

	switch l := leftVal.(type) {
	case float64:
		if r, ok := rightVal.(float64); ok {
			switch op {
			case "==":
				return l == r
			case "!=":
				return l != r
			case ">":
				return l > r
			case "<":
				return l < r
			case ">=":
				return l >= r
			case "<=":
				return l <= r
			}
		}
	case string:
		if r, ok := rightVal.(string); ok {
			switch op {
			case "==":
				return l == r
			case "!=":
				return l != r
			}
		}
	case bool:
		if r, ok := rightVal.(bool); ok {
			switch op {
			case "==":
				return l == r
			case "!=":
				return l != r
			}
		}
	}
	return false
}

func evalContains(listExpr, element string, ctx map[string]interface{}) bool {
	return parseAndSearchList(listExpr, element, ctx)
}

func evalIn(element, listExpr string, ctx map[string]interface{}) bool {
	return parseAndSearchList(listExpr, element, ctx)
}

func parseAndSearchList(listExpr, element string, ctx map[string]interface{}) bool {
	listExpr = strings.TrimSpace(listExpr)
	if !strings.HasPrefix(listExpr, "[") || !strings.HasSuffix(listExpr, "]") {
		return false
	}
	inner := listExpr[1 : len(listExpr)-1]
	items := strings.Split(inner, ",")

	targetVal := resolveValue(element, ctx)

	for _, item := range items {
		itemVal := resolveValue(item, ctx)
		if targetVal == itemVal {
			return true
		}
	}
	return false
}

func resolveValue(expr string, ctx map[string]interface{}) interface{} {
	expr = strings.TrimSpace(expr)

	if strings.HasPrefix(expr, "\"") && strings.HasSuffix(expr, "\"") {
		return expr[1 : len(expr)-1]
	}
	if expr == "true" {
		return true
	}
	if expr == "false" {
		return false
	}
	if num, err := strconv.ParseFloat(expr, 64); err == nil {
		return num
	}

	key := expr
	for _, prefix := range []string{"context.", "principal.", "resource."} {
		if strings.HasPrefix(key, prefix) {
			key = strings.TrimPrefix(key, prefix)
		}
	}

	if val, ok := ctx[key]; ok {
        switch v := val.(type) {
		case int:
			return float64(v)
		case int32:
			return float64(v)
		case int64:
			return float64(v)
		case float32:
			return float64(v)
		}
		return val
	}

	return nil
}
