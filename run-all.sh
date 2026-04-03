#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  ZanziPay — Master Runner                               ║
# ║  One script to: build → test → bench → frontend         ║
# ╚══════════════════════════════════════════════════════════╝
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ── terminal colours ──────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[zanzipay]${NC} $1"; }
head() { echo -e "\n${BOLD}${CYAN}══ $1 ══${NC}"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
die()  { echo -e "\033[0;31m[error]${NC} $1" >&2; exit 1; }

# ── locate Go & Node ──────────────────────────────────────
GO_BIN="${GOBIN:-}"
for candidate in \
    /home/dheeraj/go-install/go/bin/go \
    /usr/local/go/bin/go \
    "$(which go 2>/dev/null)"; do
    if [ -x "$candidate" ]; then GO_BIN="$candidate"; break; fi
done
[ -z "$GO_BIN" ] && die "Go not found. Install from https://go.dev"

NODE_BIN="${NODEBIN:-}"
for candidate in \
    /home/dheeraj/node-install/bin/node \
    /usr/bin/node \
    "$(which node 2>/dev/null)"; do
    if [ -x "$candidate" ]; then NODE_BIN="$candidate"; break; fi
done
NPM_BIN="$(dirname "$NODE_BIN" 2>/dev/null)/npm"

export GOPATH="${GOPATH:-/tmp/gopath}"
export GOCACHE="${GOCACHE:-/tmp/gocache}"
export PATH="$(dirname "$GO_BIN"):${HOME}/.local/bin:$(dirname "${NODE_BIN:-/usr/bin/node}"):$PATH"

log "Go:   $GO_BIN ($("$GO_BIN" version | awk '{print $3}'))"
log "Root: $ROOT"

# ── parse flags ───────────────────────────────────────────
RUN_BENCH=false
RUN_FRONTEND=false
RUN_PROTO=false
BENCH_DURATION="${BENCH_DURATION:-10s}"
BENCH_CONCURRENCY="${BENCH_CONCURRENCY:-50}"
SKIP_TESTS=false

usage() {
    echo ""
    echo "  Usage: $0 [OPTIONS]"
    echo ""
    echo "  --bench           Also run benchmarks after tests"
    echo "  --frontend        Also install & start frontend dashboard"
    echo "  --proto           Also regenerate gRPC stubs with buf"
    echo "  --skip-tests      Skip go test (faster iteration)"
    echo "  --duration=10s    Benchmark duration per scenario"
    echo "  --concurrency=50  Benchmark concurrent workers"
    echo "  --all             Run everything"
    echo "  -h, --help        Show this help"
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        --bench)        RUN_BENCH=true ;;
        --frontend)     RUN_FRONTEND=true ;;
        --proto)        RUN_PROTO=true ;;
        --skip-tests)   SKIP_TESTS=true ;;
        --all)          RUN_BENCH=true; RUN_FRONTEND=true; RUN_PROTO=true ;;
        --duration=*)   BENCH_DURATION="${arg#--duration=}" ;;
        --concurrency=*) BENCH_CONCURRENCY="${arg#--concurrency=}" ;;
        -h|--help)      usage; exit 0 ;;
        *) warn "Unknown option: $arg" ;;
    esac
done

# ════════════════════════════════════════════════════════════
head "Phase 1: Dependencies"
# ════════════════════════════════════════════════════════════

log "Running go mod tidy..."
"$GO_BIN" mod tidy
log "go.mod is clean"

# ════════════════════════════════════════════════════════════
head "Phase 2: Build"
# ════════════════════════════════════════════════════════════

mkdir -p bin
log "Building zanzipay-server..."
"$GO_BIN" build -ldflags="-s -w" -o bin/zanzipay-server ./cmd/zanzipay-server/
log "Building zanzipay-cli..."
"$GO_BIN" build -ldflags="-s -w" -o bin/zanzipay-cli    ./cmd/zanzipay-cli/
log "Building zanzipay-bench..."
"$GO_BIN" build -ldflags="-s -w" -o bin/zanzipay-bench  ./cmd/zanzipay-bench/

echo ""
echo "  Binaries:"
ls -lh bin/zanzipay-{server,cli,bench} 2>/dev/null || true
echo ""

# ════════════════════════════════════════════════════════════
head "Phase 3: Vet"
# ════════════════════════════════════════════════════════════

log "Running go vet..."
"$GO_BIN" vet ./...
log "Vet: CLEAN"

# ════════════════════════════════════════════════════════════
head "Phase 4: Tests"
# ════════════════════════════════════════════════════════════

if [ "$SKIP_TESTS" = false ]; then
    log "Running go test ./... -count=1"
    "$GO_BIN" test ./... -count=1 -timeout=120s
    log "All tests: PASS"
else
    warn "Tests skipped (--skip-tests)"
fi

# ════════════════════════════════════════════════════════════
head "Phase 5: Benchmarks"
# ════════════════════════════════════════════════════════════

if [ "$RUN_BENCH" = true ]; then
    log "Running benchmark suite (duration=${BENCH_DURATION}, concurrency=${BENCH_CONCURRENCY})..."
    mkdir -p bench/results
    ./bin/zanzipay-bench \
        --duration="$BENCH_DURATION" \
        --concurrency="$BENCH_CONCURRENCY" \
        --output=bench/results

    echo ""
    echo "  Results saved → bench/results/zanzipay.json"

    if command -v python3 >/dev/null 2>&1; then
        echo ""
        python3 bench_print.py
    fi
else
    warn "Benchmarks skipped (pass --bench or --all to run)"
    if [ -f bench/results/zanzipay.json ]; then
        echo ""
        echo "  Previous results in bench/results/zanzipay.json:"
        python3 bench_print.py 2>/dev/null || true
    fi
fi

# ════════════════════════════════════════════════════════════
head "Phase 6: gRPC Proto Generation"
# ════════════════════════════════════════════════════════════

if [ "$RUN_PROTO" = true ]; then
    if command -v buf >/dev/null 2>&1 || [ -f "${HOME}/.local/bin/buf" ]; then
        log "Generating gRPC stubs..."
        bash scripts/generate-proto.sh
    else
        warn "buf not found — run: bash scripts/generate-proto.sh first"
    fi
else
    warn "Proto generation skipped (pass --proto or --all to run)"
fi

# ════════════════════════════════════════════════════════════
head "Phase 7: Frontend"
# ════════════════════════════════════════════════════════════

if [ "$RUN_FRONTEND" = true ]; then
    if [ -x "${NPM_BIN:-}" ]; then
        log "Installing frontend dependencies..."
        "$NPM_BIN" --prefix frontend install --silent

        log "Starting frontend dashboard (Ctrl+C to stop)..."
        echo ""
        echo "  Dashboard URL: http://localhost:5173"
        echo ""
        "$NPM_BIN" --prefix frontend run dev
    else
        warn "npm not found at $NPM_BIN — skipping frontend"
        echo "  Manual: cd frontend && npm install && npm run dev"
    fi
else
    warn "Frontend skipped (pass --frontend or --all to start)"
    echo ""
    echo "  To start manually:"
    echo "    cd frontend && npm install && npm run dev"
fi

# ════════════════════════════════════════════════════════════
head "Summary"
# ════════════════════════════════════════════════════════════

echo ""
echo -e "  ${GREEN}✓${NC}  go mod tidy"
echo -e "  ${GREEN}✓${NC}  go build (server, cli, bench)"
echo -e "  ${GREEN}✓${NC}  go vet"
[ "$SKIP_TESTS" = false ] && echo -e "  ${GREEN}✓${NC}  go test (all pass)"
[ "$RUN_BENCH"  = true  ] && echo -e "  ${GREEN}✓${NC}  benchmarks → bench/results/"
[ "$RUN_PROTO"  = true  ] && echo -e "  ${GREEN}✓${NC}  gRPC stubs → api/gen/go/"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  ${CYAN}./bin/zanzipay-server${NC}           — start authorization server"
echo -e "  ${CYAN}./bin/zanzipay-cli --help${NC}       — CLI reference"
echo -e "  ${CYAN}./run-all.sh --bench${NC}            — run benchmarks"
echo -e "  ${CYAN}./run-all.sh --frontend${NC}         — start dashboard"
echo -e "  ${CYAN}./run-all.sh --all${NC}              — do everything"
echo ""
