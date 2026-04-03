#!/usr/bin/env bash
# Part 7: internal/rebac/engine.go and storage adapter types
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

cat > internal/rebac/engine.go << 'ENDOFFILE'
// Package rebac implements the Zanzibar-style ReBAC engine for ZanziPay.
package rebac

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/pkg/types"
)

// Revision is a snapshot revision alias.
type Revision = storage.Revision

// storageTupleFilter is an alias to avoid import cycles in check.go
type storageTupleFilter = types.TupleFilter

// storageBackend abstracts the storage layer used by the engine.
type storageBackend interface {
	storage.TupleStore
}

// EngineOptions holds optional engine configuration.
type EngineOptions struct {
	CacheSize     int
	CaveatTimeout time.Duration
	HMACKey       []byte
}

// Engine is the core ReBAC engine.
type Engine struct {
	storage    storageBackend
	schema     *Schema
	schemaMu   sync.RWMutex
	caveats    *CaveatEvaluator
	zookieMgr  *ZookieManager
	opts       EngineOptions
}

// NewEngine creates a new ReBAC engine backed by the given storage.
func NewEngine(store storageBackend, opts ...func(*EngineOptions)) (*Engine, error) {
	options := EngineOptions{
		CacheSize:     10000,
		CaveatTimeout: 10 * time.Millisecond,
		HMACKey:       []byte("default-hmac-key-change-in-prod!"),
	}
	for _, opt := range opts {
		opt(&options)
	}
	ce, err := NewCaveatEvaluator(nil)
	if err != nil {
		return nil, fmt.Errorf("creating caveat evaluator: %w", err)
	}
	return &Engine{
		storage:   store,
		caveats:   ce,
		zookieMgr: NewZookieManager(options.HMACKey, 5*time.Second),
		opts:      options,
	}, nil
}

// WriteSchema parses and installs a new schema definition.
func (e *Engine) WriteSchema(_ context.Context, schemaStr string) error {
	s, err := ParseSchema(schemaStr)
	if err != nil {
		return fmt.Errorf("parsing schema: %w", err)
	}
	errs := ValidateSchema(s)
	if len(errs) > 0 {
		return fmt.Errorf("schema validation failed: %v", errs)
	}
	e.schemaMu.Lock()
	e.schema = s
	e.schemaMu.Unlock()
	return nil
}

// ReadSchema returns the current schema as a string (placeholder).
func (e *Engine) ReadSchema(_ context.Context) (string, error) {
	e.schemaMu.RLock()
	defer e.schemaMu.RUnlock()
	if e.schema == nil {
		return "", nil
	}
	return fmt.Sprintf("schema version=%s definitions=%d", e.schema.Version, len(e.schema.Definitions)), nil
}

// Check performs a permission check.
func (e *Engine) Check(ctx context.Context, req *CheckRequest) (*CheckResponse, error) {
	e.schemaMu.RLock()
	schema := e.schema
	e.schemaMu.RUnlock()

	if schema == nil {
		return &CheckResponse{Result: CheckDenied, Verdict: "DENIED", Reasoning: "no schema loaded"}, nil
	}

	rev, err := e.storage.CurrentRevision(ctx)
	if err != nil {
		return nil, fmt.Errorf("getting revision: %w", err)
	}

	result, err := e.evaluateCheck(ctx, req, rev)
	if err != nil {
		return nil, err
	}

	resp := &CheckResponse{}
	switch result {
	case CheckAllowed:
		resp.Result = CheckAllowed
		resp.Verdict = "ALLOWED"
	case CheckConditional:
		resp.Result = CheckConditional
		resp.Verdict = "CONDITIONAL"
	default:
		resp.Result = CheckDenied
		resp.Verdict = "DENIED"
	}
	resp.DecisionToken = e.zookieMgr.Mint(rev)
	resp.Reasoning = fmt.Sprintf("check %s#%s@%s = %s", req.Resource, req.Permission, req.Subject, resp.Verdict)
	return resp, nil
}

// WriteTuples writes relationship tuples to storage.
func (e *Engine) WriteTuples(ctx context.Context, tuples []types.Tuple) (string, error) {
	rev, err := e.storage.WriteTuples(ctx, tuples)
	if err != nil {
		return "", err
	}
	return e.zookieMgr.Mint(rev), nil
}

// DeleteTuples removes tuples matching a filter.
func (e *Engine) DeleteTuples(ctx context.Context, filter types.TupleFilter) (string, error) {
	rev, err := e.storage.DeleteTuples(ctx, filter)
	if err != nil {
		return "", err
	}
	return e.zookieMgr.Mint(rev), nil
}

// ReadTuples returns tuples matching a filter.
func (e *Engine) ReadTuples(ctx context.Context, filter types.TupleFilter) (storage.TupleIterator, error) {
	rev, err := e.storage.CurrentRevision(ctx)
	if err != nil {
		return nil, err
	}
	return e.storage.ReadTuples(ctx, filter, rev)
}

// Watch streams tuple change events starting from a given zookie.
func (e *Engine) Watch(ctx context.Context, afterZookie string) (<-chan storage.WatchEvent, error) {
	var rev Revision
	if afterZookie != "" {
		r, err := e.zookieMgr.Decode(afterZookie)
		if err != nil {
			return nil, fmt.Errorf("invalid watch zookie: %w", err)
		}
		rev = r
	}
	return e.storage.Watch(ctx, rev)
}
ENDOFFILE
echo "  [OK] internal/rebac/engine.go"

cat > internal/rebac/engine_test.go << 'ENDOFFILE'
package rebac_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/rebac"
	"github.com/youorg/zanzipay/internal/storage/memory"
	"github.com/youorg/zanzipay/pkg/types"
)

var stripeSchema = `
definition user {}

definition team {
    relation member: user
    relation admin: user
    permission access = admin + member
}

definition account {
    relation owner: user
    relation viewer: user
    permission manage = owner
    permission view = owner + viewer
}
`

func TestEngineEndToEnd(t *testing.T) {
	store := memory.New()
	engine, err := rebac.NewEngine(store)
	if err != nil {
		t.Fatalf("NewEngine() error = %v", err)
	}
	ctx := context.Background()

	if err := engine.WriteSchema(ctx, stripeSchema); err != nil {
		t.Fatalf("WriteSchema() error = %v", err)
	}

	// Grant alice owner of acme
	zookie, err := engine.WriteTuples(ctx, []types.Tuple{{
		ResourceType: "account", ResourceID: "acme",
		Relation: "owner", SubjectType: "user", SubjectID: "alice",
	}})
	if err != nil {
		t.Fatalf("WriteTuples() error = %v", err)
	}
	if zookie == "" {
		t.Fatal("WriteTuples() returned empty zookie")
	}

	// alice should be able to manage
	resp, err := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    rebac.SubjectRef{Type: "user", ID: "alice"},
	})
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if resp.Result != rebac.CheckAllowed {
		t.Errorf("alice.manage = %s, want ALLOWED", resp.Verdict)
	}

	// bob should be denied
	resp2, _ := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "manage",
		Subject:    rebac.SubjectRef{Type: "user", ID: "bob"},
	})
	if resp2.Result != rebac.CheckDenied {
		t.Error("bob.manage should be DENIED")
	}

	// alice view (owner + viewer) should be allowed
	resp3, _ := engine.Check(ctx, &rebac.CheckRequest{
		Resource:   rebac.ObjectRef{Type: "account", ID: "acme"},
		Permission: "view",
		Subject:    rebac.SubjectRef{Type: "user", ID: "alice"},
	})
	if resp3.Result != rebac.CheckAllowed {
		t.Errorf("alice.view = %s, want ALLOWED", resp3.Verdict)
	}
}
ENDOFFILE
echo "  [OK] internal/rebac/engine_test.go"

echo "=== internal/rebac/engine done ==="
ENDOFFILE
echo "Part 7 script written"
