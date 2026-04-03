#!/usr/bin/env bash
# ZanziPay — Benchmark Runner
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${BENCH_DURATION:-30s}"
CONCURRENCY="${BENCH_CONCURRENCY:-100}"
OUTPUT="$ROOT/bench/results"
BENCH_BIN="$ROOT/bin/zanzipay-bench"

mkdir -p "$OUTPUT"

if [ ! -f "$BENCH_BIN" ]; then
    echo "[bench] Building benchmark binary..."
    cd "$ROOT"
    go build -o "$BENCH_BIN" ./cmd/zanzipay-bench/
fi

echo "[bench] Running ZanziPay benchmarks..."
echo "  Duration:    $DURATION"
echo "  Concurrency: $CONCURRENCY"
echo "  Output:      $OUTPUT"
echo ""

"$BENCH_BIN" \
    --duration="$DURATION" \
    --concurrency="$CONCURRENCY" \
    --output="$OUTPUT"

echo ""
echo "[bench] Results written to $OUTPUT/zanzipay.json"

# Pretty print
if command -v jq >/dev/null 2>&1; then
    echo ""
    echo "=== Summary ==="
    jq -r '.[] | "\(.scenario)\tP50=\(.p50_ms)ms\tP95=\(.p95_ms)ms\tRPS=\(.throughput_rps)"' "$OUTPUT/zanzipay.json"
fi
