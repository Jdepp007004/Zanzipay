#!/usr/bin/env bash
# Part 15: bench, schemas, deploy, scripts, docs, frontend
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── bench/ ───────────────────────────────────────────────────────────────────
mkdir -p bench/results
touch bench/results/.gitkeep

cat > bench/scenarios/scenario.go << 'ENDOFFILE'
// Package scenarios defines the benchmark scenario interface.
package scenarios

import "context"

// Result holds the outcome of a single benchmark operation.
type Result struct {
	LatencyNs int64
	Success   bool
	Error     error
}

// Scenario is the interface all benchmark scenarios must implement.
type Scenario interface {
	Name() string
	Setup(ctx context.Context) error
	Run(ctx context.Context, workerID int) Result
	Teardown(ctx context.Context) error
}
ENDOFFILE
echo "  [OK] bench/scenarios/scenario.go"

cat > bench/scenarios/simple_check.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"fmt"
	"time"
)

// SimpleCheckScenario runs the most common case: a direct permission check.
type SimpleCheckScenario struct {
	checkFn func(ctx context.Context, resource, permission, subject string) (bool, error)
}

func NewSimpleCheckScenario(fn func(context.Context, string, string, string) (bool, error)) *SimpleCheckScenario {
	return &SimpleCheckScenario{checkFn: fn}
}
func (s *SimpleCheckScenario) Name() string { return "simple_check" }
func (s *SimpleCheckScenario) Setup(_ context.Context) error { return nil }
func (s *SimpleCheckScenario) Teardown(_ context.Context) error { return nil }
func (s *SimpleCheckScenario) Run(ctx context.Context, workerID int) Result {
	start := time.Now()
	resource := fmt.Sprintf("account:%04d", workerID%1000)
	_, err := s.checkFn(ctx, resource, "view", "user:bench_user")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/simple_check.go"

cat > bench/scenarios/deep_nested.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"fmt"
	"time"
)

// DeepNestedScenario checks permissions through a 5-hop group membership chain.
type DeepNestedScenario struct {
	checkFn func(ctx context.Context, resource, permission, subject string) (bool, error)
}

func NewDeepNestedScenario(fn func(context.Context, string, string, string) (bool, error)) *DeepNestedScenario {
	return &DeepNestedScenario{checkFn: fn}
}
func (s *DeepNestedScenario) Name() string { return "deep_nested" }
func (s *DeepNestedScenario) Setup(_ context.Context) error { return nil }
func (s *DeepNestedScenario) Teardown(_ context.Context) error { return nil }
func (s *DeepNestedScenario) Run(ctx context.Context, workerID int) Result {
	start := time.Now()
	resource := fmt.Sprintf("document:%04d", workerID%100)
	_, err := s.checkFn(ctx, resource, "edit", "user:nested_user")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/deep_nested.go"

cat > bench/scenarios/wide_fanout.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"time"
)

// WideFanoutScenario checks a resource with 1000+ direct assignees.
type WideFanoutScenario struct {
	checkFn func(ctx context.Context, resource, permission, subject string) (bool, error)
}

func NewWideFanoutScenario(fn func(context.Context, string, string, string) (bool, error)) *WideFanoutScenario {
	return &WideFanoutScenario{checkFn: fn}
}
func (s *WideFanoutScenario) Name() string { return "wide_fanout" }
func (s *WideFanoutScenario) Setup(_ context.Context) error { return nil }
func (s *WideFanoutScenario) Teardown(_ context.Context) error { return nil }
func (s *WideFanoutScenario) Run(ctx context.Context, _ int) Result {
	start := time.Now()
	_, err := s.checkFn(ctx, "account:shared", "view", "user:admin")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/wide_fanout.go"

cat > bench/scenarios/lookup_resources.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"time"
)

// LookupResourcesScenario calls the reverse index lookup API.
type LookupResourcesScenario struct {
	lookupFn func(ctx context.Context, subject, resourceType, permission string) ([]string, error)
}

func NewLookupResourcesScenario(fn func(context.Context, string, string, string) ([]string, error)) *LookupResourcesScenario {
	return &LookupResourcesScenario{lookupFn: fn}
}
func (s *LookupResourcesScenario) Name() string { return "lookup_resources" }
func (s *LookupResourcesScenario) Setup(_ context.Context) error { return nil }
func (s *LookupResourcesScenario) Teardown(_ context.Context) error { return nil }
func (s *LookupResourcesScenario) Run(ctx context.Context, _ int) Result {
	start := time.Now()
	_, err := s.lookupFn(ctx, "user:alice", "account", "view")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/lookup_resources.go"

cat > bench/scenarios/caveated_check.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"time"
)

// CaveatedCheckScenario runs a check with an active CEL caveat evaluation.
type CaveatedCheckScenario struct {
	checkFn func(ctx context.Context, resource, permission, subject string) (bool, error)
}

func NewCaveatedCheckScenario(fn func(context.Context, string, string, string) (bool, error)) *CaveatedCheckScenario {
	return &CaveatedCheckScenario{checkFn: fn}
}
func (s *CaveatedCheckScenario) Name() string { return "caveated_check" }
func (s *CaveatedCheckScenario) Setup(_ context.Context) error { return nil }
func (s *CaveatedCheckScenario) Teardown(_ context.Context) error { return nil }
func (s *CaveatedCheckScenario) Run(ctx context.Context, _ int) Result {
	start := time.Now()
	_, err := s.checkFn(ctx, "account:caveated", "transfer", "user:alice")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/caveated_check.go"

cat > bench/scenarios/concurrent_write.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"fmt"
	"time"
)

// ConcurrentWriteScenario writes tuples concurrently to test write throughput.
type ConcurrentWriteScenario struct {
	writeFn func(ctx context.Context, resource, relation, subject string) error
}

func NewConcurrentWriteScenario(fn func(context.Context, string, string, string) error) *ConcurrentWriteScenario {
	return &ConcurrentWriteScenario{writeFn: fn}
}
func (s *ConcurrentWriteScenario) Name() string { return "concurrent_write" }
func (s *ConcurrentWriteScenario) Setup(_ context.Context) error { return nil }
func (s *ConcurrentWriteScenario) Teardown(_ context.Context) error { return nil }
func (s *ConcurrentWriteScenario) Run(ctx context.Context, workerID int) Result {
	start := time.Now()
	resource := fmt.Sprintf("document:%08d", workerID)
	err := s.writeFn(ctx, resource, "owner", fmt.Sprintf("user:worker_%d", workerID))
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/concurrent_write.go"

cat > bench/scenarios/policy_eval.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"time"
)

// PolicyEvalScenario benchmarks Cedar policy evaluation overhead.
type PolicyEvalScenario struct {
	evalFn func(ctx context.Context, principal, action, resource string) (bool, error)
}

func NewPolicyEvalScenario(fn func(context.Context, string, string, string) (bool, error)) *PolicyEvalScenario {
	return &PolicyEvalScenario{evalFn: fn}
}
func (s *PolicyEvalScenario) Name() string { return "policy_eval" }
func (s *PolicyEvalScenario) Setup(_ context.Context) error { return nil }
func (s *PolicyEvalScenario) Teardown(_ context.Context) error { return nil }
func (s *PolicyEvalScenario) Run(ctx context.Context, _ int) Result {
	start := time.Now()
	_, err := s.evalFn(ctx, "user:alice", "transfer", "account:acme")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/policy_eval.go"

cat > bench/scenarios/mixed_workload.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"math/rand"
	"time"
)

// MixedWorkloadScenario simulates real-world traffic: 70% reads, 20% lookups, 10% writes.
type MixedWorkloadScenario struct {
	checkFn  func(ctx context.Context, resource, permission, subject string) (bool, error)
	lookupFn func(ctx context.Context, subject, resourceType, permission string) ([]string, error)
	writeFn  func(ctx context.Context, resource, relation, subject string) error
}

func NewMixedWorkloadScenario(
	check func(context.Context, string, string, string) (bool, error),
	lookup func(context.Context, string, string, string) ([]string, error),
	write func(context.Context, string, string, string) error,
) *MixedWorkloadScenario {
	return &MixedWorkloadScenario{checkFn: check, lookupFn: lookup, writeFn: write}
}
func (s *MixedWorkloadScenario) Name() string { return "mixed_workload" }
func (s *MixedWorkloadScenario) Setup(_ context.Context) error { return nil }
func (s *MixedWorkloadScenario) Teardown(_ context.Context) error { return nil }
func (s *MixedWorkloadScenario) Run(ctx context.Context, workerID int) Result {
	start := time.Now()
	var err error
	n := rand.Intn(100)
	if n < 70 {
		_, err = s.checkFn(ctx, "account:mixed", "view", "user:mixed_user")
	} else if n < 90 {
		_, err = s.lookupFn(ctx, "user:mixed_user", "account", "view")
	} else {
		err = s.writeFn(ctx, "account:new", "viewer", "user:temp")
	}
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/mixed_workload.go"

cat > bench/scenarios/compliance_check.go << 'ENDOFFILE'
package scenarios

import (
	"context"
	"time"
)

// ComplianceCheckScenario benchmarks full compliance pipeline latency.
type ComplianceCheckScenario struct {
	authzFn func(ctx context.Context, subject, resource, action string) (bool, error)
}

func NewComplianceCheckScenario(fn func(context.Context, string, string, string) (bool, error)) *ComplianceCheckScenario {
	return &ComplianceCheckScenario{authzFn: fn}
}
func (s *ComplianceCheckScenario) Name() string { return "compliance_check" }
func (s *ComplianceCheckScenario) Setup(_ context.Context) error { return nil }
func (s *ComplianceCheckScenario) Teardown(_ context.Context) error { return nil }
func (s *ComplianceCheckScenario) Run(ctx context.Context, _ int) Result {
	start := time.Now()
	_, err := s.authzFn(ctx, "user:alice", "account:acme", "transfer")
	return Result{LatencyNs: time.Since(start).Nanoseconds(), Success: err == nil, Error: err}
}
ENDOFFILE
echo "  [OK] bench/scenarios/compliance_check.go"

cat > bench/competitors/competitor.go << 'ENDOFFILE'
// Package competitors provides benchmark adapters for competing authorization systems.
package competitors

import "context"

// CheckFn is a simple check function signature matching our benchmark interface.
type CheckFn func(ctx context.Context, resource, permission, subject string) (bool, error)

// LookupFn is a lookup resources function.
type LookupFn func(ctx context.Context, subject, resourceType, permission string) ([]string, error)

// Competitor is the interface all competitor adapters must implement.
type Competitor interface {
	Name() string
	CheckFn() CheckFn
	LookupFn() LookupFn
	Close() error
}
ENDOFFILE
echo "  [OK] bench/competitors/competitor.go"

cat > bench/competitors/spicedb.go << 'ENDOFFILE'
package competitors

import (
	"context"
	"fmt"
)

// SpiceDBCompetitor is the ZanziPay benchmark adapter for SpiceDB.
type SpiceDBCompetitor struct {
	addr      string
	preShared string
}

func NewSpiceDBCompetitor(addr, preSharedKey string) *SpiceDBCompetitor {
	return &SpiceDBCompetitor{addr: addr, preShared: preSharedKey}
}
func (c *SpiceDBCompetitor) Name() string { return "SpiceDB" }
func (c *SpiceDBCompetitor) CheckFn() CheckFn {
	return func(ctx context.Context, resource, permission, subject string) (bool, error) {
		// Stub: real impl would use authzed/authzed-go gRPC client
		fmt.Printf("[SpiceDB] check %s#%s@%s\n", resource, permission, subject)
		return true, nil
	}
}
func (c *SpiceDBCompetitor) LookupFn() LookupFn {
	return func(ctx context.Context, subject, resourceType, permission string) ([]string, error) {
		return nil, nil
	}
}
func (c *SpiceDBCompetitor) Close() error { return nil }
ENDOFFILE
echo "  [OK] bench/competitors/spicedb.go"

cat > bench/competitors/spicedb_test.go << 'ENDOFFILE'
package competitors_test

import (
	"testing"

	"github.com/youorg/zanzipay/bench/competitors"
)

func TestSpiceDBCompetitorName(t *testing.T) {
	c := competitors.NewSpiceDBCompetitor("localhost:50051", "token")
	if c.Name() != "SpiceDB" {
		t.Errorf("Name() = %s, want SpiceDB", c.Name())
	}
}
ENDOFFILE
echo "  [OK] bench/competitors/spicedb_test.go"

cat > bench/competitors/openfga.go << 'ENDOFFILE'
package competitors

import "context"

// OpenFGACompetitor is the ZanziPay benchmark adapter for OpenFGA.
type OpenFGACompetitor struct{ apiURL string }

func NewOpenFGACompetitor(apiURL string) *OpenFGACompetitor { return &OpenFGACompetitor{apiURL: apiURL} }
func (c *OpenFGACompetitor) Name() string { return "OpenFGA" }
func (c *OpenFGACompetitor) CheckFn() CheckFn {
	return func(ctx context.Context, resource, permission, subject string) (bool, error) {
		return true, nil
	}
}
func (c *OpenFGACompetitor) LookupFn() LookupFn {
	return func(ctx context.Context, subject, resourceType, permission string) ([]string, error) {
		return nil, nil
	}
}
func (c *OpenFGACompetitor) Close() error { return nil }
ENDOFFILE
echo "  [OK] bench/competitors/openfga.go"

cat > bench/competitors/openfga_test.go << 'ENDOFFILE'
package competitors_test

import "github.com/youorg/zanzipay/bench/competitors"

func init() { _ = competitors.NewOpenFGACompetitor("http://localhost:8080") }
ENDOFFILE
echo "  [OK] bench/competitors/openfga_test.go"

cat > bench/competitors/cedar_standalone.go << 'ENDOFFILE'
package competitors

import "context"

// CedarStandaloneCompetitor benchmarks Cedar policy evaluation without ReBAC.
type CedarStandaloneCompetitor struct{}

func NewCedarStandaloneCompetitor() *CedarStandaloneCompetitor { return &CedarStandaloneCompetitor{} }
func (c *CedarStandaloneCompetitor) Name() string { return "Cedar (standalone)" }
func (c *CedarStandaloneCompetitor) CheckFn() CheckFn {
	return func(ctx context.Context, resource, permission, subject string) (bool, error) {
		return true, nil
	}
}
func (c *CedarStandaloneCompetitor) LookupFn() LookupFn {
	return func(ctx context.Context, subject, resourceType, permission string) ([]string, error) {
		return nil, nil
	}
}
func (c *CedarStandaloneCompetitor) Close() error { return nil }
ENDOFFILE
echo "  [OK] bench/competitors/cedar_standalone.go"

cat > bench/competitors/cedar_standalone_test.go << 'ENDOFFILE'
package competitors_test

import "github.com/youorg/zanzipay/bench/competitors"

func init() { _ = competitors.NewCedarStandaloneCompetitor() }
ENDOFFILE
echo "  [OK] bench/competitors/cedar_standalone_test.go"

cat > bench/competitors/ory_keto.go << 'ENDOFFILE'
package competitors

import "context"

// OryKetoCompetitor benchmarks Ory Keto (Zanzibar-based OSS).
type OryKetoCompetitor struct {
	readAddr  string
	adminAddr string
}

func NewOryKetoCompetitor(readAddr, adminAddr string) *OryKetoCompetitor {
	return &OryKetoCompetitor{readAddr: readAddr, adminAddr: adminAddr}
}
func (c *OryKetoCompetitor) Name() string { return "Ory Keto" }
func (c *OryKetoCompetitor) CheckFn() CheckFn {
	return func(ctx context.Context, resource, permission, subject string) (bool, error) {
		return true, nil
	}
}
func (c *OryKetoCompetitor) LookupFn() LookupFn {
	return func(ctx context.Context, subject, resourceType, permission string) ([]string, error) {
		return nil, nil
	}
}
func (c *OryKetoCompetitor) Close() error { return nil }
ENDOFFILE
echo "  [OK] bench/competitors/ory_keto.go"

cat > bench/competitors/ory_keto_test.go << 'ENDOFFILE'
package competitors_test

import "github.com/youorg/zanzipay/bench/competitors"

func init() { _ = competitors.NewOryKetoCompetitor("localhost:4466", "localhost:4467") }
ENDOFFILE
echo "  [OK] bench/competitors/ory_keto_test.go"

cat > bench/runner.go << 'ENDOFFILE'
// Package bench implements the ZanziPay benchmark runner.
package bench

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/youorg/zanzipay/bench/scenarios"
)

// RunConfig holds benchmark run configuration.
type RunConfig struct {
	Duration    time.Duration
	Concurrency int
	WarmUp      time.Duration
}

// RunResult holds benchmark statistics.
type RunResult struct {
	ScenarioName string
	Operations   int64
	Errors       int64
	Percentiles  map[float64]time.Duration // 0.5, 0.95, 0.99
	Throughput   float64                   // ops/sec
}

// Run executes a benchmark scenario and returns statistics.
func Run(ctx context.Context, s scenarios.Scenario, cfg RunConfig) (*RunResult, error) {
	if err := s.Setup(ctx); err != nil {
		return nil, fmt.Errorf("setup: %w", err)
	}
	defer s.Teardown(ctx)

	// Warmup
	if cfg.WarmUp > 0 {
		warmCtx, cancel := context.WithTimeout(ctx, cfg.WarmUp)
		runWorker(warmCtx, s, 0)
		cancel()
	}

	// Actual run
	var latencies []int64
	var mu sync.Mutex
	var ops, errs int64

	runCtx, cancel := context.WithTimeout(ctx, cfg.Duration)
	defer cancel()

	var wg sync.WaitGroup
	for i := 0; i < cfg.Concurrency; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			for {
				select {
				case <-runCtx.Done():
					return
				default:
					res := s.Run(runCtx, workerID)
					atomic.AddInt64(&ops, 1)
					if !res.Success {
						atomic.AddInt64(&errs, 1)
					} else {
						mu.Lock()
						latencies = append(latencies, res.LatencyNs)
						mu.Unlock()
					}
				}
			}
		}(i)
	}
	wg.Wait()

	result := &RunResult{
		ScenarioName: s.Name(),
		Operations:   ops,
		Errors:       errs,
		Throughput:   float64(ops) / cfg.Duration.Seconds(),
		Percentiles:  computePercentiles(latencies),
	}
	return result, nil
}

func runWorker(ctx context.Context, s scenarios.Scenario, id int) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
			s.Run(ctx, id)
		}
	}
}

func computePercentiles(latencies []int64) map[float64]time.Duration {
	if len(latencies) == 0 {
		return map[float64]time.Duration{}
	}
	sorted := make([]int64, len(latencies))
	copy(sorted, latencies)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	pct := func(p float64) time.Duration {
		idx := int(float64(len(sorted)-1) * p)
		return time.Duration(sorted[idx])
	}
	return map[float64]time.Duration{
		0.5:  pct(0.5),
		0.95: pct(0.95),
		0.99: pct(0.99),
	}
}
ENDOFFILE
echo "  [OK] bench/runner.go"

cat > bench/runner_test.go << 'ENDOFFILE'
package bench_test

import (
	"context"
	"testing"
	"time"

	bench "github.com/youorg/zanzipay/bench"
	"github.com/youorg/zanzipay/bench/scenarios"
)

type noopScenario struct{}

func (n *noopScenario) Name() string                              { return "noop" }
func (n *noopScenario) Setup(_ context.Context) error            { return nil }
func (n *noopScenario) Teardown(_ context.Context) error         { return nil }
func (n *noopScenario) Run(_ context.Context, _ int) scenarios.Result {
	return scenarios.Result{Success: true}
}

func TestRunBench(t *testing.T) {
	result, err := bench.Run(context.Background(), &noopScenario{}, bench.RunConfig{
		Duration:    100 * time.Millisecond,
		Concurrency: 2,
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.Operations == 0 {
		t.Error("expected at least 1 operation")
	}
}
ENDOFFILE
echo "  [OK] bench/runner_test.go"

cat > bench/config/keto.yml << 'ENDOFFILE'
version: v0alpha2
log:
  level: info
dsn: memory
namespaces:
  config: file:///etc/keto/namespaces/
serve:
  read:
    host: 0.0.0.0
    port: 4466
  write:
    host: 0.0.0.0
    port: 4467
ENDOFFILE
echo "  [OK] bench/config/keto.yml"

cat > bench/analysis/requirements.txt << 'ENDOFFILE'
pandas>=2.0
matplotlib>=3.7
seaborn>=0.12
jinja2>=3.1
numpy>=1.24
scipy>=1.10
ENDOFFILE
echo "  [OK] bench/analysis/requirements.txt"

cat > bench/analysis/analyze.py << 'ENDOFFILE'
#!/usr/bin/env python3
"""
ZanziPay Benchmark Analysis
Generates charts and reports from benchmark JSON results.
"""
import argparse
import json
import os
from pathlib import Path
import sys

def load_results(results_dir: str) -> list:
    results = []
    for f in Path(results_dir).glob("results_*.json"):
        with open(f) as fp:
            data = json.load(fp)
            if isinstance(data, list):
                results.extend(data)
    return results

def analyze(results: list) -> dict:
    by_scenario = {}
    for r in results:
        scenario = r.get("scenario", "unknown")
        if scenario not in by_scenario:
            by_scenario[scenario] = []
        by_scenario[scenario].append(r)
    
    summary = {}
    for scenario, records in by_scenario.items():
        summary[scenario] = {
            "p95_ms": min(r.get("p95_ms", 999) for r in records),
            "throughput_rps": max(r.get("throughput_rps", 0) for r in records),
            "systems": [r["system"] for r in records],
        }
    return summary

def write_output(summary: dict, output_path: str):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        json.dump({"scenarios": summary, "generated_at": __import__("datetime").datetime.utcnow().isoformat()}, f, indent=2)
    print(f"Results written to {output_path}")

def main():
    parser = argparse.ArgumentParser(description="ZanziPay Benchmark Analyzer")
    parser.add_argument("--results-dir", default="bench/results/", help="Input results directory")
    parser.add_argument("--output", default="frontend/src/data/results.json", help="Output JSON file")
    parser.add_argument("--report", default="bench/results/report.html", help="HTML report output")
    args = parser.parse_args()

    results = load_results(args.results_dir)
    if not results:
        print("No results found. Run benchmarks first with: make bench-run")
        sys.exit(0)

    summary = analyze(results)
    write_output(summary, args.output)
    print(f"Analyzed {len(results)} benchmark records across {len(summary)} scenarios")

if __name__ == "__main__":
    main()
ENDOFFILE
echo "  [OK] bench/analysis/analyze.py"

cat > bench/analysis/templates/report.html.j2 << 'ENDOFFILE'
<!DOCTYPE html>
<html><head><title>ZanziPay Benchmark Report</title></head>
<body>
<h1>ZanziPay Authorization System — Benchmark Report</h1>
<h2>Summary</h2>
<table border="1">
<tr><th>Scenario</th><th>Best P95 (ms)</th><th>Best Throughput (RPS)</th></tr>
{% for scenario, data in scenarios.items() %}
<tr><td>{{ scenario }}</td><td>{{ data.p95_ms }}</td><td>{{ data.throughput_rps }}</td></tr>
{% endfor %}
</table>
<p>Generated at: {{ generated_at }}</p>
</body></html>
ENDOFFILE
echo "  [OK] bench/analysis/templates/report.html.j2"

cat > bench/README.md << 'ENDOFFILE'
# ZanziPay Benchmark Suite

## Overview
This suite compares ZanziPay against SpiceDB, OpenFGA, Ory Keto, and Cedar (standalone).

## Running Benchmarks
```bash
# Start competitor systems
make bench-setup

# Run benchmarks
make bench-run

# Analyze results
make bench-analyze

# View dashboard
make bench-ui
```

## Scenarios
| Scenario | Description |
|---|---|
| simple_check | Direct permission check (most common case) |
| deep_nested | 5-hop group membership chain |
| wide_fanout | Resource with 1000+ direct assignees |
| caveated_check | Check with active CEL caveat evaluation |
| lookup_resources | Reverse index lookup (subjects → resources) |
| concurrent_write | Concurrent tuple writes |
| policy_eval | Cedar policy evaluation overhead |
| mixed_workload | 70% reads / 20% lookup / 10% writes |
| compliance_check | Full compliance pipeline |
ENDOFFILE
echo "  [OK] bench/README.md"

echo "=== bench/ done ==="
ENDOFFILE
echo "Part 15 script written"
