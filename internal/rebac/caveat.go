package rebac

import (
	"fmt"
	"strconv"
	"strings"
)

type CaveatParamType int

const (
	TypeInt CaveatParamType = iota
	TypeString
	TypeBool
	TypeDouble
)

type CaveatResult int

const (
	CaveatSatisfied CaveatResult = iota
	CaveatNotSatisfied
	CaveatMissingContext
)

type CaveatDefinition struct {
	Name       string
	Parameters map[string]CaveatParamType
	Expression string
}

type CaveatEvaluator struct {
	definitions map[string]*CaveatDefinition
}

func NewCaveatEvaluator() *CaveatEvaluator {
	return &CaveatEvaluator{
		definitions: make(map[string]*CaveatDefinition),
	}
}

func (ce *CaveatEvaluator) Register(def CaveatDefinition) error {
	ce.definitions[def.Name] = &def
	return nil
}

func (ce *CaveatEvaluator) Evaluate(caveatName string, tupleContext map[string]interface{}, requestContext map[string]interface{}) (CaveatResult, error) {
	def, ok := ce.definitions[caveatName]
	if !ok {
		return CaveatMissingContext, fmt.Errorf("caveat definition not found: %s", caveatName)
	}

	mergedContext := make(map[string]interface{})
	if requestContext != nil {
		for k, v := range requestContext {
			mergedContext[k] = v
		}
	}
	if tupleContext != nil {
		for k, v := range tupleContext {
			mergedContext[k] = v
		}
	}

	for param := range def.Parameters {
		if _, exists := mergedContext[param]; !exists {
			return CaveatMissingContext, nil
		}
	}

	result, err := evaluateExpression(def.Expression, mergedContext)
	if err != nil {
		return CaveatMissingContext, err
	}
	if result {
		return CaveatSatisfied, nil
	}
	return CaveatNotSatisfied, nil
}

func (ce *CaveatEvaluator) MissingFields(caveatName string, ctx map[string]interface{}) []string {
	def, ok := ce.definitions[caveatName]
	if !ok {
		return nil
	}
	var missing []string
	for param := range def.Parameters {
		if _, exists := ctx[param]; !exists {
			missing = append(missing, param)
		}
	}
	return missing
}

func evaluateExpression(expr string, ctx map[string]interface{}) (bool, error) {
	expr = strings.TrimSpace(expr)

	if strings.Contains(expr, "||") {
		parts := strings.SplitN(expr, "||", 2)
		leftResult, err := evaluateExpression(parts[0], ctx)
		if err != nil {
			return false, err
		}
		if leftResult {
			return true, nil
		}
		rightResult, err := evaluateExpression(parts[1], ctx)
		if err != nil {
			return false, err
		}
		return rightResult, nil
	}
	if strings.Contains(expr, "&&") {
		parts := strings.SplitN(expr, "&&", 2)
		leftResult, err := evaluateExpression(parts[0], ctx)
		if err != nil {
			return false, err
		}
		if !leftResult {
			return false, nil
		}
		rightResult, err := evaluateExpression(parts[1], ctx)
		if err != nil {
			return false, err
		}
		return rightResult, nil
	}

	operators := []string{"==", "!=", ">=", "<=", ">", "<"}
	for _, op := range operators {
		idx := strings.Index(expr, op)
		if idx != -1 {
			leftStr := strings.TrimSpace(expr[:idx])
			rightStr := strings.TrimSpace(expr[idx+len(op):])

			leftVal, err := resolveValue(leftStr, ctx)
			if err != nil {
				return false, err
			}
			rightVal, err := resolveValue(rightStr, ctx)
			if err != nil {
				return false, err
			}

			return compareValues(leftVal, rightVal, op)
		}
	}

	val, err := resolveValue(expr, ctx)
	if err == nil {
		if b, ok := val.(bool); ok {
			return b, nil
		}
	}
	return false, fmt.Errorf("invalid expression or unsupported operation: %s", expr)
}

func resolveValue(str string, ctx map[string]interface{}) (interface{}, error) {
	str = strings.TrimSpace(str)
	if strings.HasPrefix(str, "\"") && strings.HasSuffix(str, "\"") {
		return strings.Trim(str, "\""), nil
	}
	if str == "true" {
		return true, nil
	}
	if str == "false" {
		return false, nil
	}
	if num, err := strconv.ParseFloat(str, 64); err == nil {
		return num, nil
	}

	if val, ok := ctx[str]; ok {
		switch v := val.(type) {
		case int:
			return float64(v), nil
		case int32:
			return float64(v), nil
		case int64:
			return float64(v), nil
		case float32:
			return float64(v), nil
		case float64:
			return v, nil
		case string:
			return v, nil
		case bool:
			return v, nil
		}
		return val, nil
	}
	return nil, fmt.Errorf("variable not found in context: %s", str)
}

func compareValues(left, right interface{}, op string) (bool, error) {
	if _, isFloatL := left.(float64); isFloatL {
		if rightStr, isStrR := right.(string); isStrR {
			if num, err := strconv.ParseFloat(rightStr, 64); err == nil {
				right = num
			}
		}
	}
	if _, isFloatR := right.(float64); isFloatR {
		if leftStr, isStrL := left.(string); isStrL {
			if num, err := strconv.ParseFloat(leftStr, 64); err == nil {
				left = num
			}
		}
	}
	if leftStr, isStr := left.(string); isStr && (op == "==" || op == "!=") {
		if rightStr, isStr2 := right.(string); isStr2 {
			if op == "==" {
				return leftStr == rightStr, nil
			}
			return leftStr != rightStr, nil
		}
	}

	switch leftVal := left.(type) {
	case float64:
		rightVal, ok := right.(float64)
		if !ok {
			return false, fmt.Errorf("type mismatch: expected float64, got %T", right)
		}
		switch op {
		case "==":
			return leftVal == rightVal, nil
		case "!=":
			return leftVal != rightVal, nil
		case "<":
			return leftVal < rightVal, nil
		case "<=":
			return leftVal <= rightVal, nil
		case ">":
			return leftVal > rightVal, nil
		case ">=":
			return leftVal >= rightVal, nil
		}
	case string:
		rightVal, ok := right.(string)
		if !ok {
			return false, fmt.Errorf("type mismatch: expected string, got %T", right)
		}
		switch op {
		case "==":
			return leftVal == rightVal, nil
		case "!=":
			return leftVal != rightVal, nil
		}
	case bool:
		rightVal, ok := right.(bool)
		if !ok {
			return false, fmt.Errorf("type mismatch: expected bool, got %T", right)
		}
		switch op {
		case "==":
			return leftVal == rightVal, nil
		case "!=":
			return leftVal != rightVal, nil
		}
	}
	return false, fmt.Errorf("unsupported comparison between %T and %T", left, right)
}
