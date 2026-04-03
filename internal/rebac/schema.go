package rebac

import (
	"fmt"
	"strings"
)

// SchemaDefinition is a parsed resource type definition.
type SchemaDefinition struct {
	Name      string
	Relations map[string]*RelationDef
}

// RelationDef is a named relation with its allowed subject types.
type RelationDef struct {
	Name         string
	AllowedTypes []AllowedType
	IsPermission bool
	Expression   *SetExpression
}

// AllowedType is a subject type allowed for a relation (type:id or type#relation).
type AllowedType struct {
	ObjectType       string
	ObjectRelation   string // for userset subjects (e.g. team#member)
}

// SetExpression is a union/intersection/exclusion/arrow/leaf expression node.
type SetExpression struct {
	Op       string         // "union" | "intersection" | "exclusion" | "computed" | "arrow"
	Children []*SetExpression
	Ref      string         // for "computed" (direct relation ref)
	Arrow    *ArrowExpr     // for "arrow" (follow relation then check)
}

// ArrowExpr is an arrow expression: relation->permission
type ArrowExpr struct {
	TuplesetRelation    string
	ComputedPermission  string
}

// Schema holds all type definitions.
type Schema struct {
	Version     string
	Definitions map[string]*SchemaDefinition
	Caveats     map[string]*CaveatDefinition
}

// ParseSchema parses a ZanziPay schema source string.
func ParseSchema(src string) (*Schema, error) {
	s := &Schema{
		Definitions: make(map[string]*SchemaDefinition),
		Caveats:     make(map[string]*CaveatDefinition),
		Version:     "1",
	}
	lines := strings.Split(src, "\n")
	var current *SchemaDefinition
	var inCaveat bool
	var currentCaveat *CaveatDefinition
	var caveatExprBuilder strings.Builder

	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "//") {
			continue
		}

		if inCaveat {
			if line == "}" {
				currentCaveat.Expression = strings.TrimSpace(caveatExprBuilder.String())
				s.Caveats[currentCaveat.Name] = currentCaveat
				inCaveat = false
				currentCaveat = nil
				caveatExprBuilder.Reset()
				continue
			}
			if caveatExprBuilder.Len() > 0 {
				caveatExprBuilder.WriteString(" ")
			}
			caveatExprBuilder.WriteString(line)
			continue
		}

		if strings.HasPrefix(line, "caveat ") {
			line = strings.TrimSuffix(line, "{")
			line = strings.TrimSpace(line)
			parts := strings.SplitN(strings.TrimPrefix(line, "caveat "), "(", 2)
			name := strings.TrimSpace(parts[0])
			paramsStr := strings.TrimSuffix(parts[1], ")")

			params := make(map[string]CaveatParamType)
			if strings.TrimSpace(paramsStr) != "" {
				for _, p := range strings.Split(paramsStr, ",") {
					p = strings.TrimSpace(p)
					pp := strings.Split(p, " ")
					if len(pp) >= 2 {
						pname := strings.TrimSpace(pp[0])
						ptypeStr := strings.TrimSpace(pp[1])
						var ptype CaveatParamType
						switch ptypeStr {
						case "int":
							ptype = TypeInt
						case "string":
							ptype = TypeString
						case "bool":
							ptype = TypeBool
						case "double":
							ptype = TypeDouble
						}
						params[pname] = ptype
					}
				}
			}
			currentCaveat = &CaveatDefinition{
				Name:       name,
				Parameters: params,
			}
			inCaveat = true
			continue
		}

		if strings.HasPrefix(line, "definition ") {
			name := strings.TrimSuffix(strings.TrimPrefix(line, "definition "), " {")
			name = strings.TrimSpace(name)
			current = &SchemaDefinition{Name: name, Relations: make(map[string]*RelationDef)}
			s.Definitions[name] = current
			continue
		}
		if line == "}" {
			current = nil
			continue
		}
		if current == nil {
			continue
		}
		if strings.HasPrefix(line, "relation ") {
			rel := parseRelationLine(line)
			if rel != nil {
				current.Relations[rel.Name] = rel
			}
		} else if strings.HasPrefix(line, "permission ") {
			perm := parsePermissionLine(line)
			if perm != nil {
				current.Relations[perm.Name] = perm
			}
		}
	}
	return s, nil
}

func parseRelationLine(line string) *RelationDef {
	// relation member: user | team#member
	parts := strings.SplitN(line, ":", 2)
	if len(parts) != 2 {
		return nil
	}
	name := strings.TrimSpace(strings.TrimPrefix(parts[0], "relation"))
	allowedStr := strings.TrimSpace(parts[1])
	var allowed []AllowedType
	for _, at := range strings.Split(allowedStr, "|") {
		at = strings.TrimSpace(at)
		if strings.Contains(at, "#") {
			sub := strings.SplitN(at, "#", 2)
			allowed = append(allowed, AllowedType{ObjectType: strings.TrimSpace(sub[0]), ObjectRelation: strings.TrimSpace(sub[1])})
		} else {
			allowed = append(allowed, AllowedType{ObjectType: at})
		}
	}
	return &RelationDef{Name: name, AllowedTypes: allowed}
}

func parsePermissionLine(line string) *RelationDef {
	// permission view = owner + viewer + org->admin
	parts := strings.SplitN(line, "=", 2)
	if len(parts) != 2 {
		return nil
	}
	name := strings.TrimSpace(strings.TrimPrefix(parts[0], "permission"))
	expr := buildExpression(strings.TrimSpace(parts[1]))
	return &RelationDef{Name: name, IsPermission: true, Expression: expr}
}

func buildExpression(s string) *SetExpression {
	s = strings.TrimSpace(s)
	// Strip caveat modifiers: "owner with kyc_verified" -> "owner"
	if idx := strings.Index(s, " with "); idx != -1 {
		s = s[:idx]
	}
	// Union (+ has lowest precedence)
	if strings.Contains(s, " + ") {
		children := []*SetExpression{}
		for _, p := range strings.Split(s, " + ") {
			children = append(children, buildExpression(strings.TrimSpace(p)))
		}
		return &SetExpression{Op: "union", Children: children}
	}
	// Intersection
	if strings.Contains(s, " & ") {
		children := []*SetExpression{}
		for _, p := range strings.Split(s, " & ") {
			children = append(children, buildExpression(strings.TrimSpace(p)))
		}
		return &SetExpression{Op: "intersection", Children: children}
	}
	// Exclusion
	if strings.Contains(s, " - ") {
		children := []*SetExpression{}
		for _, p := range strings.Split(s, " - ") {
			children = append(children, buildExpression(strings.TrimSpace(p)))
		}
		return &SetExpression{Op: "exclusion", Children: children}
	}
	// Arrow
	if strings.Contains(s, "->") {
		parts := strings.SplitN(s, "->", 2)
		return &SetExpression{Op: "arrow", Arrow: &ArrowExpr{
			TuplesetRelation:   strings.TrimSpace(parts[0]),
			ComputedPermission: strings.TrimSpace(parts[1]),
		}}
	}
	return &SetExpression{Op: "computed", Ref: s}
}

// ValidateSchema checks for common schema errors.
func ValidateSchema(s *Schema) []error {
	var errs []error
	for typeName, def := range s.Definitions {
		for relName, rel := range def.Relations {
			if rel.IsPermission && rel.Expression == nil {
				errs = append(errs, fmt.Errorf("%s#%s: permission has no expression", typeName, relName))
			}
		}
	}
	return errs
}
