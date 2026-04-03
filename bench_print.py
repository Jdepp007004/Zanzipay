import json, os

path = "bench/results/zanzipay.json"
data = json.load(open(path))
print(f"{'System':<12} {'Scenario':<22} {'P50':>8} {'P95':>8} {'P99':>8} {'RPS':>10} {'Ops':>10}")
print("-"*90)
for r in data:
    print(f"{r['system']:<12} {r['scenario']:<22} {r['p50_ms']:>7.2f}ms {r['p95_ms']:>7.2f}ms {r['p99_ms']:>7.2f}ms {r['throughput_rps']:>10,} {r['operations']:>10,}")
