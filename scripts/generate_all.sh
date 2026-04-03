#!/usr/bin/env bash
# MASTER RUNNER — executes all gen_files_partN.sh scripts in order
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
SCRIPTS="$ROOT/scripts"

echo "╔══════════════════════════════════════════════════╗"
echo "║    ZanziPay — Full Source Code Generation        ║"
echo "╚══════════════════════════════════════════════════╝"

run_part() {
  local n=$1
  echo ""
  echo "▶ Running Part $n..."
  bash "$SCRIPTS/gen_files_part${n}.sh"
  echo "✓ Part $n complete"
}

for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21; do
  run_part $i
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  All source files generated successfully!        ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Next steps:                                     ║"
echo "║  1. cd /mnt/c/Users/dheer/.../zanzipay           ║"
echo "║  2. ~/go-install/go/bin/go mod tidy              ║"
echo "║  3. ~/go-install/go/bin/go build ./...           ║"
echo "║  4. ~/go-install/go/bin/go test ./...            ║"
echo "╚══════════════════════════════════════════════════╝"
