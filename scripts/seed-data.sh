#!/usr/bin/env bash
# ZanziPay — Seed Demo Data
set -euo pipefail

SERVER="${ZANZIPAY_ADDR:-localhost:8090}"
CLI="./bin/zanzipay-cli --server ${SERVER}"

echo "[seed] Loading stripe schema..."
$CLI schema write < schemas/stripe/schema.zp

echo "[seed] Writing stripe tuples..."
# Parse and write each tuple from YAML
$CLI tuple write "account:acme-main#owner@user:alice"
$CLI tuple write "merchant:acme-corp#admin@user:alice"
$CLI tuple write "team:payments-eng#member@user:alice"
$CLI tuple write "team:payments-eng#member@user:bob"

echo "[seed] Writing marketplace tuples..."
$CLI tuple write "listing:item-001#seller@user:seller-alice"
$CLI tuple write "order:order-001#buyer@user:buyer-bob"

echo "[seed] Verifying: alice can manage acme-main..."
$CLI check "account:acme-main#manage@user:alice"

echo "[seed] Verifying: unknown user denied..."
$CLI check "account:acme-main#manage@user:unknown"

echo "[seed] Seed complete!"
