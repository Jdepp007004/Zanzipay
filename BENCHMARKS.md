# ZanziPay — Benchmark Report

**Date:** 2026-04-02  
**Machine:** WSL2 / Ubuntu 24.04 / Go 1.22  
**Config:** 50 concurrent workers · 8s per scenario · 1s warmup · In-memory backend

---

## Results

| Scenario | P50 (ms) | P95 (ms) | P99 (ms) | Throughput (req/s) | Total Ops | Error % |
|----------|----------|----------|----------|--------------------|-----------|---------|
| `simple_check` | **0.064** | **0.905** | **2.636** | **208,061** | 1,664,542 | 0.000% |
| `denied_check` | 0.088 | 1.240 | 4.185 | 145,285 | 1,162,334 | 0.000% |
| `nested_group_check` | 0.133 | 1.220 | 4.131 | 126,343 | 1,010,817 | 0.000% |
| `high_concurrency` | 0.130 | 1.125 | 3.465 | 137,688 | 1,101,593 | 0.000% |
| `compliance_check` | 0.141 | 1.192 | 3.346 | 138,484 | 1,108,115 | 0.000% |
| **Average** | **0.111** | **1.136** | **3.553** | **151,172** | **7,047,401** | **0.000%** |

---

## What Each Scenario Tests

| Scenario | What runs |
|----------|-----------|
| `simple_check` | ReBAC + Cedar Policy + Compliance (allow path — all pass) |
| `denied_check` | ReBAC DENY — unknown subject, short-circuit after ReBAC layer |
| `nested_group_check` | ReBAC indirect relationship (owner → account, 2-hop) |
| `high_concurrency` | Same as simple_check with 50 goroutines racing on 500-tuple subset |
| `compliance_check` | Full pipeline with rich PolicyContext (KYC, amount, time) |

---

## Key Takeaways

```
Peak throughput:       208,061 req/s
Lowest P50 latency:      0.064 ms  (< 100 microseconds)
Lowest P99 latency:      2.636 ms
Compliance overhead:    +0.077ms P50 over simple_check  (< 0.1ms!)
Error rate:              0.000%  across 7,047,401 decisions
```

---

## How to Reproduce

```bash
# Build the bench binary
export GOPATH=/tmp/gopath GOCACHE=/tmp/gocache
/home/dheeraj/go-install/go/bin/go build -o bin/zanzipay-bench ./cmd/zanzipay-bench/

# Run all 5 scenarios
./bin/zanzipay-bench \
  --duration=8s \
  --concurrency=50 \
  --warmup=1s \
  --output=bench/results

# View as table
python3 bench_print.py

# Via script
bash scripts/run-benchmarks.sh

# Or via master runner
bash run-all.sh --bench --duration=8s --concurrency=50
```

---

## Competitive Context

> **DISCLAIMER:** The ZanziPay benchmarks above test a local, in-memory deployment without network latency or a distributed database backend. The competitor numbers below are sourced from large-scale, production-grade distributed deployments. Direct comparisons to ZanziPay's in-memory single-node performance are inherently flawed and should be treated as indicative of engine efficiency, not equivalent scale.

**REAL BENCHMARK DATA (from official sources):**

**Google Zanzibar (2019 paper, USENIX ATC):**
- Median latency: ~3ms
- P95 latency: < 10ms
- Throughput: > 10 million checks/second
- Scale: 2+ trillion tuples
- Source: https://www.usenix.org/conference/atc19/presentation/pang

**SpiceDB (AuthZed, published benchmarks):**
- P95 latency: ~5.76ms at 1M QPS against 100B relationships
- Typical P95: sub-10ms for optimized workloads
- Cached simple check: 2-5ms range
- Fully consistent check: higher (10-50ms)
- Source: https://authzed.com/blog/performance-benchmarking

**OpenFGA (Auth0/Okta, 2024):**
- No officially published RPS numbers
- Claims "millisecond-level" check latency
- 2024 optimizations: up to 20x improvement, 98% P99 reduction for complex models
- Introduced BatchCheck API in 2024
- Source: https://openfga.dev, https://auth0.com (blog)

**AWS Cedar (Amazon, OOPSLA 2024 paper):**
- Policy evaluation: < 1ms for hundreds of policies (policy-only, no graph DB)
- 28.7x-35.2x faster than OpenFGA
- 42.8x-80.8x faster than Rego (OPA)
- Note: Cedar evaluates policies only, NOT relationship graphs
- Source: https://www.amazon.science/publications/cedar

---

## Raw JSON

Located at: `bench/results/zanzipay.json`

```json
[
  { "system": "ZanziPay", "scenario": "simple_check",        "p50_ms": 0.064, "p95_ms": 0.905, "p99_ms": 2.636, "throughput_rps": 208061, "operations": 1664542, "error_rate": 0 },
  { "system": "ZanziPay", "scenario": "denied_check",        "p50_ms": 0.088, "p95_ms": 1.240, "p99_ms": 4.185, "throughput_rps": 145285, "operations": 1162334, "error_rate": 0 },
  { "system": "ZanziPay", "scenario": "nested_group_check",  "p50_ms": 0.133, "p95_ms": 1.220, "p99_ms": 4.131, "throughput_rps": 126343, "operations": 1010817, "error_rate": 0 },
  { "system": "ZanziPay", "scenario": "high_concurrency",    "p50_ms": 0.130, "p95_ms": 1.125, "p99_ms": 3.465, "throughput_rps": 137688, "operations": 1101593, "error_rate": 0 },
  { "system": "ZanziPay", "scenario": "compliance_check",    "p50_ms": 0.141, "p95_ms": 1.192, "p99_ms": 3.346, "throughput_rps": 138484, "operations": 1108115, "error_rate": 0 }
]
```
