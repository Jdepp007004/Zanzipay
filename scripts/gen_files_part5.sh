#!/usr/bin/env bash
# Part 5: internal/rebac/ — the Zanzibar core
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/rebac/tuple.go ─────────────────────────────────────────────────
cat > internal/rebac/tuple.go << 'ENDOFFILE'
package rebac

import (
	"fmt"
	"strings"
)

// ObjectRef identifies a resource.
type ObjectRef struct {
	Type string
	ID   string
}

func (o ObjectRef) String() string { return fmt.Sprintf("%s:%s", o.Type, o.ID) }

// SubjectRef identifies a subject (user or group).
type SubjectRef struct {
	Type     string
	ID       string
	Relation string // non-empty for group references like team:eng#member
}

func (s SubjectRef) String() string {
	if s.Relation != "" {
		return fmt.Sprintf("%s:%s#%s", s.Type, s.ID, s.Relation)
	}
	return fmt.Sprintf("%s:%s", s.Type, s.ID)
}

// Tuple is a stored relationship: resource#relation@subject.
type Tuple struct {
	Resource      ObjectRef
	Relation      string
	Subject       SubjectRef
	CaveatName    string
	CaveatContext map[string]interface{}
}

func (t Tuple) String() string {
	return fmt.Sprintf("%s#%s@%s", t.Resource, t.Relation, t.Subject)
}

// ParseTupleString parses "resource_type:id#relation@subject_type:id" notation.
func ParseTupleString(s string) (Tuple, error) {
	// Split at '#'
	hashIdx := strings.Index(s, "#")
	if hashIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '#'", s)
	}
	resourceStr := s[:hashIdx]
	rest := s[hashIdx+1:]

	// Split resource_type:id
	resource, err := parseObjectRef(resourceStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid tuple resource: %w", err)
	}

	// Split relation@subject at '@'
	atIdx := strings.LastIndex(rest, "@")
	if atIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '@'", s)
	}
	relation := rest[:atIdx]
	subjectStr := rest[atIdx+1:]

	subject, err := parseSubjectRef(subjectStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid tuple subject: %w", err)
	}

	return Tuple{Resource: resource, Relation: relation, Subject: subject}, nil
}

func parseObjectRef(s string) (ObjectRef, error) {
	parts := strings.SplitN(s, ":", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return ObjectRef{}, fmt.Errorf("expected type:id, got %q", s)
	}
	return ObjectRef{Type: parts[0], ID: parts[1]}, nil
}

func parseSubjectRef(s string) (SubjectRef, error) {
	// May be type:id or type:id#relation
	hashIdx := strings.LastIndex(s, "#")
	var rel string
	objectStr := s
	if hashIdx != -1 {
		rel = s[hashIdx+1:]
		objectStr = s[:hashIdx]
	}
	obj, err := parseObjectRef(objectStr)
	if err != nil {
		return SubjectRef{}, err
	}
	return SubjectRef{Type: obj.Type, ID: obj.ID, Relation: rel}, nil
}
ENDOFFILE
echo "  [OK] internal/rebac/tuple.go"

cat > internal/rebac/tuple_test.go << 'ENDOFFILE'
package rebac

import "testing"

func TestParseTupleString(t *testing.T) {
	tests := []struct {
		input   string
		wantErr bool
	}{
		{"account:acme#owner@user:alice", false},
		{"team:eng#member@user:bob", false},
		{"account:acme#viewer@team:eng#member", false},
		{"invalid", true},
		{"account:acme#@user:alice", false}, // empty relation is allowed syntactically
	}
	for _, tt := range tests {
		_, err := ParseTupleString(tt.input)
		if (err != nil) != tt.wantErr {
			t.Errorf("ParseTupleString(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
		}
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/tuple_test.go"

# ─── internal/rebac/zookie.go ─────────────────────────────────────────────────
cat > internal/rebac/zookie.go << 'ENDOFFILE'
package rebac

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"time"

	"github.com/youorg/zanzipay/pkg/types"
)

// Zookie encodes a causal snapshot timestamp for consistency.
type Zookie struct {
	Timestamp  time.Time
	Quantized  time.Time
	Revision   types.Revision
}

// ZookieManager mints and validates zookies.
type ZookieManager struct {
	hmacKey       []byte
	quantInterval time.Duration
	defaultStale  time.Duration
}

// NewZookieManager creates a new ZookieManager.
func NewZookieManager(hmacKey []byte, quantInterval time.Duration) *ZookieManager {
	if quantInterval == 0 {
		quantInterval = 5 * time.Second
	}
	return &ZookieManager{
		hmacKey:       hmacKey,
		quantInterval: quantInterval,
		defaultStale:  10 * time.Second,
	}
}

// Mint creates a new zookie from a revision value.
func (zm *ZookieManager) Mint(revision types.Revision) string {
	now := time.Now()
	quantized := now.Truncate(zm.quantInterval)
	payload := make([]byte, 8)
	binary.BigEndian.PutUint64(payload, uint64(revision))
	sig := zm.sign(payload)
	data := append(payload, sig...)
	return base64.URLEncoding.EncodeToString(data)
}

// Decode decodes a zookie string back to a revision.
func (zm *ZookieManager) Decode(encoded string) (types.Revision, error) {
	data, err := base64.URLEncoding.DecodeString(encoded)
	if err != nil {
		return 0, fmt.Errorf("invalid zookie encoding: %w", err)
	}
	if len(data) < 8+32 {
		return 0, fmt.Errorf("zookie too short")
	}
	payload := data[:8]
	sig := data[8:]
	expected := zm.sign(payload)
	if !hmac.Equal(sig, expected) {
		return 0, fmt.Errorf("zookie signature invalid")
	}
	rev := types.Revision(binary.BigEndian.Uint64(payload))
	return rev, nil
}

// ResolveSnapshot returns the snapshot revision to use given a consistency level and optional client zookie.
func (zm *ZookieManager) ResolveSnapshot(
	ctx interface{},
	consistency types.ConsistencyLevel,
	clientZookie string,
	currentRevision types.Revision,
) (types.Revision, error) {
	switch consistency {
	case types.MinimizeLatency:
		return currentRevision, nil
	case types.AtLeastAsFresh:
		if clientZookie == "" {
			return currentRevision, nil
		}
		clientRev, err := zm.Decode(clientZookie)
		if err != nil {
			return 0, fmt.Errorf("invalid client zookie: %w", err)
		}
		if currentRevision < clientRev {
			return clientRev, nil
		}
		return currentRevision, nil
	case types.FullyConsistent:
		return currentRevision, nil
	default:
		return currentRevision, nil
	}
}

func (zm *ZookieManager) sign(payload []byte) []byte {
	mac := hmac.New(sha256.New, zm.hmacKey)
	mac.Write(payload)
	return mac.Sum(nil)
}
ENDOFFILE
echo "  [OK] internal/rebac/zookie.go"

cat > internal/rebac/zookie_test.go << 'ENDOFFILE'
package rebac

import (
	"testing"
	"time"
)

func TestZookieMintDecode(t *testing.T) {
	zm := NewZookieManager([]byte("test-hmac-key-32-bytes-long!!!!!"), 5*time.Second)
	encoded := zm.Mint(42)
	if encoded == "" {
		t.Fatal("Mint() returned empty string")
	}
	rev, err := zm.Decode(encoded)
	if err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	if rev != 42 {
		t.Errorf("Decode() rev = %d, want 42", rev)
	}
}

func TestZookieTampering(t *testing.T) {
	zm := NewZookieManager([]byte("test-hmac-key-32-bytes-long!!!!!"), 5*time.Second)
	encoded := zm.Mint(42)
	// Corrupt the encoded string
	corrupted := encoded[:len(encoded)-4] + "XXXX"
	_, err := zm.Decode(corrupted)
	if err == nil {
		t.Error("expected error on tampered zookie")
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/zookie_test.go"

# ─── internal/rebac/schema.go ─────────────────────────────────────────────────
cat > internal/rebac/schema.go << 'ENDOFFILE'
package rebac

import (
	"fmt"
	"strings"
)

// Schema holds the parsed namespace configuration.
type Schema struct {
	Definitions map[string]*TypeDefinition
	Caveats     map[string]*CaveatDefinition
	Version     string
}

// TypeDefinition defines a resource type with its relations and permissions.
type TypeDefinition struct {
	Name        string
	Relations   map[string]*RelationDef
	Permissions map[string]*PermissionDef
}

// RelationDef defines an allowable relation on a resource type.
type RelationDef struct {
	Name           string
	AllowedTypes   []TypeRef
	AllowCaveat    bool
	AllowedCaveats []string
}

// TypeRef is a reference to a type optionally with a relation (e.g., team#member).
type TypeRef struct {
	Type     string
	Relation string
}

func (tr TypeRef) String() string {
	if tr.Relation != "" {
		return tr.Type + "#" + tr.Relation
	}
	return tr.Type
}

// PermissionDef defines a permission using userset rewrites.
type PermissionDef struct {
	Name    string
	Userset *UsersetRewrite
}

// UsersetRewrite defines how a permission is computed.
type UsersetRewrite struct {
	Operation SetOperation
	Children  []*UsersetRewrite
	This      *ThisRef
	Computed  *ComputedUsersetRef
	Arrow     *ArrowRef
}

// SetOperation is a boolean combination over usersets.
type SetOperation string

const (
	OpUnion        SetOperation = "union"
	OpIntersection SetOperation = "intersection"
	OpExclusion    SetOperation = "exclusion"
	OpLeaf         SetOperation = "leaf"
)

// ThisRef means "direct tuples for this relation".
type ThisRef struct{}

// ComputedUsersetRef references another relation on the same object.
type ComputedUsersetRef struct {
	Relation string
}

// ArrowRef follows a relation to another object and checks a permission there.
type ArrowRef struct {
	Relation   string
	Permission string
}

// CaveatDefinition defines a CEL-based caveat.
type CaveatDefinition struct {
	Name       string
	Parameters map[string]string // param name → CEL type string
	Expression string
}

// ParseSchema parses a ZanziPay schema definition string.
// This is a simplified parser that handles the schema language described in the architecture.
func ParseSchema(input string) (*Schema, error) {
	s := &Schema{
		Definitions: make(map[string]*TypeDefinition),
		Caveats:     make(map[string]*CaveatDefinition),
	}
	lines := strings.Split(input, "\n")
	var i int
	for i < len(lines) {
		line := strings.TrimSpace(lines[i])
		if line == "" || strings.HasPrefix(line, "//") {
			i++
			continue
		}
		if strings.HasPrefix(line, "caveat ") {
			caveat, newI, err := parseCaveat(lines, i)
			if err != nil {
				return nil, err
			}
			s.Caveats[caveat.Name] = caveat
			i = newI
		} else if strings.HasPrefix(line, "definition ") {
			def, newI, err := parseDefinition(lines, i)
			if err != nil {
				return nil, err
			}
			s.Definitions[def.Name] = def
			i = newI
		} else {
			i++
		}
	}
	return s, nil
}

func parseCaveat(lines []string, start int) (*CaveatDefinition, int, error) {
	line := strings.TrimSpace(lines[start])
	// caveat name(params) {
	line = strings.TrimPrefix(line, "caveat ")
	parenIdx := strings.Index(line, "(")
	if parenIdx == -1 {
		return nil, start + 1, fmt.Errorf("invalid caveat line: %q", line)
	}
	name := strings.TrimSpace(line[:parenIdx])
	// Skip to closing brace
	var exprLines []string
	i := start + 1
	for i < len(lines) {
		l := strings.TrimSpace(lines[i])
		if l == "}" {
			i++
			break
		}
		exprLines = append(exprLines, l)
		i++
	}
	return &CaveatDefinition{
		Name:       name,
		Parameters: map[string]string{},
		Expression: strings.Join(exprLines, " "),
	}, i, nil
}

func parseDefinition(lines []string, start int) (*TypeDefinition, int, error) {
	line := strings.TrimSpace(lines[start])
	line = strings.TrimPrefix(line, "definition ")
	namePart := strings.Fields(line)[0]
	name := strings.TrimSuffix(namePart, "{")
	name = strings.TrimSpace(name)

	def := &TypeDefinition{
		Name:        name,
		Relations:   make(map[string]*RelationDef),
		Permissions: make(map[string]*PermissionDef),
	}

	i := start + 1
	for i < len(lines) {
		l := strings.TrimSpace(lines[i])
		if l == "}" {
			i++
			break
		}
		if strings.HasPrefix(l, "relation ") {
			rel := parseRelation(l)
			def.Relations[rel.Name] = rel
		} else if strings.HasPrefix(l, "permission ") {
			perm := parsePermission(l)
			def.Permissions[perm.Name] = perm
		}
		i++
	}
	return def, i, nil
}

func parseRelation(line string) *RelationDef {
	// relation name: type | type#rel | type with caveat
	line = strings.TrimPrefix(line, "relation ")
	colonIdx := strings.Index(line, ":")
	if colonIdx == -1 {
		return &RelationDef{Name: strings.TrimSpace(line)}
	}
	name := strings.TrimSpace(line[:colonIdx])
	typesPart := strings.TrimSpace(line[colonIdx+1:])
	rel := &RelationDef{Name: name}
	for _, part := range strings.Split(typesPart, "|") {
		part = strings.TrimSpace(part)
		if strings.Contains(part, " with ") {
			withParts := strings.SplitN(part, " with ", 2)
			rel.AllowCaveat = true
			rel.AllowedCaveats = append(rel.AllowedCaveats, strings.TrimSpace(withParts[1]))
			part = strings.TrimSpace(withParts[0])
		}
		tr := parseTypeRef(part)
		rel.AllowedTypes = append(rel.AllowedTypes, tr)
	}
	return rel
}

func parseTypeRef(s string) TypeRef {
	if idx := strings.Index(s, "#"); idx != -1 {
		return TypeRef{Type: s[:idx], Relation: s[idx+1:]}
	}
	return TypeRef{Type: s}
}

func parsePermission(line string) *PermissionDef {
	// permission name = expr
	line = strings.TrimPrefix(line, "permission ")
	eqIdx := strings.Index(line, "=")
	if eqIdx == -1 {
		return &PermissionDef{Name: strings.TrimSpace(line)}
	}
	name := strings.TrimSpace(line[:eqIdx])
	expr := strings.TrimSpace(line[eqIdx+1:])
	return &PermissionDef{
		Name:    name,
		Userset: parseUsersetExpr(expr),
	}
}

func parseUsersetExpr(expr string) *UsersetRewrite {
	// Handle union (+), intersection (&), exclusion (-)
	// Simple left-to-right parsing for + (union) at top level
	parts := splitTopLevel(expr, '+')
	if len(parts) > 1 {
		children := make([]*UsersetRewrite, 0, len(parts))
		for _, p := range parts {
			children = append(children, parseUsersetExpr(strings.TrimSpace(p)))
		}
		return &UsersetRewrite{Operation: OpUnion, Children: children}
	}

	// Arrow: relation->permission
	if arrowIdx := strings.Index(expr, "->"); arrowIdx != -1 {
		rel := strings.TrimSpace(expr[:arrowIdx])
		perm := strings.TrimSpace(expr[arrowIdx+2:])
		return &UsersetRewrite{
			Operation: OpLeaf,
			Arrow:     &ArrowRef{Relation: rel, Permission: perm},
		}
	}

	// Simple computed userset (just a relation name)
	return &UsersetRewrite{
		Operation: OpLeaf,
		Computed:  &ComputedUsersetRef{Relation: expr},
	}
}

// splitTopLevel splits s by sep only at the top level (not inside brackets).
func splitTopLevel(s string, sep rune) []string {
	var parts []string
	depth := 0
	start := 0
	for i, c := range s {
		switch c {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		case sep:
			if depth == 0 {
				parts = append(parts, s[start:i])
				start = i + 1
			}
		}
	}
	parts = append(parts, s[start:])
	return parts
}

// ValidateSchema validates a parsed schema for consistency.
func ValidateSchema(s *Schema) []string {
	var errs []string
	for typeName, def := range s.Definitions {
		for _, perm := range def.Permissions {
			if perm.Userset == nil {
				errs = append(errs, fmt.Sprintf("%s.%s: nil userset", typeName, perm.Name))
			}
		}
	}
	return errs
}

// LookupDefinition returns the type definition for a resource type name.
func (s *Schema) LookupDefinition(typeName string) (*TypeDefinition, bool) {
	def, ok := s.Definitions[typeName]
	return def, ok
}

// LookupRelation returns a relation definition.
func (s *Schema) LookupRelation(typeName, relationName string) (*RelationDef, bool) {
	def, ok := s.Definitions[typeName]
	if !ok {
		return nil, false
	}
	rel, ok := def.Relations[relationName]
	return rel, ok
}

// LookupPermission returns a permission definition.
func (s *Schema) LookupPermission(typeName, permissionName string) (*PermissionDef, bool) {
	def, ok := s.Definitions[typeName]
	if !ok {
		return nil, false
	}
	perm, ok := def.Permissions[permissionName]
	return perm, ok
}
ENDOFFILE
echo "  [OK] internal/rebac/schema.go"

cat > internal/rebac/schema_test.go << 'ENDOFFILE'
package rebac

import (
	"testing"
)

const testSchema = `
definition user {}

definition team {
    relation member: user
    relation admin: user
    permission access = admin + member
}

definition account {
    relation owner: user | team#member
    relation viewer: user
    permission view = owner + viewer
    permission manage = owner
}
`

func TestParseSchema(t *testing.T) {
	s, err := ParseSchema(testSchema)
	if err != nil {
		t.Fatalf("ParseSchema() error = %v", err)
	}
	if len(s.Definitions) != 3 {
		t.Errorf("got %d definitions, want 3", len(s.Definitions))
	}
	_, ok := s.LookupDefinition("account")
	if !ok {
		t.Error("LookupDefinition(account) not found")
	}
	rel, ok := s.LookupRelation("account", "owner")
	if !ok {
		t.Error("LookupRelation(account, owner) not found")
	}
	if len(rel.AllowedTypes) < 2 {
		t.Errorf("account.owner should have 2 allowed types, got %d", len(rel.AllowedTypes))
	}
	perm, ok := s.LookupPermission("account", "view")
	if !ok {
		t.Error("LookupPermission(account, view) not found")
	}
	if perm.Userset == nil {
		t.Error("account.view userset is nil")
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/schema_test.go"

echo "=== internal/rebac/tuple+schema+zookie done ==="
ENDOFFILE
echo "Part 5 script written"
