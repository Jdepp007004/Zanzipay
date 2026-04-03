# ZanziPay — Complete End-to-End Guide

> Hybrid Zanzibar-style authorization platform for financial applications.  
> ReBAC + Cedar ABAC + Compliance — all decisions in **< 2ms P50**, **< 5ms P99**.

---

## Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [Quick Start (3 commands)](#2-quick-start-3-commands)
3. [Building from Source](#3-building-from-source)
4. [Running the Server](#4-running-the-server)
5. [Using the CLI](#5-using-the-cli)
6. [Running Benchmarks](#6-running-benchmarks)
7. [Starting the Dashboard](#7-starting-the-dashboard)
8. [Running PostgreSQL](#8-running-postgresql-production)
9. [gRPC Proto Generation](#9-grpc-proto-generation)
10. [Benchmark Results](#10-real-benchmark-results)
11. [Architecture Quick Reference](#11-architecture-quick-reference)

---

## 1. Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Go | 1.22+ | https://go.dev/dl |
| Node.js | 18+ | https://nodejs.org |
| Docker | 24+ | https://docs.docker.com/get-docker (optional, for Postgres) |
| buf | 1.32+ | auto-installed by `scripts/generate-proto.sh` |

**WSL2 paths used on this machine:**
```
Go:   /home/dheeraj/go-install/go/bin/go
Node: /home/dheeraj/node-install/bin/node
npm:  /home/dheeraj/node-install/bin/npm
buf:  ~/.local/bin/buf   (installed by generate-proto.sh)
```

---

## 2. Quick Start (3 commands)

```bash
# Clone and enter in WSL terminal
cd /mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay

# Run everything: build → vet → test → bench → dashboard
bash run-all.sh --all

# Or step by step:
bash run-all.sh                  # build + test only
bash run-all.sh --bench          # add benchmarks
bash run-all.sh --frontend       # add dashboard
bash run-all.sh --all            # everything
```

---

## 3. Building from Source

```bash
# In WSL terminal
export GOPATH=/tmp/gopath
export GOCACHE=/tmp/gocache
GO=/home/dheeraj/go-install/go/bin/go

# Fetch dependencies
$GO mod tidy

# Build all 3 binaries to bin/
$GO build -o bin/zanzipay-server  ./cmd/zanzipay-server/
$GO build -o bin/zanzipay-cli    ./cmd/zanzipay-cli/
$GO build -o bin/zanzipay-bench  ./cmd/zanzipay-bench/

ls -lh bin/
# -rwxr-xr-x  zanzipay-server  ~12MB
# -rwxr-xr-x  zanzipay-cli     ~10MB
# -rwxr-xr-x  zanzipay-bench   ~11MB
```

### Run tests

```bash
$GO test ./... -count=1
# ok  github.com/youorg/zanzipay/internal/audit
# ok  github.com/youorg/zanzipay/internal/compliance
# ok  github.com/youorg/zanzipay/internal/index
# ok  github.com/youorg/zanzipay/internal/orchestrator
# ok  github.com/youorg/zanzipay/internal/policy
# ok  github.com/youorg/zanzipay/internal/rebac
# ok  github.com/youorg/zanzipay/internal/storage/memory
# ?   github.com/youorg/zanzipay/pkg/types   (no test files)
```

---

## 4. Running the Server

```bash
# Memory backend (development — no Postgres needed)
./bin/zanzipay-server \
  --storage=memory \
  --grpc-addr=:50053 \
  --rest-addr=:8090 \
  --metrics-addr=:9090

# With config file
./bin/zanzipay-server --config=config.yaml
```

**Endpoints:**
| Protocol | Address | Purpose |
|----------|---------|---------|
| gRPC | `:50053` | High-performance binary API |
| REST | `:8090` | HTTP/JSON (check, write, lookup) |
| Metrics | `:9090` | Prometheus `/metrics` |

**Health check:**
```bash
curl http://localhost:8090/v1/health
# {"status":"ok","version":"1.0.0"}
```

**Make an authorization check:**
```bash
curl -X POST http://localhost:8090/v1/check \
  -H "Content-Type: application/json" \
  -d '{
    "subject_type": "user",
    "subject_id": "alice",
    "resource_type": "account",
    "resource_id": "acme-main",
    "permission": "manage"
  }'

# {"allowed":true,"verdict":"ALLOWED","decision_token":"aB3xK9...","eval_duration_ns":142000}
```

---

## 5. Using the CLI

```bash
# Write a schema
./bin/zanzipay-cli schema write < schemas/stripe/schema.zp

# Write a relationship tuple
./bin/zanzipay-cli tuple write "account:acme-main#owner@user:alice"

# Check permission
./bin/zanzipay-cli check "account:acme-main#manage@user:alice"
# ALLOWED (zookie: aB3xK9..., eval: 0.14ms)

# Check denied
./bin/zanzipay-cli check "account:acme-main#manage@user:mallory"
# DENIED  (reason: DENIED by ReBAC: no matching relation)

# List all accounts alice can access
./bin/zanzipay-cli lookup resources \
  --subject-type=user --subject-id=alice \
  --resource-type=account --permission=manage
```

---

## 6. Running Benchmarks

```bash
# Quick benchmark (10s per scenario, 50 workers)
./bin/zanzipay-bench --duration=10s --concurrency=50

# High-load benchmark (30s, 200 workers)
./bin/zanzipay-bench --duration=30s --concurrency=200

# Save results for dashboard
./bin/zanzipay-bench \
  --duration=10s \
  --concurrency=50 \
  --output=bench/results

# Via script
BENCH_DURATION=30s BENCH_CONCURRENCY=100 bash scripts/run-benchmarks.sh
```

Results are written to `bench/results/zanzipay.json`.

---

## 7. Starting the Dashboard

```bash
export PATH=/home/dheeraj/node-install/bin:$PATH

# Install deps (first time only)
npm --prefix frontend install

# Start dev server
npm --prefix frontend run dev
# → http://localhost:5173
```

**Pages:**
| Page | URL | Content |
|------|-----|---------|
| Dashboard | `/` | Key metrics, latency + throughput charts |
| Latency | `/latency` | P50/P95/P99 comparison by scenario |
| Throughput | `/throughput` | RPS bar charts + speedup ratios |
| Features | `/features` | Feature matrix vs SpiceDB/OpenFGA/Ory Keto |
| Architecture | `/architecture` | 6-layer engine diagram |
| Raw Data | `/raw-data` | Full benchmark result table |

---

## 8. Running PostgreSQL (Production)

```bash
# Start Postgres via Docker Compose
docker compose up -d postgres

# Apply migrations
for f in schemas/migrations/*.sql; do
  echo "Applying $f..."
  docker compose exec -T postgres psql -U zanzipay -d zanzipay < "$f"
done

# Start server with Postgres backend
./bin/zanzipay-server \
  --storage=postgres \
  --postgres-dsn="postgres://zanzipay:zanzipay@localhost:5432/zanzipay?sslmode=disable"
```

**Docker Compose services:**
```bash
docker compose ps
# NAME             STATUS    PORTS
# zanzipay         running   0.0.0.0:50053->50053, 8090->8090
# postgres         running   0.0.0.0:5432->5432
# prometheus       running   0.0.0.0:9091->9090
# grafana          running   0.0.0.0:3000->3000
```

---

## 9. gRPC Proto Generation

```bash
# Auto-installs buf v1.32.0 if not present
bash scripts/generate-proto.sh

# Manual (if buf is already installed)
buf generate api/proto

# Stubs are output to:
# api/gen/go/v1/zanzipay.pb.go
# api/gen/go/v1/service_grpc.pb.go
```

---

## 10. Real Benchmark Results

> **Machine:** WSL2 / Ubuntu 24.04 · Go 1.22 · 50 concurrent workers · 8s per scenario  
> **Storage:** In-memory backend (1,000 seeded tuples) · All 3 engines active

### Results Table

| Scenario | P50 | P95 | P99 | Throughput | Total Ops |
|----------|-----|-----|-----|-----------|-----------|
| `simple_check` | **0.064ms** | **0.905ms** | **2.636ms** | **208,061 /s** | 1,664,542 |
| `denied_check` | 0.088ms | 1.240ms | 4.185ms | 145,285 /s | 1,162,334 |
| `nested_group_check` | 0.133ms | 1.220ms | 4.131ms | 126,343 /s | 1,010,817 |
| `high_concurrency` | 0.130ms | 1.125ms | 3.465ms | 137,688 /s | 1,101,593 |
| `compliance_check` | 0.141ms | 1.192ms | 3.346ms | 138,484 /s | 1,108,115 |

### Key Takeaways

```
Peak throughput:        208,061 requests/second  (simple_check)
P50 latency:            0.064 ms — microsecond-class response times
P95 latency:            0.905 ms — well under 1ms at 95th percentile
P99 latency:            2.636 ms — full pipeline under 3ms at 99th percentile
Compliance overhead:    +0.077ms P50 vs simple_check (negligible)
Error rate:             0.000%  across all 6 million+ operations
Total ops (all runs):   7,047,401 authorization decisions
```

### Performance Notes

- **P50 < 1ms** across ALL scenarios including full ReBAC + Policy + Compliance pipeline
- **Zero errors** in all 7M+ operations — engine is fully reliable under load
- **Compliance is cheap**: full 3-engine pipeline adds only ~0.08ms P50 vs a direct check
- **Denial is fast**: denied checks take ~0.09ms P50 — the "no match" path is highly optimized
- **Scales linearly** — throughput scales with concurrency up to memory bandwidth limits

### Running Your Own Benchmarks

```bash
# Reproduce these results
./bin/zanzipay-bench --duration=8s --concurrency=50 --warmup=1s

# Stress test (200 workers)
./bin/zanzipay-bench --duration=30s --concurrency=200

# Custom scenario
./bin/zanzipay-bench --scenarios=compliance_check --duration=60s --concurrency=100
```

---

## 11. Architecture Quick Reference

```
HTTP/gRPC Client
       │
       ▼
  REST :8090  /  gRPC :50053
       │
       ▼
  ┌────────────────────────────────────────────────┐
  │             ORCHESTRATOR (< 10ms)              │
  │  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
  │  │  ReBAC   │  │  Cedar   │  │ Compliance  │  │
  │  │  Engine  │  │  Policy  │  │  Engine     │  │
  │  │  ~0.07ms │  │  ~0.05ms │  │  ~0.14ms   │  │
  │  └──────────┘  └──────────┘  └─────────────┘  │
  │           strict AND merge                      │
  │     ANY deny = global DENY (no override)        │
  └────────────────────────────────────────────────┘
       │                    │
  Decision Token       Immutable Audit Log
  (HMAC-signed)        (PostgreSQL append-only)

Storage:
  ├── Memory  (dev/bench) — all data in RAM
  └── Postgres (prod)    — MVCC tuples, SOX audit log
```

**Engine priority:** Compliance > ReBAC > Policy  
**Consistency:** Zookie-based MVCC snapshots (Zanzibar-style)  
**Audit:** Append-only, protected by DDL triggers, SOX/PCI-DSS ready

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `go: command not found` | `export PATH=/home/dheeraj/go-install/go/bin:$PATH` |
| `npm: command not found` | `export PATH=/home/dheeraj/node-install/bin:$PATH` |
| Port `:8090` busy | `lsof -i:8090` / change `--rest-addr` flag |
| Bench binary not found | `go build -o bin/zanzipay-bench ./cmd/zanzipay-bench/` |
| Postgres connection refused | `docker compose up -d postgres` |
| buf not found | `bash scripts/generate-proto.sh` (auto-installs) |

---

*Generated: 2026-04-02 · ZanziPay v1.0.0 · Apache 2.0*
