#!/usr/bin/env bash
# Part 2: pkg/, internal/config/, internal/storage/
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── pkg/errors/errors.go ───────────────────────────────────────────────────
cat > pkg/errors/errors.go << 'ENDOFFILE'
package errors

import (
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Error codes for ZanziPay
const (
	CodeNotFound          = "NOT_FOUND"
	CodeInvalidArgument   = "INVALID_ARGUMENT"
	CodePermissionDenied  = "PERMISSION_DENIED"
	CodeInternal          = "INTERNAL"
	CodeUnavailable       = "UNAVAILABLE"
	CodeAlreadyExists     = "ALREADY_EXISTS"
	CodeResourceExhausted = "RESOURCE_EXHAUSTED"
	CodeDeadlineExceeded  = "DEADLINE_EXCEEDED"
)

// ZanziPayError is the base error type.
type ZanziPayError struct {
	Code    string
	Message string
	Cause   error
}

func (e *ZanziPayError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("[%s] %s: %v", e.Code, e.Message, e.Cause)
	}
	return fmt.Sprintf("[%s] %s", e.Code, e.Message)
}

func (e *ZanziPayError) Unwrap() error { return e.Cause }

// New creates a new ZanziPayError.
func New(code, message string) *ZanziPayError {
	return &ZanziPayError{Code: code, Message: message}
}

// Wrap wraps an existing error.
func Wrap(code, message string, cause error) *ZanziPayError {
	return &ZanziPayError{Code: code, Message: message, Cause: cause}
}

// ToGRPCStatus converts a ZanziPayError to a gRPC status error.
func ToGRPCStatus(err error) error {
	zpe, ok := err.(*ZanziPayError)
	if !ok {
		return status.Errorf(codes.Internal, "%v", err)
	}
	var code codes.Code
	switch zpe.Code {
	case CodeNotFound:
		code = codes.NotFound
	case CodeInvalidArgument:
		code = codes.InvalidArgument
	case CodePermissionDenied:
		code = codes.PermissionDenied
	case CodeAlreadyExists:
		code = codes.AlreadyExists
	case CodeResourceExhausted:
		code = codes.ResourceExhausted
	case CodeDeadlineExceeded:
		code = codes.DeadlineExceeded
	case CodeUnavailable:
		code = codes.Unavailable
	default:
		code = codes.Internal
	}
	return status.Errorf(code, "%s", zpe.Message)
}

// Sentinel errors
var (
	ErrSchemaNotFound    = New(CodeNotFound, "schema not found")
	ErrTupleNotFound     = New(CodeNotFound, "tuple not found")
	ErrPolicyNotFound    = New(CodeNotFound, "policy not found")
	ErrInvalidSchema     = New(CodeInvalidArgument, "invalid schema")
	ErrInvalidTuple      = New(CodeInvalidArgument, "invalid tuple")
	ErrStorageUnavailable = New(CodeUnavailable, "storage unavailable")
)
ENDOFFILE
echo "  [OK] pkg/errors/errors.go"

# ─── pkg/types/ ──────────────────────────────────────────────────────────────
cat > pkg/types/tuple.go << 'ENDOFFILE'
package types

import "fmt"

// Tuple represents a relationship triple: resource#relation@subject
type Tuple struct {
	ResourceType    string            `json:"resource_type"`
	ResourceID      string            `json:"resource_id"`
	Relation        string            `json:"relation"`
	SubjectType     string            `json:"subject_type"`
	SubjectID       string            `json:"subject_id"`
	SubjectRelation string            `json:"subject_relation,omitempty"`
	CaveatName      string            `json:"caveat_name,omitempty"`
	CaveatContext   map[string]interface{} `json:"caveat_context,omitempty"`
}

// String returns the canonical string representation resource#relation@subject.
func (t *Tuple) String() string {
	subj := fmt.Sprintf("%s:%s", t.SubjectType, t.SubjectID)
	if t.SubjectRelation != "" {
		subj += "#" + t.SubjectRelation
	}
	return fmt.Sprintf("%s:%s#%s@%s", t.ResourceType, t.ResourceID, t.Relation, subj)
}

// TupleFilter is used to query tuples.
type TupleFilter struct {
	ResourceType string
	ResourceID   string
	Relation     string
	SubjectType  string
	SubjectID    string
}
ENDOFFILE
echo "  [OK] pkg/types/tuple.go"

cat > pkg/types/relation.go << 'ENDOFFILE'
package types

// RelationType enumerates the types of userset rewrite operations.
type RelationType string

const (
	RelationTypeThis           RelationType = "this"
	RelationTypeComputedUserset RelationType = "computed_userset"
	RelationTypeTupleToUserset  RelationType = "tuple_to_userset"
	RelationTypeUnion          RelationType = "union"
	RelationTypeIntersection   RelationType = "intersection"
	RelationTypeExclusion      RelationType = "exclusion"
)

// SetOperation represents a boolean combination of child usersets.
type SetOperation string

const (
	SetOperationUnion        SetOperation = "union"
	SetOperationIntersection SetOperation = "intersection"
	SetOperationExclusion    SetOperation = "exclusion"
)
ENDOFFILE
echo "  [OK] pkg/types/relation.go"

cat > pkg/types/subject.go << 'ENDOFFILE'
package types

import "fmt"

// SubjectRef is a reference to a subject (user or group).
type SubjectRef struct {
	Type     string `json:"type"`
	ID       string `json:"id"`
	Relation string `json:"relation,omitempty"`
}

// String returns subject:id or subject:id#relation
func (s SubjectRef) String() string {
	if s.Relation != "" {
		return fmt.Sprintf("%s:%s#%s", s.Type, s.ID, s.Relation)
	}
	return fmt.Sprintf("%s:%s", s.Type, s.ID)
}

// IsWildcard returns true if the subject matches all IDs of a type.
func (s SubjectRef) IsWildcard() bool {
	return s.ID == "*"
}
ENDOFFILE
echo "  [OK] pkg/types/subject.go"

cat > pkg/types/resource.go << 'ENDOFFILE'
package types

import "fmt"

// ObjectRef is a reference to a resource object.
type ObjectRef struct {
	Type string `json:"type"`
	ID   string `json:"id"`
}

// String returns type:id
func (o ObjectRef) String() string {
	return fmt.Sprintf("%s:%s", o.Type, o.ID)
}

// Revision is a logical transaction ID (used for zookie/snapshot consistency).
type Revision int64

// ConsistencyLevel determines how fresh a permission check result must be.
type ConsistencyLevel int

const (
	MinimizeLatency  ConsistencyLevel = 0
	AtLeastAsFresh   ConsistencyLevel = 1
	FullyConsistent  ConsistencyLevel = 2
)
ENDOFFILE
echo "  [OK] pkg/types/resource.go"

# ─── pkg/client/client.go ─────────────────────────────────────────────────────
cat > pkg/client/client.go << 'ENDOFFILE'
// Package client provides the Go client SDK for ZanziPay.
package client

import (
	"context"
	"time"

	"github.com/youorg/zanzipay/pkg/types"
)

// Client is the ZanziPay Go client SDK.
type Client struct {
	addr    string
	apiKey  string
	timeout time.Duration
}

// Option is a client configuration option.
type Option func(*Client)

// WithTimeout sets the request timeout.
func WithTimeout(d time.Duration) Option {
	return func(c *Client) { c.timeout = d }
}

// WithAPIKey sets the API key for authentication.
func WithAPIKey(key string) Option {
	return func(c *Client) { c.apiKey = key }
}

// New creates a new ZanziPay client.
func New(addr string, opts ...Option) *Client {
	c := &Client{
		addr:    addr,
		timeout: 5 * time.Second,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// CheckRequest holds parameters for a permission check.
type CheckRequest struct {
	ResourceType   string
	ResourceID     string
	Permission     string
	SubjectType    string
	SubjectID      string
	Consistency    types.ConsistencyLevel
	Zookie         string
	CaveatContext  map[string]string
}

// CheckResponse holds the result of a permission check.
type CheckResponse struct {
	Allowed       bool
	Verdict       string
	DecisionToken string
	Reasoning     string
	EvalDurationNs int64
}

// Check performs a permission check.
func (c *Client) Check(ctx context.Context, req CheckRequest) (*CheckResponse, error) {
	// In a real implementation this would make a gRPC call.
	// Stub implementation for compilability.
	return &CheckResponse{
		Allowed:       false,
		Verdict:       "DENIED",
		DecisionToken: "",
		Reasoning:     "stub: not connected",
	}, nil
}

// WriteTuple writes a single relationship tuple.
func (c *Client) WriteTuple(ctx context.Context, t types.Tuple) (string, error) {
	return "", nil
}

// DeleteTuple deletes relationship tuples matching a filter.
func (c *Client) DeleteTuple(ctx context.Context, filter types.TupleFilter) (string, error) {
	return "", nil
}
ENDOFFILE
echo "  [OK] pkg/client/client.go"

cat > pkg/client/client_test.go << 'ENDOFFILE'
package client_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/pkg/client"
)

func TestClientCheck(t *testing.T) {
	c := client.New("localhost:50053", client.WithAPIKey("test"))
	resp, err := c.Check(context.Background(), client.CheckRequest{
		ResourceType: "account",
		ResourceID:   "acme",
		Permission:   "view",
		SubjectType:  "user",
		SubjectID:    "alice",
	})
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if resp == nil {
		t.Fatal("Check() returned nil response")
	}
}
ENDOFFILE
echo "  [OK] pkg/client/client_test.go"

echo "=== pkg/ done ==="
ENDOFFILE
echo "Part 2 script written"
