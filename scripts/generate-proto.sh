#!/usr/bin/env bash
# ZanziPay — gRPC Stub Generator
# Installs buf if missing, then generates Go stubs from api/proto
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUF_BIN="${HOME}/.local/bin/buf"
BUF_VERSION="1.32.0"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[proto]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }

# ── Install buf if not present ────────────────────────────────────────────────
if ! command -v buf >/dev/null 2>&1 && [ ! -f "$BUF_BIN" ]; then
    log "Installing buf v${BUF_VERSION}..."
    mkdir -p "${HOME}/.local/bin"
    BUF_OS="Linux"
    BUF_ARCH="x86_64"
    curl -fsSL \
        "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-${BUF_OS}-${BUF_ARCH}" \
        -o "$BUF_BIN"
    chmod +x "$BUF_BIN"
    log "buf installed at $BUF_BIN"
else
    log "buf already installed: $(buf --version 2>/dev/null || $BUF_BIN --version)"
fi

export PATH="${HOME}/.local/bin:$PATH"

# ── Create output directories ─────────────────────────────────────────────────
mkdir -p api/gen/go/v1

# ── Generate ──────────────────────────────────────────────────────────────────
log "Running buf generate..."
buf generate api/proto || buf generate

log "Go stubs generated → api/gen/go/"
ls -la api/gen/go/v1/ 2>/dev/null || warn "No files generated — check buf.gen.yaml"

log "Done. Add generated files to go.mod if needed:"
echo "  go get google.golang.org/protobuf"
echo "  go get google.golang.org/grpc"
