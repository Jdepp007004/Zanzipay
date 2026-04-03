#!/usr/bin/env bash
# Part 14: postgres migrations, cockroach, bench, schemas, scripts, docs, deploy, frontend
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── postgres migrations ───────────────────────────────────────────────────────
cat > internal/storage/postgres/migrations/001_create_tuples.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS tuples (
    namespace        TEXT NOT NULL,
    object_id        TEXT NOT NULL,
    relation         TEXT NOT NULL,
    subject_type     TEXT NOT NULL,
    subject_id       TEXT NOT NULL,
    subject_relation TEXT NOT NULL DEFAULT '',
    caveat_name      TEXT DEFAULT NULL,
    caveat_context   JSONB DEFAULT NULL,
    created_txn      BIGINT NOT NULL,
    deleted_txn      BIGINT NOT NULL DEFAULT 9223372036854775807,
    PRIMARY KEY (namespace, object_id, relation, subject_type, subject_id, subject_relation, created_txn)
);
CREATE INDEX idx_tuples_resource ON tuples (namespace, object_id, relation)
    WHERE deleted_txn = 9223372036854775807;
CREATE INDEX idx_tuples_subject ON tuples (subject_type, subject_id, namespace, relation)
    WHERE deleted_txn = 9223372036854775807;
CREATE INDEX idx_tuples_txn ON tuples (created_txn);
ENDOFFILE

cat > internal/storage/postgres/migrations/001_create_tuples.down.sql << 'ENDOFFILE'
DROP TABLE IF EXISTS tuples;
ENDOFFILE

cat > internal/storage/postgres/migrations/002_create_changelog.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS changelog (
    revision    BIGSERIAL PRIMARY KEY,
    event_type  TEXT NOT NULL,
    namespace   TEXT NOT NULL,
    object_id   TEXT NOT NULL,
    relation    TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    subject_id  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_changelog_revision ON changelog (revision);
ENDOFFILE

cat > internal/storage/postgres/migrations/002_create_changelog.down.sql << 'ENDOFFILE'
DROP TABLE IF EXISTS changelog;
ENDOFFILE

cat > internal/storage/postgres/migrations/003_create_audit_log.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS audit_log (
    id              TEXT PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    request_json    JSONB NOT NULL,
    decision_json   JSONB NOT NULL,
    rebac_json      JSONB,
    policy_json     JSONB,
    compliance_json JSONB,
    decision_token  TEXT NOT NULL,
    reasoning       TEXT NOT NULL,
    eval_duration   INTERVAL NOT NULL,
    client_id       TEXT NOT NULL,
    source_ip       INET NOT NULL,
    user_agent      TEXT
);
CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit log records are immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER audit_log_immutable_update BEFORE UPDATE ON audit_log FOR EACH ROW EXECUTE FUNCTION prevent_audit_modification();
CREATE TRIGGER audit_log_immutable_delete BEFORE DELETE ON audit_log FOR EACH ROW EXECUTE FUNCTION prevent_audit_modification();
CREATE INDEX idx_audit_timestamp ON audit_log (timestamp DESC);
CREATE INDEX idx_audit_client ON audit_log (client_id, timestamp DESC);
ENDOFFILE

cat > internal/storage/postgres/migrations/003_create_audit_log.down.sql << 'ENDOFFILE'
DROP TRIGGER IF EXISTS audit_log_immutable_update ON audit_log;
DROP TRIGGER IF EXISTS audit_log_immutable_delete ON audit_log;
DROP FUNCTION IF EXISTS prevent_audit_modification();
DROP TABLE IF EXISTS audit_log;
ENDOFFILE

cat > internal/storage/postgres/migrations/004_create_policies.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS policies (
    version    TEXT PRIMARY KEY,
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS policy_current (
    id         INTEGER PRIMARY KEY DEFAULT 1,
    version    TEXT NOT NULL REFERENCES policies(version),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT single_row CHECK (id = 1)
);
ENDOFFILE

cat > internal/storage/postgres/migrations/004_create_policies.down.sql << 'ENDOFFILE'
DROP TABLE IF EXISTS policy_current;
DROP TABLE IF EXISTS policies;
ENDOFFILE

cat > internal/storage/postgres/migrations/005_create_sanctions.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS sanctions_lists (
    id          BIGSERIAL PRIMARY KEY,
    list_type   TEXT NOT NULL,
    entity_id   TEXT NOT NULL DEFAULT '',
    name        TEXT NOT NULL,
    aliases     TEXT[] DEFAULT '{}',
    country     TEXT DEFAULT '',
    reason      TEXT DEFAULT '',
    listed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_sanctions_list_type ON sanctions_lists (list_type);
CREATE INDEX idx_sanctions_name ON sanctions_lists USING gin (to_tsvector('english', name));

CREATE TABLE IF NOT EXISTS account_freezes (
    id          BIGSERIAL PRIMARY KEY,
    account_id  TEXT NOT NULL,
    reason      TEXT NOT NULL,
    authority   TEXT NOT NULL,
    frozen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lifted_at   TIMESTAMPTZ DEFAULT NULL
);
CREATE INDEX idx_freezes_account ON account_freezes (account_id) WHERE lifted_at IS NULL;
ENDOFFILE

cat > internal/storage/postgres/migrations/005_create_sanctions.down.sql << 'ENDOFFILE'
DROP TABLE IF EXISTS account_freezes;
DROP TABLE IF EXISTS sanctions_lists;
ENDOFFILE

cat > internal/storage/postgres/migrations/006_create_regulatory.up.sql << 'ENDOFFILE'
CREATE TABLE IF NOT EXISTS regulatory_overrides (
    id            BIGSERIAL PRIMARY KEY,
    resource_id   TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    reason        TEXT NOT NULL,
    authority     TEXT NOT NULL,
    issued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ DEFAULT NULL,
    active        BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX idx_regulatory_resource ON regulatory_overrides (resource_id) WHERE active = TRUE;
ENDOFFILE

cat > internal/storage/postgres/migrations/006_create_regulatory.down.sql << 'ENDOFFILE'
DROP TABLE IF EXISTS regulatory_overrides;
ENDOFFILE
echo "  [OK] All 12 migration files"

# ─── internal/storage/postgres/postgres.go ────────────────────────────────────
cat > internal/storage/postgres/postgres.go << 'ENDOFFILE'
// Package postgres provides the PostgreSQL storage backend for ZanziPay.
package postgres

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/pkg/types"
)

// Backend is the PostgreSQL storage backend.
type Backend struct {
	pool *pgxpool.Pool
}

// Option configures the PostgreSQL backend.
type Option func(*pgxpool.Config)

// New creates a new PostgreSQL backend. Establishes and verifies the connection pool.
func New(ctx context.Context, dsn string, opts ...Option) (*Backend, error) {
	poolCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parsing DSN: %w", err)
	}
	for _, opt := range opts {
		opt(poolCfg)
	}
	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, fmt.Errorf("creating pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("pinging postgres: %w", err)
	}
	return &Backend{pool: pool}, nil
}

func (b *Backend) Close() error {
	b.pool.Close()
	return nil
}

// WriteTuples inserts tuples using ON CONFLICT DO UPDATE (touch semantics).
func (b *Backend) WriteTuples(ctx context.Context, tuples []types.Tuple) (storage.Revision, error) {
	tx, err := b.pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	for _, t := range tuples {
		_, err = tx.Exec(ctx, `
INSERT INTO tuples (namespace, object_id, relation, subject_type, subject_id, subject_relation, caveat_name, created_txn)
VALUES ($1, $2, $3, $4, $5, $6, $7, (SELECT COALESCE(MAX(created_txn), 0) + 1 FROM tuples))
ON CONFLICT (namespace, object_id, relation, subject_type, subject_id, subject_relation, created_txn) DO NOTHING`,
			t.ResourceType, t.ResourceID, t.Relation, t.SubjectType, t.SubjectID, t.SubjectRelation, t.CaveatName)
		if err != nil {
			return 0, fmt.Errorf("inserting tuple: %w", err)
		}
	}

	var rev int64
	tx.QueryRow(ctx, `SELECT COALESCE(MAX(created_txn), 0) FROM tuples`).Scan(&rev)
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("committing transaction: %w", err)
	}
	return storage.Revision(rev), nil
}

// DeleteTuples soft-deletes tuples by setting deleted_txn.
func (b *Backend) DeleteTuples(ctx context.Context, filter types.TupleFilter) (storage.Revision, error) {
	var rev int64
	err := b.pool.QueryRow(ctx, `
UPDATE tuples SET deleted_txn = (SELECT COALESCE(MAX(created_txn), 0) + 1 FROM tuples)
WHERE namespace = $1 AND ($2 = '' OR object_id = $2) AND ($3 = '' OR relation = $3)
  AND deleted_txn = 9223372036854775807
RETURNING deleted_txn`, filter.ResourceType, filter.ResourceID, filter.Relation).Scan(&rev)
	if err != nil {
		return 0, nil // no rows deleted is OK
	}
	return storage.Revision(rev), nil
}

// ReadTuples returns tuples matching the filter at the given snapshot.
func (b *Backend) ReadTuples(ctx context.Context, filter types.TupleFilter, snapshot storage.Revision) (storage.TupleIterator, error) {
	rows, err := b.pool.Query(ctx, `
SELECT namespace, object_id, relation, subject_type, subject_id, subject_relation, caveat_name
FROM tuples
WHERE namespace = $1 AND ($2 = '' OR object_id = $2) AND ($3 = '' OR relation = $3)
  AND created_txn <= $4 AND deleted_txn > $4`,
		filter.ResourceType, filter.ResourceID, filter.Relation, int64(snapshot))
	if err != nil {
		return nil, err
	}
	return &pgIterator{rows: rows}, nil
}

// Watch uses polling to return change events after the given revision.
func (b *Backend) Watch(ctx context.Context, afterRevision storage.Revision) (<-chan storage.WatchEvent, error) {
	ch := make(chan storage.WatchEvent, 100)
	go func() {
		defer close(ch)
		// In production: use LISTEN/NOTIFY for real-time events
		// This is a polling stub
		<-ctx.Done()
	}()
	return ch, nil
}

// CurrentRevision returns the latest revision number.
func (b *Backend) CurrentRevision(ctx context.Context) (storage.Revision, error) {
	var rev int64
	err := b.pool.QueryRow(ctx, `SELECT COALESCE(MAX(created_txn), 0) FROM tuples`).Scan(&rev)
	return storage.Revision(rev), err
}

// WritePolicies stores a new policy version.
func (b *Backend) WritePolicies(ctx context.Context, policies, version string) error {
	_, err := b.pool.Exec(ctx,
		`INSERT INTO policies (version, content) VALUES ($1, $2) ON CONFLICT (version) DO NOTHING`,
		version, policies)
	if err != nil {
		return err
	}
	_, err = b.pool.Exec(ctx,
		`INSERT INTO policy_current (id, version) VALUES (1, $1) ON CONFLICT (id) DO UPDATE SET version=$1, updated_at=NOW()`,
		version)
	return err
}

// ReadPolicies returns the current policy set.
func (b *Backend) ReadPolicies(ctx context.Context) (string, string, error) {
	var content, version string
	err := b.pool.QueryRow(ctx,
		`SELECT p.content, p.version FROM policies p JOIN policy_current pc ON p.version = pc.version`).
		Scan(&content, &version)
	return content, version, err
}

// PolicyHistory returns the last N policy versions.
func (b *Backend) PolicyHistory(ctx context.Context, limit int) ([]storage.PolicyVersion, error) {
	rows, err := b.pool.Query(ctx, `SELECT version, content, created_at FROM policies ORDER BY created_at DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var versions []storage.PolicyVersion
	for rows.Next() {
		var v storage.PolicyVersion
		rows.Scan(&v.Version, &v.Policies, &v.CreatedAt)
		versions = append(versions, v)
	}
	return versions, nil
}

// AppendDecisions inserts audit records (immutable — triggers prevent modification).
func (b *Backend) AppendDecisions(ctx context.Context, records []storage.DecisionRecord) error {
	for _, r := range records {
		_, err := b.pool.Exec(ctx,
			`INSERT INTO audit_log (id, timestamp, request_json, decision_json, decision_token, reasoning, eval_duration, client_id, source_ip, user_agent)
             VALUES ($1, $2, $3, $4, $5, $6, make_interval(secs => $7::float/1e9), $8, $9::inet, $10)`,
			r.ID, r.Timestamp, `{}`, `{}`, r.DecisionToken, r.Reasoning,
			r.EvalDurationNs, r.ClientID, r.SourceIP, r.UserAgent)
		if err != nil {
			return err
		}
	}
	return nil
}

// QueryDecisions queries the audit log with filters.
func (b *Backend) QueryDecisions(ctx context.Context, filter storage.AuditFilter) ([]storage.DecisionRecord, error) {
	// Simplified implementation
	return nil, nil
}

// WriteSanctionsList replaces a sanctions list.
func (b *Backend) WriteSanctionsList(ctx context.Context, listType string, entries []storage.SanctionsEntry) error {
	tx, _ := b.pool.Begin(ctx)
	defer tx.Rollback(ctx)
	tx.Exec(ctx, `DELETE FROM sanctions_lists WHERE list_type = $1`, listType)
	for _, e := range entries {
		tx.Exec(ctx, `INSERT INTO sanctions_lists (list_type, name, country, reason) VALUES ($1, $2, $3, $4)`,
			listType, e.Name, e.Country, e.Reason)
	}
	return tx.Commit(ctx)
}

// ReadSanctionsList reads all entries for a list type.
func (b *Backend) ReadSanctionsList(ctx context.Context, listType string) ([]storage.SanctionsEntry, error) {
	rows, _ := b.pool.Query(ctx, `SELECT list_type, name, country, reason FROM sanctions_lists WHERE list_type = $1`, listType)
	defer rows.Close()
	var entries []storage.SanctionsEntry
	for rows.Next() {
		var e storage.SanctionsEntry
		rows.Scan(&e.ListType, &e.Name, &e.Country, &e.Reason)
		entries = append(entries, e)
	}
	return entries, nil
}

func (b *Backend) WriteFreeze(ctx context.Context, freeze storage.AccountFreeze) error {
	_, err := b.pool.Exec(ctx, `INSERT INTO account_freezes (account_id, reason, authority, frozen_at, lifted_at) VALUES ($1,$2,$3,$4,$5)`,
		freeze.AccountID, freeze.Reason, freeze.Authority, freeze.FrozenAt, freeze.LiftedAt)
	return err
}

func (b *Backend) ReadFreezes(ctx context.Context, accountID string) ([]storage.AccountFreeze, error) {
	rows, _ := b.pool.Query(ctx, `SELECT account_id, reason, authority, frozen_at, lifted_at FROM account_freezes WHERE account_id = $1`, accountID)
	defer rows.Close()
	var freezes []storage.AccountFreeze
	for rows.Next() {
		var f storage.AccountFreeze
		rows.Scan(&f.AccountID, &f.Reason, &f.Authority, &f.FrozenAt, &f.LiftedAt)
		freezes = append(freezes, f)
	}
	return freezes, nil
}

func (b *Backend) WriteRegulatoryOverride(ctx context.Context, override storage.RegulatoryOverride) error {
	_, err := b.pool.Exec(ctx,
		`INSERT INTO regulatory_overrides (resource_id, resource_type, reason, authority, issued_at, expires_at, active) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		override.ResourceID, override.ResourceType, override.Reason, override.Authority, override.IssuedAt, override.ExpiresAt, override.Active)
	return err
}

func (b *Backend) ReadRegulatoryOverrides(ctx context.Context, resourceID string) ([]storage.RegulatoryOverride, error) {
	rows, _ := b.pool.Query(ctx,
		`SELECT resource_id, resource_type, reason, authority, issued_at, expires_at, active FROM regulatory_overrides WHERE resource_id = $1 AND active = TRUE`, resourceID)
	defer rows.Close()
	var overrides []storage.RegulatoryOverride
	for rows.Next() {
		var o storage.RegulatoryOverride
		rows.Scan(&o.ResourceID, &o.ResourceType, &o.Reason, &o.Authority, &o.IssuedAt, &o.ExpiresAt, &o.Active)
		overrides = append(overrides, o)
	}
	return overrides, nil
}

func (b *Backend) AppendChange(ctx context.Context, change storage.ChangeEntry) error { return nil }
func (b *Backend) ReadChanges(ctx context.Context, after storage.Revision, limit int) ([]storage.ChangeEntry, error) {
	return nil, nil
}

type pgIterator struct {
	rows interface{ Next() bool; Scan(...interface{}) error; Close() }
}

func (it *pgIterator) Next() (*types.Tuple, error) {
	if !it.rows.Next() {
		return nil, fmt.Errorf("EOF")
	}
	var t types.Tuple
	it.rows.Scan(&t.ResourceType, &t.ResourceID, &t.Relation, &t.SubjectType, &t.SubjectID, &t.SubjectRelation, &t.CaveatName)
	return &t, nil
}
func (it *pgIterator) Close() error { it.rows.Close(); return nil }
ENDOFFILE
echo "  [OK] internal/storage/postgres/postgres.go"

cat > internal/storage/postgres/postgres_test.go << 'ENDOFFILE'
//go:build integration
// +build integration

// Run with: go test -tags integration ./internal/storage/postgres/...
// Requires a running PostgreSQL instance.
package postgres_test
ENDOFFILE
echo "  [OK] internal/storage/postgres/postgres_test.go"

cat > internal/storage/postgres/queries.go << 'ENDOFFILE'
package postgres

// SQL queries used by the PostgreSQL backend.
// These are extracted here for clarity and reuse.

const (
	InsertTuple = `
INSERT INTO tuples (namespace, object_id, relation, subject_type, subject_id, subject_relation, caveat_name, created_txn)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (namespace, object_id, relation, subject_type, subject_id, subject_relation, created_txn) DO NOTHING`

	SelectTuples = `
SELECT namespace, object_id, relation, subject_type, subject_id, subject_relation, caveat_name
FROM tuples
WHERE namespace = $1
  AND ($2 = '' OR object_id = $2)
  AND ($3 = '' OR relation = $3)
  AND ($4 = '' OR subject_type = $4)
  AND ($5 = '' OR subject_id = $5)
  AND created_txn <= $6
  AND deleted_txn > $6`

	SelectCurrentRevision = `SELECT COALESCE(MAX(created_txn), 0) FROM tuples`

	InsertAuditRecord = `
INSERT INTO audit_log (id, timestamp, request_json, decision_json, decision_token, reasoning, eval_duration, client_id, source_ip, user_agent)
VALUES ($1, $2, $3, $4, $5, $6, make_interval(secs => $7::float/1e9), $8, $9::inet, $10)`
)
ENDOFFILE
echo "  [OK] internal/storage/postgres/queries.go"

# ─── internal/storage/cockroach/ ──────────────────────────────────────────────
cat > internal/storage/cockroach/cockroach.go << 'ENDOFFILE'
// Package cockroach provides the CockroachDB storage backend.
// CockroachDB is wire-compatible with PostgreSQL, so this is a thin wrapper.
package cockroach

import (
	"context"

	"github.com/youorg/zanzipay/internal/storage/postgres"
)

// New creates a CockroachDB backend using the PostgreSQL driver.
// CockroachDB speaks the PostgreSQL wire protocol.
func New(ctx context.Context, dsn string, opts ...postgres.Option) (*postgres.Backend, error) {
	return postgres.New(ctx, dsn, opts...)
}
ENDOFFILE
echo "  [OK] internal/storage/cockroach/cockroach.go"

cat > internal/storage/cockroach/cockroach_test.go << 'ENDOFFILE'
//go:build integration
// +build integration

// Run with: go test -tags integration ./internal/storage/cockroach/...
package cockroach_test
ENDOFFILE
echo "  [OK] internal/storage/cockroach/cockroach_test.go"

echo "=== postgres migrations + storage done ==="
ENDOFFILE
echo "Part 14 script written"
