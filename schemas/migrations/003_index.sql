-- ZanziPay Schema: Materialized Index and Performance Tables
-- Migration 003

-- Materialized permission index (cached bitmap entries)
CREATE TABLE IF NOT EXISTS zp_index_entries (
    id             BIGSERIAL    PRIMARY KEY,
    subject_type   TEXT         NOT NULL,
    subject_id     TEXT         NOT NULL,
    resource_type  TEXT         NOT NULL,
    permission     TEXT         NOT NULL,
    resource_id    TEXT         NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (subject_type, subject_id, resource_type, permission, resource_id)
);

CREATE INDEX IF NOT EXISTS idx_index_forward  ON zp_index_entries (subject_type, subject_id, resource_type, permission);
CREATE INDEX IF NOT EXISTS idx_index_reverse  ON zp_index_entries (resource_type, permission, subject_type);

-- Index rebuild history
CREATE TABLE IF NOT EXISTS zp_index_rebuilds (
    id           BIGSERIAL    PRIMARY KEY,
    started_at   TIMESTAMPTZ  NOT NULL,
    completed_at TIMESTAMPTZ  NULL,
    entries      BIGINT       NOT NULL DEFAULT 0,
    success      BOOLEAN      NOT NULL DEFAULT FALSE
);

-- Metrics snapshots
CREATE TABLE IF NOT EXISTS zp_metrics (
    id              BIGSERIAL    PRIMARY KEY,
    ts              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    check_latency_p50 FLOAT8    NOT NULL DEFAULT 0,
    check_latency_p95 FLOAT8    NOT NULL DEFAULT 0,
    check_latency_p99 FLOAT8    NOT NULL DEFAULT 0,
    checks_per_second BIGINT    NOT NULL DEFAULT 0,
    error_rate      FLOAT8      NOT NULL DEFAULT 0,
    tuple_count     BIGINT      NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_metrics_ts ON zp_metrics (ts DESC);
