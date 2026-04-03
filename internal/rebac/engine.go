package rebac

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// Engine is the core ReBAC engine.
type Engine struct {
	storage   storage.TupleStore
	schema    *Schema
	schemaMu  sync.RWMutex
	zookieMgr *ZookieManager
	opts      EngineOptions
	caveats   *CaveatEvaluator
}

// NewEngine creates a new ReBAC engine backed by the given storage.
func NewEngine(store storage.TupleStore, opts ...func(*EngineOptions)) (*Engine, error) {
	options := EngineOptions{
		CacheSize: 10000,
		HMACKey:   []byte("default-hmac-key-change-in-prod!"),
	}
	for _, opt := range opts {
		opt(&options)
	}
	return &Engine{
		storage:   store,
		zookieMgr: NewZookieManager(options.HMACKey, 5*time.Second),
		opts:      options,
		caveats:   NewCaveatEvaluator(),
	}, nil
}

// WriteSchema parses and installs a new schema definition.
func (e *Engine) WriteSchema(_ context.Context, schemaStr string) error {
	s, err := ParseSchema(schemaStr)
	if err != nil {
		return fmt.Errorf("parsing schema: %w", err)
	}
	if errs := ValidateSchema(s); len(errs) > 0 {
		return fmt.Errorf("schema validation: %v", errs)
	}

	if e.caveats != nil && s.Caveats != nil {
		for _, def := range s.Caveats {
			e.caveats.Register(*def)
		}
	}

	e.schemaMu.Lock()
	e.schema = s
	e.schemaMu.Unlock()
	return nil
}

// ReadSchema returns a summary of the current schema.
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
	resp.Reasoning = fmt.Sprintf("check %s:%s#%s@%s:%s = %s",
		req.Resource.Type, req.Resource.ID, req.Permission, req.Subject.Type, req.Subject.ID, resp.Verdict)
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
	var rev storage.Revision
	if afterZookie != "" {
		r, err := e.zookieMgr.Decode(afterZookie)
		if err != nil {
			return nil, fmt.Errorf("invalid watch zookie: %w", err)
		}
		rev = r
	}
	return e.storage.Watch(ctx, rev)
}
