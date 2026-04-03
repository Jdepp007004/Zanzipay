# ZanziPay — Zanzibar-derived authorization for fintech

# Binary targets
.PHONY: all build run test bench-setup bench-run bench-analyze bench-ui clean lint setup

GOPATH_BIN := $(HOME)/go-install/go/bin
GO := $(GOPATH_BIN)/go
NODE_BIN := $(HOME)/node-install/bin
NPM := $(NODE_BIN)/npm
NODE := $(NODE_BIN)/node

all: build

# Build all binaries
build:
	$(GO) build -o bin/zanzipay-server ./cmd/zanzipay-server/
	$(GO) build -o bin/zanzipay-cli ./cmd/zanzipay-cli/
	$(GO) build -o bin/zanzipay-bench ./cmd/zanzipay-bench/

# Run the server
run: build
	./bin/zanzipay-server --config config.yaml

# Run all tests
test:
	$(GO) test ./... -v -race -count=1 -timeout 60s

# Download Go module dependencies
deps:
	$(GO) mod download
	$(GO) mod tidy

# Start competitor systems for benchmarking
bench-setup:
	docker compose -f docker-compose.bench.yml up -d
	sleep 10
	@echo "All competitor systems are running."

# Run benchmark suite
bench-run: build
	./bin/zanzipay-bench \
		--systems zanzipay,spicedb,openfga,cedar,keto \
		--scenarios all \
		--duration 30s \
		--concurrency 50 \
		--output bench/results/

# Analyze benchmark results
bench-analyze:
	cd bench/analysis && python3 analyze.py \
		--results-dir ../results/ \
		--output ../../frontend/src/data/results.json \
		--report ../results/report.html

# Start the benchmark dashboard
bench-ui:
	cd frontend && $(NPM) run dev

# Full benchmark pipeline
bench: bench-setup bench-run bench-analyze
	@echo "Benchmarks complete. Run 'make bench-ui' to view results."

# Full local development setup
setup:
	@echo "=== ZanziPay Development Setup ==="
	$(GO) mod download
	@echo "Setting up frontend..."
	cd frontend && $(NPM) install
	@echo "=== Setup complete! ==="
	@echo "Run: make run"
	@echo "Run: make bench-ui"

# Clean build artifacts
clean:
	rm -rf bin/ bench/results/*.json frontend/src/data/results.json
	docker compose -f docker-compose.bench.yml down -v

# Lint
lint:
	$(GO) vet ./...
	cd frontend && $(NPM) run lint

# Proto generation (requires protoc and buf)
proto:
	./scripts/generate-proto.sh
