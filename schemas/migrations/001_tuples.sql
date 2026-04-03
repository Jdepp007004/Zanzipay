-- ZanziPay Schema: Relationship Tuples
-- Migration 001: Initial schema

CREATE TABLE IF NOT EXISTS zp_tuples (
    id             BIGSERIAL PRIMARY KEY,
    created_rev    BIGINT    NOT NULL,
    deleted_rev    BIGINT    NOT NULL DEFAULT 0,
    resource_type  TEXT      NOT NULL,
    resource_id    TEXT      NOT NULL,
    relation       TEXT      NOT NULL,
    subject_type   TEXT      NOT NULL,
    subject_id     TEXT      NOT NULL,
    subject_relation TEXT    NOT NULL DEFAULT '',
    caveat_name    TEXT      NOT NULL DEFAULT '',
    caveat_context JSONB     NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tuples_resource ON zp_tuples (resource_type, resource_id, relation, deleted_rev);
CREATE INDEX IF NOT EXISTS idx_tuples_subject  ON zp_tuples (subject_type, subject_id, subject_relation, deleted_rev);
CREATE INDEX IF NOT EXISTS idx_tuples_revision ON zp_tuples (created_rev, deleted_rev);

-- Transactions table for snapshot isolation
CREATE TABLE IF NOT EXISTS zp_transactions (
    id         BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    snapshot   BIGINT      NOT NULL DEFAULT 0
);

-- Schema definitions
CREATE TABLE IF NOT EXISTS zp_schemas (
    id         BIGSERIAL    PRIMARY KEY,
    version    TEXT         NOT NULL UNIQUE,
    source     TEXT         NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Changelog for the Watch stream
CREATE TABLE IF NOT EXISTS zp_changelog (
    id         BIGSERIAL    PRIMARY KEY,
    revision   BIGINT       NOT NULL,
    event_type TEXT         NOT NULL,    -- 'CREATE' | 'DELETE' | 'TOUCH'
    resource_type TEXT      NOT NULL,
    resource_id   TEXT      NOT NULL,
    relation      TEXT      NOT NULL,
    subject_type  TEXT      NOT NULL,
    subject_id    TEXT      NOT NULL,
    subject_relation TEXT   NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_changelog_revision ON zp_changelog (revision);
