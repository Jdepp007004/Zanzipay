# ZanziPay

**A Zanzibar-derived authorization platform built for fintech. Combines ReBAC, Cedar policies, and a compliance engine into a single decision service.**

---

[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?style=flat&logo=go)](https://go.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Build](https://img.shields.io/badge/build-passing-brightgreen)](#)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)](#)

---

## What It Is

Most authorization systems answer one question: *"Does this role allow this action?"*

ZanziPay answers a harder question:  
> **"Is this user's relationship to this resource valid, do the attribute conditions pass, and is there any compliance reason (sanctions, KYC, freeze, regulatory override) to block this?"**

It runs all three checks in parallel and returns a single verdict in **< 0.2ms** (engine only, in-memory).

---

## Architecture

```
Client (gRPC :50053 / REST :8090)
        │
        ▼
┌─────────────────────────────────────┐
│        Decision Orchestrator         │
│   Parallel fan-out · AND-merge       │
└──────┬──────────────┬───────────────┘
       │              │              │
       ▼              ▼              ▼
 ┌──────────┐  ┌──────────┐  ┌──────────────┐
 │  ReBAC   │  │  Cedar   │  │  Compliance  │
 │  Engine  │  │  Policy  │  │   Engine     │
 │          │  │  Engine  │  │              │
 │ Graph    │  │ permit / │  │ Sanctions    │
 │ walk +   │  │ forbid   │  │ KYC gate     │
 │ caveats  │  │ ABAC +   │  │ Freeze       │
 │ zookies  │  │ temporal │  │ Regulatory   │
 └──────────┘  └──────────┘  └──────────────┘
        │              │              │
        ▼              ▼              ▼
┌─────────────────────────────────────┐
│     Storage (Memory / PostgreSQL)    │
│     MVCC tuples · Changelog          │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│    Immutable Audit Log (SOX/PCI)    │
│  Append-only · HMAC-signed tokens   │
└─────────────────────────────────────┘
```

### Six Layers

| Layer | What It Does |
|-------|-------------|
| **ReBAC Engine** | Zanzibar-style graph walk — tuples, userset expansion, caveat evaluation, zookie consistency tokens |
| **Cedar Policy Engine** | AWS Cedar-compatible `permit`/`forbid` policies with ABAC conditions (`>`, `<=`, `in`, `&&`) and temporal rules (business hours, token expiry) |
| **Compliance Engine** | Sanctions screening (OFAC/EU/UN, Jaro-Winkler fuzzy match) · KYC tier gates · Account freeze enforcement · Regulatory overrides |
| **Decision Orchestrator** | Parallel fan-out to all three engines, strict AND-merge (any deny = final DENY), HMAC-signed decision tokens |
| **Materialized Permission Index** | Watch API-driven bitmap cache for sub-ms reverse lookups (`LookupResources`, `LookupSubjects`) |
| **Immutable Audit Stream** | Append-only decision log — full reasoning chain, eval duration, engine sub-verdicts — exportable to JSON/CSV, SOX/PCI reports |

---

## Quick Start

```bash
# Prerequisites: Go 1.22+, Node.js 20+
git clone https://github.com/<your-username>/zanzipay
cd zanzipay

# Copy config
cp config.yaml.example config.yaml

# Build all binaries
go build -o bin/zanzipay-server ./cmd/zanzipay-server/
go build -o bin/zanzipay-cli   ./cmd/zanzipay-cli/
go build -o bin/zanzipay-bench ./cmd/zanzipay-bench/

# Run server (in-memory backend, no DB needed)
./bin/zanzipay-server

# Check a permission
curl -s -X POST http://localhost:8090/v1/check \
  -H "Authorization: Bearer default-api-key" \
  -H "Content-Type: application/json" \
  -d '{"resource_type":"account","resource_id":"acme-001","permission":"view","subject_type":"user","subject_id":"alice"}'
```

---

## Benchmark Results

> **Tested:** 10 seconds · 50 concurrent workers · in-memory backend · WSL2 Ubuntu 24.04 / Go 1.22

| Scenario | P50 | P95 | P99 | Throughput | Ops | Errors |
|----------|-----|-----|-----|-----------|-----|--------|
| Simple check | **0.063ms** | 0.903ms | 2.434ms | **212,856 req/s** | 2,136,359 | 0% |
| Denied check | 0.221ms | 1.973ms | 5.699ms | 83,974 req/s | 839,804 | 0% |
| Nested group | 0.154ms | 1.335ms | 4.066ms | 119,955 req/s | 1,199,605 | 0% |
| High concurrency | 0.149ms | 1.290ms | 4.110ms | 121,004 req/s | 1,210,177 | 0% |
| Full compliance pipeline | 0.154ms | 1.567ms | 5.812ms | 106,314 req/s | 1,063,199 | 0% |

> ⚠️ These numbers use an **in-memory backend** — no network, no disk. Add ~2–5ms for PostgreSQL in production. Estimated production P95 ≈ 3–7ms, which is comparable to [SpiceDB (~5.76ms)](https://authzed.com/blog/performance-benchmarking) and [Google Zanzibar (<10ms)](https://www.usenix.org/conference/atc19/presentation/pang).

Run them yourself:
```bash
./bin/zanzipay-bench --duration=10s --concurrency=50 --warmup=2s --output=bench/results
python3 bench_print.py
```

---

## Writing a Schema

```
// Define resource types and relationships
definition user {}

definition organization {
    relation admin: user
    relation member: user
    permission manage = admin
    permission view   = admin + member
}

definition account {
    relation org:     organization
    relation owner:   user
    relation viewer:  user
    permission transfer = owner + org->admin
    permission view     = owner + viewer + org->member
}
```

```bash
# Deploy schema
./bin/zanzipay-cli schema write ./schemas/banking/schema.zp

# Write tuples
./bin/zanzipay-cli tuple write "organization:acme#admin@user:alice"
./bin/zanzipay-cli tuple write "account:001#org@organization:acme"

# Check permission
./bin/zanzipay-cli check "account:001#transfer@user:alice"
# → ALLOWED
```

---

## Cedar Policies

```cedar
// Permit transfers under $10K for verified users (business hours only)
permit(principal, action == "transfer", resource)
when {
    context.amount <= 10000 &&
    context.kyc_status == "verified" &&
    context.is_business_hours == true
};

// Forbid all large transfers without enhanced KYC
forbid(principal, action == "large_transfer", resource)
when { context.kyc_tier < 3 };
```

```bash
./bin/zanzipay-cli policy deploy ./schemas/banking/policies.cedar
```

---

## REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/check` | Authorization check |
| `POST` | `/v1/tuples` | Write relationship tuples |
| `POST` | `/v1/tuples/delete` | Delete tuples |
| `POST` | `/v1/schema` | Deploy schema |
| `GET` | `/v1/schema` | Read current schema |
| `POST` | `/v1/lookup` | Lookup resources by subject |
| `POST` | `/v1/policies` | Deploy Cedar policies |
| `GET` | `/v1/health` | Health check |

All endpoints require `Authorization: Bearer <api-key>` header.

---

## Running Tests

```bash
go test ./...          # All tests
go test ./... -v       # Verbose
go vet ./...           # Static analysis
```

---

## Project Structure

```
zanzipay/
├── cmd/                    # Runnable binaries
│   ├── zanzipay-server/    # Authorization server (gRPC + REST)
│   ├── zanzipay-cli/       # Admin CLI
│   └── zanzipay-bench/     # Benchmark runner
├── internal/
│   ├── rebac/              # ReBAC engine (graph walk, caveats, zookies, schema)
│   ├── policy/             # Cedar policy engine (parser, ABAC, temporal)
│   ├── compliance/         # Compliance engine (sanctions, KYC, freeze, regulatory)
│   ├── orchestrator/       # Decision fan-out and verdict merge
│   ├── audit/              # Immutable audit log (logger, reporter, exporter)
│   ├── index/              # Materialized permission index
│   ├── storage/            # Storage backends (memory, PostgreSQL)
│   ├── server/             # HTTP + gRPC server, middleware, interceptors
│   └── config/             # Configuration loading
├── pkg/
│   ├── types/              # Shared data types
│   ├── errors/             # Domain error types + gRPC status mapping
│   └── client/             # Go client SDK
├── schemas/                # Example schemas (Stripe, Marketplace, Banking)
├── bench/                  # Benchmark suite and results
├── frontend/               # React/Vite benchmark dashboard
├── deploy/                 # Docker, Kubernetes, Terraform
├── docs/                   # Architecture, schema language, Cedar guide
└── scripts/                # Setup, proto generation, seeding
```

---

## Deployment

```bash
# Docker
docker compose up -d

# With PostgreSQL
ZANZIPAY_STORAGE_ENGINE=postgres \
ZANZIPAY_STORAGE_DSN="postgres://zanzipay:password@localhost/zanzipay" \
./bin/zanzipay-server

# Kubernetes
kubectl apply -f deploy/kubernetes/
```

---

## Design Decisions

- **Deny overrides** — Any single engine DENY is final. A Compliance DENY can never be overridden by a Cedar permit.
- **Parallel evaluation** — All three engines run concurrently with a shared 100ms deadline. Slowest engine determines latency.
- **Consistency via Zookies** — Zanzibar-style HMAC-signed tokens prevent stale-read authorization bugs (the "new enemy" problem).
- **No CEL dependency** — Caveats use a self-contained expression evaluator. No CGO, single binary, zero runtime dependencies.
- **Immutable audit** — DDL triggers at the DB layer reject any UPDATE/DELETE on audit tables. Tamper-proof by construction.

---

## Inspired By

| System | What ZanziPay Takes From It |
|--------|-----------------------------|
| [Google Zanzibar](https://www.usenix.org/conference/atc19/presentation/pang) | Tuple-based ReBAC, zookie consistency, userset rewrites |
| [SpiceDB](https://github.com/authzed/spicedb) | Caveated relationships, schema language design |
| [AWS Cedar](https://www.cedarpolicy.com) | `permit`/`forbid` policy syntax, deny-overrides semantics |
| [OpenFGA](https://github.com/openfga/openfga) | Type-safe relation definitions |

---

## License

[Apache 2.0](LICENSE)
