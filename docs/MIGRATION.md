# Database Migration Guide

## Overview

ZanziPay uses plain SQL migrations (no ORM). Migrations are located in `schemas/migrations/` and run in numeric order.

## Files

| File | Contents |
|------|----------|
| `001_tuples.sql` | Relationship tuples, transactions, schema versions, changelog |
| `002_compliance.sql` | Audit log (with immutability triggers), sanctions, freezes, regulatory overrides, Cedar policies |
| `003_index.sql` | Materialized permission index, rebuild history, metrics snapshots |

## Running Migrations

### Development (via Docker Compose)

```bash
# Start Postgres
docker compose up -d postgres

# Wait for ready
docker compose exec postgres pg_isready

# Apply all migrations in order
for f in schemas/migrations/*.sql; do
  echo "Applying $f..."
  docker compose exec -T postgres psql -U zanzipay -d zanzipay < "$f"
done
```

### Production

```bash
# Using psql directly
for f in schemas/migrations/*.sql; do
  psql "$DATABASE_URL" -f "$f"
done

# Or via the setup script
./scripts/setup.sh
```

### Checking Applied Migrations

```sql
-- See all tuples tables
\dt zp_*

-- Check audit log immutability
INSERT INTO zp_audit_log(id) VALUES('test'); -- Should raise: "audit log is immutable"
```

## Schema Breakdown

### `zp_tuples`

Stores all relationship tuples with MVCC versioning:

```
created_rev  — transaction ID when tuple was created
deleted_rev  — transaction ID when tuple was deleted (0 = alive)
```

Indexes optimized for Zanzibar-style queries:
- **Forward**: `(resource_type, resource_id, relation, deleted_rev)` — for check and expand
- **Reverse**: `(subject_type, subject_id, subject_relation, deleted_rev)` — for lookup resources

### `zp_audit_log`

Append-only (protected by DDL triggers that raise exceptions on UPDATE/DELETE):
- 7-year retention requirement for SOX compliance
- Index on `(subject_id, ts DESC)` and `(resource_id, ts DESC)` for fast reporting

### `zp_changelog`

Lightweight event stream consumed by the materialized index and Watch clients:
```
revision    — transaction ID (monotonic)
event_type  — CREATE | DELETE | TOUCH
```

## Postgres Configuration Recommendations

```conf
# postgresql.conf tuning for ZanziPay workloads

# Connection pooling (use PgBouncer in production)
max_connections = 200

# WAL for replication and audit durability
wal_level = replica
synchronous_commit = on

# Query planning
random_page_cost = 1.1   # for SSD
effective_cache_size = 8GB
shared_buffers = 2GB
work_mem = 16MB

# Autovacuum (critical for MVCC tuple churn)
autovacuum_vacuum_scale_factor = 0.02
autovacuum_analyze_scale_factor = 0.01
```

## Rollback Policy

Migrations are **not reversible** (audit tables have immutability triggers). To roll back:

1. Restore from a pre-migration backup
2. Or add new forward migrations that archive and drop the unwanted tables

## Adding New Migrations

Name format: `NNN_description.sql` where NNN is zero-padded (e.g., `004_rate_limits.sql`).

```sql
-- 004_rate_limits.sql
CREATE TABLE IF NOT EXISTS zp_rate_limits (
    id         BIGSERIAL PRIMARY KEY,
    subject_id TEXT NOT NULL,
    window_sec INT  NOT NULL DEFAULT 60,
    max_calls  INT  NOT NULL DEFAULT 1000,
    -- ...
);
```
