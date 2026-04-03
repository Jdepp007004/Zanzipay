# Contributing to ZanziPay

Thank you for your interest in contributing.

## Getting Started

```bash
git clone https://github.com/<your-username>/zanzipay
cd zanzipay
cp config.yaml.example config.yaml
go mod download
```

## Development Workflow

```bash
# Run tests
go test ./...

# Run with race detector
go test -race ./...

# Static analysis
go vet ./...

# Build all binaries
go build -o bin/zanzipay-server ./cmd/zanzipay-server/
go build -o bin/zanzipay-bench  ./cmd/zanzipay-bench/
go build -o bin/zanzipay-cli    ./cmd/zanzipay-cli/

# Run benchmarks
./bin/zanzipay-bench --duration=10s --concurrency=50
```

## Pull Request Guidelines

1. **Tests required** — all new code must have corresponding tests
2. **`go vet` clean** — no vet warnings allowed
3. **No new external dependencies** without discussion — the project intentionally has minimal deps
4. **Honest benchmarks** — if adding benchmark scenarios, include the backend type (memory/postgres) in results
5. **One concern per PR** — keep changes focused

## Adding a New Engine Check

All authorization checks flow through `internal/orchestrator/orchestrator.go`. To add a new engine:

1. Implement the engine in `internal/<engine>/`
2. Add it to the `Orchestrator` struct
3. Launch it as a goroutine in `Authorize()` alongside the existing three
4. Merge its verdict in the AND-logic block

## Running with PostgreSQL (for storage tests)

```bash
docker compose up -d postgres
export ZANZIPAY_STORAGE_ENGINE=postgres
export ZANZIPAY_STORAGE_DSN="postgres://zanzipay:password@localhost:5432/zanzipay?sslmode=disable"
./bin/zanzipay-server
```

## License

By contributing, you agree your contributions will be licensed under [Apache 2.0](LICENSE).
