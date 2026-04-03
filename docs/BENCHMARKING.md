# Benchmarking Guide

## Running Benchmarks

```bash
# Quick run (30 seconds)
make bench

# Full benchmark suite
make bench-full

# With custom params
./bin/zanzipay-bench \
    --duration=30s \
    --concurrency=100 \
    --output=bench/results
```

## Scenarios

| Scenario | Description | Expected P95 |
|----------|-------------|--------------|
| `simple_check` | Direct owner check | < 3ms |
| `denied_check` | Non-existent subject | < 2ms |
| `deep_nested` | 5-hop chain (org→team→member→account) | < 8ms |
| `lookup_resources` | Bitmap reverse lookup | < 2ms |
| `mixed_workload` | 60% check / 30% write / 10% lookup | < 10ms |
| `compliance_check` | Full pipeline with KYC + OFAC | < 15ms |

## Reading Results

Results are written to `bench/results/zanzipay.json`:

```json
[
  {
    "system": "ZanziPay",
    "scenario": "simple_check",
    "p50_ms": 1.2,
    "p95_ms": 2.1,
    "p99_ms": 3.5,
    "throughput_rps": 52000
  }
]
```

## Comparing Against Other Systems

```bash
# Run all comparison benchmarks
make bench-compare

# View in dashboard
cd frontend && npm run dev
# Open http://localhost:5173
```

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 16 cores |
| RAM | 8 GB | 32 GB |
| Storage | SSD | NVMe SSD |
| Network | 1 Gbps | 10 Gbps |

## Interpreting P99

ZanziPay targets **P99 < 20ms** for the full compliance pipeline under:
- 100 concurrent workers
- 1 million tuples in storage
- Active OFAC screening
