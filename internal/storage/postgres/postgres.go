// Package postgres provides a PostgreSQL storage backend for ZanziPay.
package postgres

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "github.com/lib/pq"
	"github.com/Jdepp007004/Zanzipay/internal/storage"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// Backend is the PostgreSQL implementation of all storage interfaces.
type Backend struct {
	db *sql.DB
}

// Config holds Postgres connection configuration.
type Config struct {
	DSN             string
	MaxConns        int
	MinConns        int
	MaxConnLifetime time.Duration
}

// New creates a Backend and validates connectivity.
func New(ctx context.Context, cfg Config) (*Backend, error) {
	db, err := sql.Open("postgres", cfg.DSN)
	if err != nil {
		return nil, fmt.Errorf("opening postgres: %w", err)
	}
	maxConns := cfg.MaxConns
	if maxConns <= 0 {
		maxConns = 50
	}
	db.SetMaxOpenConns(maxConns)
	db.SetMaxIdleConns(maxConns / 2)
	if cfg.MaxConnLifetime > 0 {
		db.SetConnMaxLifetime(cfg.MaxConnLifetime)
	}
	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("pinging postgres: %w", err)
	}
	return &Backend{db: db}, nil
}

// Close closes the underlying connection pool.
func (b *Backend) Close() error { return b.db.Close() }

// -----------------------------------------------------------------------
// TupleStore
// -----------------------------------------------------------------------

func (b *Backend) WriteTuples(ctx context.Context, tuples []types.Tuple) (storage.Revision, error) {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var rev storage.Revision
	if err := tx.QueryRowContext(ctx,
		`INSERT INTO zp_transactions(snapshot) VALUES(0) RETURNING id`,
	).Scan(&rev); err != nil {
		return 0, fmt.Errorf("creating transaction: %w", err)
	}

	for i := range tuples {
		t := tuples[i]
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO zp_tuples
				(created_rev,resource_type,resource_id,relation,subject_type,subject_id,subject_relation)
			VALUES ($1,$2,$3,$4,$5,$6,$7)
			ON CONFLICT DO NOTHING`,
			rev, t.ResourceType, t.ResourceID, t.Relation,
			t.SubjectType, t.SubjectID, t.SubjectRelation,
		); err != nil {
			return 0, fmt.Errorf("inserting tuple: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO zp_changelog
				(revision,event_type,resource_type,resource_id,relation,subject_type,subject_id,subject_relation)
			VALUES($1,'CREATE',$2,$3,$4,$5,$6,$7)`,
			rev, t.ResourceType, t.ResourceID, t.Relation,
			t.SubjectType, t.SubjectID, t.SubjectRelation,
		); err != nil {
			return 0, fmt.Errorf("inserting changelog: %w", err)
		}
	}
	return rev, tx.Commit()
}

func (b *Backend) DeleteTuples(ctx context.Context, filter types.TupleFilter) (storage.Revision, error) {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var rev storage.Revision
	if err := tx.QueryRowContext(ctx,
		`INSERT INTO zp_transactions(snapshot) VALUES(0) RETURNING id`,
	).Scan(&rev); err != nil {
		return 0, fmt.Errorf("creating delete transaction: %w", err)
	}

	query, args := buildDeleteQuery(filter, rev)
	if _, err := tx.ExecContext(ctx, query, args...); err != nil {
		return 0, fmt.Errorf("deleting tuples: %w", err)
	}
	return rev, tx.Commit()
}

func (b *Backend) ReadTuples(ctx context.Context, filter types.TupleFilter, snapshot storage.Revision) (storage.TupleIterator, error) {
	query, args := buildReadQuery(filter, snapshot)
	rows, err := b.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("reading tuples: %w", err)
	}
	return &rowIterator{rows: rows}, nil
}

func (b *Backend) Watch(ctx context.Context, afterRevision storage.Revision) (<-chan storage.WatchEvent, error) {
	ch := make(chan storage.WatchEvent, 1000)
	go b.watchLoop(ctx, afterRevision, ch)
	return ch, nil
}

func (b *Backend) watchLoop(ctx context.Context, startRev storage.Revision, ch chan<- storage.WatchEvent) {
	defer close(ch)
	rev := startRev
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			rows, err := b.db.QueryContext(ctx,
				`SELECT revision,event_type,resource_type,resource_id,relation,
				        subject_type,subject_id,subject_relation
				 FROM zp_changelog WHERE revision > $1 ORDER BY revision ASC LIMIT 500`, rev)
			if err != nil {
				continue
			}
			func() {
				defer func() { _ = rows.Close() }()
				for rows.Next() {
					var e storage.WatchEvent
					var t types.Tuple
					var eventType string
					if err := rows.Scan(
						&e.Revision, &eventType,
						&t.ResourceType, &t.ResourceID, &t.Relation,
						&t.SubjectType, &t.SubjectID, &t.SubjectRelation,
					); err != nil {
						continue
					}
					e.Tuple = t
					e.Type = storage.WatchEventType(eventType)
					select {
					case ch <- e:
						rev = e.Revision
					case <-ctx.Done():
						return
					}
				}
			}()
		}
	}
}

func (b *Backend) CurrentRevision(ctx context.Context) (storage.Revision, error) {
	var rev storage.Revision
	err := b.db.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(id),0) FROM zp_transactions`).Scan(&rev)
	return rev, err
}

// -----------------------------------------------------------------------
// AuditStore
// -----------------------------------------------------------------------

func (b *Backend) AppendDecisions(ctx context.Context, records []storage.DecisionRecord) error {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	for i := range records {
		r := records[i]
		if r.ID == "" {
			r.ID = fmt.Sprintf("%d-%d", time.Now().UnixNano(), i)
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO zp_audit_log
				(id,ts,subject_type,subject_id,resource_type,resource_id,action,
				 allowed,verdict,decision_token,reasoning,eval_duration_ns,
				 client_id,source_ip,user_agent)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
			ON CONFLICT(id) DO NOTHING`,
			r.ID, r.Timestamp, r.SubjectType, r.SubjectID,
			r.ResourceType, r.ResourceID, r.Action, r.Allowed, r.Verdict,
			r.DecisionToken, r.Reasoning, r.EvalDurationNs,
			r.ClientID, r.SourceIP, r.UserAgent,
		); err != nil {
			return fmt.Errorf("inserting audit record: %w", err)
		}
	}
	return tx.Commit()
}

func (b *Backend) QueryDecisions(ctx context.Context, filter storage.AuditFilter) ([]storage.DecisionRecord, error) {
	query := `SELECT id,ts,subject_type,subject_id,resource_type,resource_id,
	           action,allowed,verdict,decision_token,reasoning,eval_duration_ns,
	           client_id,source_ip,user_agent
	           FROM zp_audit_log WHERE 1=1`
	var args []interface{}
	n := 1
	if filter.SubjectID != "" {
		query += fmt.Sprintf(" AND subject_id=$%d", n)
		args = append(args, filter.SubjectID)
		n++
	}
	if filter.ResourceID != "" {
		query += fmt.Sprintf(" AND resource_id=$%d", n)
		args = append(args, filter.ResourceID)
		n++
	}
	if filter.StartTime != nil {
		query += fmt.Sprintf(" AND ts>=$%d", n)
		args = append(args, *filter.StartTime)
		n++
	}
	if filter.EndTime != nil {
		query += fmt.Sprintf(" AND ts<=$%d", n)
		args = append(args, *filter.EndTime)
		n++
	}
	query += " ORDER BY ts DESC"
	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", n)
		args = append(args, filter.Limit)
	}

	rows, err := b.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()

	var records []storage.DecisionRecord
	for rows.Next() {
		var r storage.DecisionRecord
		if err := rows.Scan(
			&r.ID, &r.Timestamp, &r.SubjectType, &r.SubjectID,
			&r.ResourceType, &r.ResourceID, &r.Action, &r.Allowed, &r.Verdict,
			&r.DecisionToken, &r.Reasoning, &r.EvalDurationNs,
			&r.ClientID, &r.SourceIP, &r.UserAgent,
		); err != nil {
			return nil, fmt.Errorf("scanning audit record: %w", err)
		}
		records = append(records, r)
	}
	return records, rows.Err()
}

// -----------------------------------------------------------------------
// ComplianceStore
// -----------------------------------------------------------------------

func (b *Backend) WriteSanctionsList(ctx context.Context, listType string, entries []storage.SanctionsEntry) error {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `DELETE FROM zp_sanctions WHERE list_type=$1`, listType); err != nil {
		return fmt.Errorf("clearing sanctions list: %w", err)
	}
	for i := range entries {
		e := entries[i]
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO zp_sanctions(list_type,name,country,reason) VALUES($1,$2,$3,$4)`,
			listType, e.Name, e.Country, e.Reason,
		); err != nil {
			return fmt.Errorf("inserting sanctions entry: %w", err)
		}
	}
	return tx.Commit()
}

func (b *Backend) ReadSanctionsList(ctx context.Context, listType string) ([]storage.SanctionsEntry, error) {
	rows, err := b.db.QueryContext(ctx,
		`SELECT name,list_type,country,reason FROM zp_sanctions WHERE list_type=$1`, listType)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var results []storage.SanctionsEntry
	for rows.Next() {
		var e storage.SanctionsEntry
		if err := rows.Scan(&e.Name, &e.ListType, &e.Country, &e.Reason); err != nil {
			return nil, err
		}
		results = append(results, e)
	}
	return results, rows.Err()
}

func (b *Backend) WriteFreeze(ctx context.Context, freeze storage.AccountFreeze) error {
	_, err := b.db.ExecContext(ctx,
		`INSERT INTO zp_freezes(account_id,reason,authority,frozen_at) VALUES($1,$2,$3,$4)`,
		freeze.AccountID, freeze.Reason, freeze.Authority, freeze.FrozenAt)
	return err
}

func (b *Backend) ReadFreezes(ctx context.Context, accountID string) ([]storage.AccountFreeze, error) {
	rows, err := b.db.QueryContext(ctx,
		`SELECT account_id,reason,authority,frozen_at,lifted_at
		 FROM zp_freezes WHERE account_id=$1 ORDER BY frozen_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var results []storage.AccountFreeze
	for rows.Next() {
		var f storage.AccountFreeze
		if err := rows.Scan(&f.AccountID, &f.Reason, &f.Authority, &f.FrozenAt, &f.LiftedAt); err != nil {
			return nil, err
		}
		results = append(results, f)
	}
	return results, rows.Err()
}

func (b *Backend) WriteRegulatoryOverride(ctx context.Context, o storage.RegulatoryOverride) error {
	_, err := b.db.ExecContext(ctx,
		`INSERT INTO zp_regulatory_overrides
			(resource_id,resource_type,reason,authority,issued_at,expires_at,active)
		 VALUES($1,$2,$3,$4,$5,$6,$7)`,
		o.ResourceID, o.ResourceType, o.Reason, o.Authority, o.IssuedAt, o.ExpiresAt, o.Active)
	return err
}

func (b *Backend) ReadRegulatoryOverrides(ctx context.Context, resourceID string) ([]storage.RegulatoryOverride, error) {
	rows, err := b.db.QueryContext(ctx,
		`SELECT resource_id,resource_type,reason,authority,issued_at,expires_at,active
		 FROM zp_regulatory_overrides WHERE resource_id=$1 AND active=true`, resourceID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var results []storage.RegulatoryOverride
	for rows.Next() {
		var o storage.RegulatoryOverride
		if err := rows.Scan(
			&o.ResourceID, &o.ResourceType, &o.Reason, &o.Authority,
			&o.IssuedAt, &o.ExpiresAt, &o.Active,
		); err != nil {
			return nil, err
		}
		results = append(results, o)
	}
	return results, rows.Err()
}

// -----------------------------------------------------------------------
// PolicyStore
// -----------------------------------------------------------------------

func (b *Backend) WritePolicies(ctx context.Context, policies, version string) error {
	_, err := b.db.ExecContext(ctx,
		`INSERT INTO zp_policies(version,source) VALUES($1,$2)
		 ON CONFLICT(version) DO UPDATE SET source=EXCLUDED.source`,
		version, policies)
	return err
}

func (b *Backend) ReadPolicies(ctx context.Context) (string, string, error) {
	var src, ver string
	err := b.db.QueryRowContext(ctx,
		`SELECT source,version FROM zp_policies ORDER BY created_at DESC LIMIT 1`).Scan(&src, &ver)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", nil
	}
	return src, ver, err
}

// -----------------------------------------------------------------------
// ChangelogStore
// -----------------------------------------------------------------------

func (b *Backend) AppendChange(ctx context.Context, change storage.ChangeEntry) error {
	_, err := b.db.ExecContext(ctx,
		`INSERT INTO zp_changelog
			(revision,event_type,resource_type,resource_id,relation,subject_type,subject_id,subject_relation)
		 VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,
		change.Revision, string(change.EventType),
		change.Tuple.ResourceType, change.Tuple.ResourceID, change.Tuple.Relation,
		change.Tuple.SubjectType, change.Tuple.SubjectID, change.Tuple.SubjectRelation)
	return err
}

func (b *Backend) ReadChanges(ctx context.Context, after storage.Revision, limit int) ([]storage.ChangeEntry, error) {
	rows, err := b.db.QueryContext(ctx,
		`SELECT revision,event_type,resource_type,resource_id,relation,subject_type,subject_id,subject_relation
		 FROM zp_changelog WHERE revision > $1 ORDER BY revision ASC LIMIT $2`,
		after, limit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var results []storage.ChangeEntry
	for rows.Next() {
		var c storage.ChangeEntry
		var t types.Tuple
		var et string
		if err := rows.Scan(
			&c.Revision, &et,
			&t.ResourceType, &t.ResourceID, &t.Relation,
			&t.SubjectType, &t.SubjectID, &t.SubjectRelation,
		); err != nil {
			return nil, err
		}
		c.EventType = et
		c.Tuple = t
		results = append(results, c)
	}
	return results, rows.Err()
}

// -----------------------------------------------------------------------
// Query helpers
// -----------------------------------------------------------------------

func buildReadQuery(filter types.TupleFilter, snapshot storage.Revision) (string, []interface{}) {
	q := `SELECT resource_type,resource_id,relation,subject_type,subject_id,subject_relation
	      FROM zp_tuples
	      WHERE created_rev <= $1 AND (deleted_rev = 0 OR deleted_rev > $1)`
	args := []interface{}{snapshot}
	n := 2
	if filter.ResourceType != "" {
		q += fmt.Sprintf(" AND resource_type=$%d", n)
		args = append(args, filter.ResourceType)
		n++
	}
	if filter.ResourceID != "" {
		q += fmt.Sprintf(" AND resource_id=$%d", n)
		args = append(args, filter.ResourceID)
		n++
	}
	if filter.Relation != "" {
		q += fmt.Sprintf(" AND relation=$%d", n)
		args = append(args, filter.Relation)
		n++
	}
	if filter.SubjectType != "" {
		q += fmt.Sprintf(" AND subject_type=$%d", n)
		args = append(args, filter.SubjectType)
		n++
	}
	if filter.SubjectID != "" {
		q += fmt.Sprintf(" AND subject_id=$%d", n)
		args = append(args, filter.SubjectID)
		n++
	}
	_ = n // suppress unused variable warning
	return q, args
}

func buildDeleteQuery(filter types.TupleFilter, rev storage.Revision) (string, []interface{}) {
	q := `UPDATE zp_tuples SET deleted_rev=$1 WHERE deleted_rev=0`
	args := []interface{}{rev}
	n := 2
	if filter.ResourceType != "" {
		q += fmt.Sprintf(" AND resource_type=$%d", n)
		args = append(args, filter.ResourceType)
		n++
	}
	if filter.ResourceID != "" {
		q += fmt.Sprintf(" AND resource_id=$%d", n)
		args = append(args, filter.ResourceID)
		n++
	}
	if filter.Relation != "" {
		q += fmt.Sprintf(" AND relation=$%d", n)
		args = append(args, filter.Relation)
		n++
	}
	_ = n
	return q, args
}

// -----------------------------------------------------------------------
// TupleIterator
// -----------------------------------------------------------------------

type rowIterator struct {
	rows *sql.Rows
}

func (it *rowIterator) Next() (*types.Tuple, error) {
	if !it.rows.Next() {
		_ = it.rows.Close()
		return nil, fmt.Errorf("EOF")
	}
	var t types.Tuple
	if err := it.rows.Scan(
		&t.ResourceType, &t.ResourceID, &t.Relation,
		&t.SubjectType, &t.SubjectID, &t.SubjectRelation,
	); err != nil {
		return nil, err
	}
	return &t, nil
}

func (it *rowIterator) Close() error { return it.rows.Close() }
