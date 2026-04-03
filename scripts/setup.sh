#!/usr/bin/env bash
# ZanziPay — Local Development Setup
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Check deps
command -v go >/dev/null 2>&1 || { warn "go not found. Install from https://go.dev"; exit 1; }
command -v docker >/dev/null 2>&1 || warn "docker not found — skipping DB setup"

log "Setting up ZanziPay development environment..."
log "Root: $ROOT"

# Copy .env if not exists
if [ ! -f .env ]; then
    cp .env.example .env
    log "Created .env from .env.example — update secrets!"
fi

# Go mod tidy
log "Running go mod tidy..."
go mod tidy

# Build all binaries
log "Building Go binaries..."
mkdir -p bin
go build -o bin/zanzipay-server  ./cmd/zanzipay-server/
go build -o bin/zanzipay-cli    ./cmd/zanzipay-cli/
go build -o bin/zanzipay-bench  ./cmd/zanzipay-bench/
log "Binaries: bin/zanzipay-{server,cli,bench}"

# Frontend deps
if command -v npm >/dev/null 2>&1 && [ -d frontend ]; then
    log "Installing frontend dependencies..."
    cd frontend && npm install --silent && cd ..
fi

# Run Go tests
log "Running test suite..."
go test ./... -count=1

# Docker stack (if available)
if command -v docker >/dev/null 2>&1; then
    log "Starting PostgreSQL via docker-compose..."
    docker compose up -d postgres 2>/dev/null || warn "docker compose failed — skipping"
    sleep 3
    log "Running migrations..."
    for f in schemas/migrations/*.sql; do
        log "  Applying $f..."
        docker compose exec -T postgres psql -U zanzipay -d zanzipay -f "/dev/stdin" < "$f" 2>/dev/null || warn "Migration $f failed (DB may not be ready)"
    done
fi

log "Setup complete!"
echo ""
echo "  Start server:    ./bin/zanzipay-server"
echo "  Start frontend:  cd frontend && npm run dev"
echo "  Run benchmarks:  ./bin/zanzipay-bench --duration=10s"
echo "  CLI help:        ./bin/zanzipay-cli --help"
