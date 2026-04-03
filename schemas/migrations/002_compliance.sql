-- ZanziPay Schema: Compliance Tables
-- Migration 002

-- Immutable audit log
CREATE TABLE IF NOT EXISTS zp_audit_log (
    id              TEXT         PRIMARY KEY,
    ts              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    subject_type    TEXT         NOT NULL,
    subject_id      TEXT         NOT NULL,
    resource_type   TEXT         NOT NULL,
    resource_id     TEXT         NOT NULL,
    action          TEXT         NOT NULL DEFAULT '',
    allowed         BOOLEAN      NOT NULL,
    verdict         TEXT         NOT NULL,
    decision_token  TEXT         NOT NULL DEFAULT '',
    reasoning       TEXT         NOT NULL DEFAULT '',
    eval_duration_ns BIGINT      NOT NULL DEFAULT 0,
    client_id       TEXT         NOT NULL DEFAULT '',
    source_ip       TEXT         NOT NULL DEFAULT '',
    user_agent      TEXT         NOT NULL DEFAULT ''
);

-- Immutability triggers: prevent UPDATE and DELETE
CREATE OR REPLACE FUNCTION zp_audit_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit log is immutable: % on %', TG_OP, TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER trg_audit_no_update
    BEFORE UPDATE ON zp_audit_log
    FOR EACH ROW EXECUTE FUNCTION zp_audit_immutable();

CREATE TRIGGER trg_audit_no_delete
    BEFORE DELETE ON zp_audit_log
    FOR EACH ROW EXECUTE FUNCTION zp_audit_immutable();

CREATE INDEX IF NOT EXISTS idx_audit_subject   ON zp_audit_log (subject_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_resource  ON zp_audit_log (resource_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_ts        ON zp_audit_log (ts DESC);

-- Sanctions lists
CREATE TABLE IF NOT EXISTS zp_sanctions (
    id          BIGSERIAL    PRIMARY KEY,
    list_type   TEXT         NOT NULL,
    name        TEXT         NOT NULL,
    country     TEXT         NOT NULL DEFAULT '',
    reason      TEXT         NOT NULL DEFAULT '',
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sanctions_list ON zp_sanctions (list_type);

-- Account freezes
CREATE TABLE IF NOT EXISTS zp_freezes (
    id          BIGSERIAL    PRIMARY KEY,
    account_id  TEXT         NOT NULL,
    reason      TEXT         NOT NULL,
    authority   TEXT         NOT NULL DEFAULT '',
    frozen_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    lifted_at   TIMESTAMPTZ  NULL
);

CREATE INDEX IF NOT EXISTS idx_freezes_account ON zp_freezes (account_id);

-- Regulatory overrides / court orders
CREATE TABLE IF NOT EXISTS zp_regulatory_overrides (
    id            BIGSERIAL    PRIMARY KEY,
    resource_id   TEXT         NOT NULL,
    resource_type TEXT         NOT NULL,
    reason        TEXT         NOT NULL,
    authority     TEXT         NOT NULL,
    issued_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ  NULL,
    active        BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_regulatory_resource ON zp_regulatory_overrides (resource_id, active);

-- Cedar policy versions
CREATE TABLE IF NOT EXISTS zp_policies (
    id          BIGSERIAL    PRIMARY KEY,
    version     TEXT         NOT NULL UNIQUE,
    source      TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
