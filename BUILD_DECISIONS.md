# ZanziPay — Build Decisions & Environment Configuration

## WSL Environment Details

| Property | Value |
|---|---|
| **WSL Distro** | Ubuntu 24.04 LTS (Noble Numbat) |
| **Kernel** | Linux 6.6.8 x86_64 |
| **Docker** | Available (Docker Desktop 29.1.3 via WSL2 integration) |
| **Go** | ❌ NOT INSTALLED — needs installation |
| **Node.js** | ❌ NOT INSTALLED — needs installation |
| **npm** | ✅ Available (10.9.0) |
| **Python3** | ✅ Available (/usr/bin/python3) |
| **Git** | needs verification |

---

## Installation Plan (inside WSL)

### Go Installation
- Install Go 1.22+ via official tarball (architecture mandates Go 1.22+)
- Path: `/usr/local/go`
- Add to `.bashrc`: `export PATH=$PATH:/usr/local/go/bin`

### Node.js Installation  
- Install Node.js 20+ via NodeSource (architecture mandates Node 20+)
- Use: `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -`

---

## Platform Decision

The architecture.md explicitly recommends:
- **Preferred**: Ubuntu 22.04 LTS bare metal (NOT WSL2 for benchmarking)
- **Available**: WSL2 with Ubuntu 24.04 LTS (Noble Numbat) on Docker Desktop

**Decision**: We develop the codebase IN WSL2 (Ubuntu 24.04). This is valid for:
- ✅ Building source code
- ✅ Running tests  
- ✅ Development iteration
- ⚠️ Benchmarking (WSL2 filesystem bridge adds non-deterministic latency — acceptable for dev, not for production benchmarks)

**WSL path for project**: `/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay`

---

## Go Module Configuration

| Setting | Value |
|---|---|
| **Module name** | `github.com/youorg/zanzipay` |
| **Go version** | `1.22` |
| **Primary language** | Go (engines, core) |
| **Secondary language** | TypeScript (frontend, CLI) |
| **Tertiary language** | Python (benchmarks) |

### Key Go Dependencies
- `google.golang.org/grpc` — gRPC server/client
- `google.golang.org/grpc/cmd/protoc-gen-go-grpc` — gRPC code gen
- `github.com/grpc-ecosystem/grpc-gateway/v2` — REST↔gRPC bridge
- `github.com/google/cel-go` — CEL expression engine (for caveats)
- `github.com/RoaringBitmap/roaring` — Roaring bitmaps for materialized index
- `github.com/lib/pq` or `github.com/jackc/pgx/v5` — PostgreSQL driver
- `github.com/spf13/cobra` — CLI framework
- `github.com/prometheus/client_golang` — Prometheus metrics
- `go.uber.org/zap` — Structured logging
- `github.com/oklog/ulid/v2` — ULID generation for audit records

### Key Frontend Dependencies
- `react` + `react-dom` — UI framework
- `react-router-dom` — Client-side routing
- `recharts` — Chart library (for benchmark visualization)
- `vite` — Build tool
- TypeScript — Type safety

---

## Architecture Summary (58 files across 6 layers)

### Layer 1: ReBAC Engine (`internal/rebac/`)
- 14 files (7 source + 7 test)
- Core: engine.go, check.go, caveat.go, zookie.go, schema.go, tuple.go, expand.go, namespace.go

### Layer 2: Policy Engine (`internal/policy/`)
- 14 files (7 source + 7 test)
- Core: engine.go, cedar_eval.go, cedar_parser.go, cedar_analyzer.go, temporal.go, abac.go, store.go

### Layer 3: Compliance Engine (`internal/compliance/`)
- Sanctions screening (OFAC/EU/UN), KYC gates, regulatory overrides, account freeze
- Plus: lists/ subdirectory (loader.go, matcher.go, updater.go)

### Layer 4: Decision Orchestrator (`internal/orchestrator/`)
- Parallel fan-out → strict AND merge → decision token minting

### Layer 5: Materialized Permission Index (`internal/index/`)
- Watch API consumer → Roaring bitmaps → sub-ms reverse lookups

### Layer 6: Immutable Audit Stream (`internal/audit/`)
- Append-only log, SOX/PCI reports, JSON/CSV/Parquet export

### Storage Backends (`internal/storage/`)
- PostgreSQL (primary), CockroachDB, in-memory (testing)
- 12 SQL migration files

### Servers (`internal/server/`)
- gRPC + REST gateway, middleware (auth, rate limit, logging, metrics)

### Public SDK (`pkg/`)
- Go client SDK, shared types, error codes

### CLI + Binaries (`cmd/`)
- zanzipay-server, zanzipay-cli, zanzipay-bench

### Benchmark Suite (`bench/`)
- 9 scenarios × 4 competitors + Python analysis

### Frontend (`frontend/`)
- React + Vite + Recharts dashboard

### Schemas (`schemas/`)
- stripe/, marketplace/, banking/ examples

### Deployment (`deploy/`)
- Docker, Kubernetes, Terraform

---

## Build Order (sequential dependency order)

1. **Root files**: go.mod, go.sum, Makefile, docker-compose files, .env.example, .gitignore
2. **Proto definitions**: api/proto/zanzipay/v1/*.proto
3. **Public types**: pkg/types/, pkg/errors/
4. **Storage interfaces**: internal/storage/interface.go
5. **Storage backends**: internal/storage/postgres/, cockroach/, memory/ + migrations
6. **Config**: internal/config/
7. **ReBAC engine**: internal/rebac/ (tuple → schema → zookie → caveat → check → expand → engine)
8. **Policy engine**: internal/policy/ (store → cedar_parser → cedar_eval → cedar_analyzer → temporal → abac → engine)
9. **Compliance engine**: internal/compliance/ (lists/ → sanctions → kyc → regulatory → freeze → engine)
10. **Orchestrator**: internal/orchestrator/ (verdict → token → orchestrator)
11. **Materialized index**: internal/index/ (bitmap → watcher → materializer → lookup)
12. **Audit stream**: internal/audit/ (decision → logger → reporter → exporter)
13. **Server**: internal/server/ (middleware/ → interceptors/ → grpc → rest → server)
14. **CLI binaries**: cmd/
15. **Public client SDK**: pkg/client/
16. **Benchmark suite**: bench/
17. **Example schemas**: schemas/
18. **Frontend**: frontend/
19. **Deployment configs**: deploy/
20. **Scripts & docs**: scripts/, docs/

---

## Server Configuration (`config.yaml`)

| Setting | Value |
|---|---|
| gRPC port | 50053 |
| REST port | 8090 |
| Metrics port | 9090 |
| PostgreSQL DSN | postgres://zanzipay:password@localhost:5432/zanzipay |
| ReBAC cache | 100,000 entries |
| Caveat timeout | 10ms |
| Policy eval timeout | 20ms |
| Audit retention | 2555 days (7 years, SOX) |
| Bitmap shards | 16 |

---

## Key Design Decisions

1. **No code generation**: Since protoc/buf may not be available in WSL, proto files are defined as-is and generated code is stubbed in Go files with build tags
2. **In-memory backend first**: All tests use the memory backend so no PostgreSQL needed to run tests
3. **Context-based timeouts**: Every engine has independent timeouts; fail-closed (DENY) on timeout
4. **Compliance has veto power**: Compliance DENY cannot be overridden by ReBAC or policy engines
5. **Watch API for incremental index updates**: Bitmap indexes are updated incrementally on tuple changes, with full rebuilds every 6 hours
6. **Audit immutability at DB level**: PostgreSQL triggers prevent UPDATE/DELETE on audit_log table
7. **Module path**: `github.com/youorg/zanzipay` (placeholder — replace with real org)
