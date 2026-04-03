# ZanziPay — Step-by-Step Improvement Map to Production Grade

**Version:** 2.0  
**Last Updated:** 2026-04-03  
**Purpose:** This file is a precise instruction manual. An AI coding assistant should read it top-to-bottom and execute each step exactly as written. Every step includes: what file to change, what the code should do, how to test it, and what the expected output is.

---

## TABLE OF CONTENTS

1. [Current State Audit](#1-current-state-audit)
2. [Phase 1: Caveat System (ReBAC Layer)](#phase-1-caveat-system-rebac-layer)
3. [Phase 2: ABAC Condition Evaluator (Policy Layer)](#phase-2-abac-condition-evaluator-policy-layer)
4. [Phase 3: Temporal Policy Engine](#phase-3-temporal-policy-engine)
5. [Phase 4: Server Middleware](#phase-4-server-middleware)
6. [Phase 5: gRPC Handler Wiring](#phase-5-grpc-handler-wiring)
7. [Phase 6: Audit Reporter & Exporter](#phase-6-audit-reporter--exporter)
8. [Phase 7: Error Types & Codes](#phase-7-error-types--codes)
9. [Phase 8: Compliance Sub-Modules](#phase-8-compliance-sub-modules)
10. [Phase 9: Benchmark Accuracy](#phase-9-benchmark-accuracy)
11. [Phase 10: Final Verification](#phase-10-final-verification)
12. [Appendix A: Real Competitor Benchmark Data (sourced)](#appendix-a-real-competitor-benchmark-data)
13. [Appendix B: Architecture Reference](#appendix-b-architecture-reference)

---

## 1. Current State Audit

### Files That Exist and ARE Properly Implemented ✅

| File | Lines | What It Does |
|------|-------|--------------|
| `internal/rebac/engine.go` | 140 | Core ReBAC engine: Check, WriteTuples, DeleteTuples, ReadTuples, Watch, WriteSchema |
| `internal/rebac/check.go` | 207 | Recursive graph walk: union, intersection, exclusion, arrow, computed, userset expansion |
| `internal/rebac/schema.go` | 175 | Schema parser: definitions, relations, permissions, `+`/`&`/`-`/`->` operators |
| `internal/rebac/zookie.go` | ~80 | Zookie mint/decode with HMAC signing |
| `internal/rebac/types.go` | ~80 | CheckRequest, CheckResponse, ObjectRef, SubjectRef, CheckResult enum |
| `internal/compliance/engine.go` | 348 | Full 4-check pipeline: sanctions (Jaro-Winkler), KYC tiers, regulatory overrides, account freeze |
| `internal/orchestrator/orchestrator.go` | 209 | Fan-out to ReBAC+Policy+Compliance in parallel, AND-merge, HMAC decision token |
| `internal/audit/logger.go` | ~130 | Append-only audit log with query support |
| `internal/policy/engine.go` | 324 | Cedar parser, scope matching, basic condition evaluation |
| `internal/storage/memory/memory.go` | ~350 | Full in-memory storage implementing all interfaces |
| `internal/storage/postgres/postgres.go` | ~500 | Full PostgreSQL backend (needs live DB to test) |
| `internal/storage/storage.go` | ~145 | All storage interfaces |
| `internal/server/server.go` | 143 | REST /v1/check + /v1/health, gRPC stub (no handlers registered) |
| `pkg/errors/errors.go` | 19 | Basic sentinel errors |

### Files That EXIST But Are INCOMPLETE ⚠️

| File | Gap |
|------|-----|
| `internal/policy/engine.go` | `evalSingleCondition()` only supports `==` and literal `frozen == true`. Cannot do `>`, `<`, `!=`, `>=`, `<=`, `in`, `contains`. Cannot do `&&`/`||` compound conditions. |
| `internal/rebac/check.go` | `checkDirectRelation()` does NOT check caveats on matched tuples. If a tuple has a `CaveatName`, it should evaluate the caveat expression and return `CheckConditional` if context is missing. Currently ignores caveats entirely. |
| `internal/rebac/schema.go` | `ParseSchema()` skips `caveat` blocks entirely (line 58: `strings.HasPrefix(line, "caveat")` → `continue`). Needs to parse caveat definitions into the Schema struct. |
| `internal/server/server.go` | gRPC server has no service handlers registered. Only REST `/v1/check` and `/v1/health` work. |
| `pkg/errors/errors.go` | No gRPC status code mapping, no compliance-specific errors |

### Files That Are COMPLETELY MISSING ❌

| Expected File (per architecture.md) | What It Should Do |
|--------------------------------------|-------------------|
| `internal/rebac/caveat.go` | Caveat expression evaluator: evaluate `amount <= 10000`, `currency == "USD"`, etc. |
| `internal/rebac/caveat_test.go` | Tests for 6+ caveat scenarios |
| `internal/rebac/expand.go` | Expand API: build userset tree for debugging |
| `internal/rebac/namespace.go` | Namespace management (thin wrapper over schema) |
| `internal/policy/abac.go` | Full ABAC condition evaluator with all operators |
| `internal/policy/abac_test.go` | Tests for every operator |
| `internal/policy/temporal.go` | Time window, day-of-week, token expiry policies |
| `internal/policy/temporal_test.go` | Tests for temporal conditions |
| `internal/policy/cedar_eval.go` | Separate Cedar evaluator module (currently inlined in engine.go) |
| `internal/policy/cedar_parser.go` | Separate Cedar parser module (currently inlined in engine.go) |
| `internal/policy/store.go` | Separate policy store (currently inlined in engine.go) |
| `internal/server/middleware/auth.go` | API key authentication middleware |
| `internal/server/middleware/ratelimit.go` | Token-bucket rate limiter |
| `internal/server/middleware/logging.go` | Request/response structured logging |
| `internal/server/middleware/metrics.go` | Prometheus metrics middleware |
| `internal/server/interceptors/audit.go` | gRPC audit logging interceptor |
| `internal/server/interceptors/recovery.go` | Panic recovery interceptor (exists inline, needs extraction) |
| `internal/audit/reporter.go` | SOX/PCI compliance report generator |
| `internal/audit/reporter_test.go` | Reporter tests |
| `internal/audit/exporter.go` | JSON/CSV audit log exporter |
| `internal/audit/exporter_test.go` | Exporter tests |
| `internal/audit/decision.go` | Decision record types (currently in storage.go) |
| `internal/compliance/sanctions.go` | Separate sanctions screening module |
| `internal/compliance/kyc.go` | Separate KYC gate module |
| `internal/compliance/freeze.go` | Separate account freeze module |
| `internal/compliance/regulatory.go` | Separate regulatory override module |
| `internal/compliance/lists/loader.go` | Sanctions list loader |
| `internal/compliance/lists/matcher.go` | Fuzzy name matching (already in engine.go, needs extraction) |
| `internal/config/config.go` | Configuration struct with Viper loading |
| `pkg/client/client.go` | Go client SDK for ZanziPay |

---

## PHASE 1: Caveat System (ReBAC Layer)

### Step 1.1 — Create `internal/rebac/caveat.go`

**What this file does:** Evaluates conditions attached to relationship tuples. For example, a tuple `account:acme#viewer@user:alice with amount_limit({"max_amount": 10000})` means Alice can view, but only if the request's `amount` is ≤ 10000.

**Implementation requirements:**

```
Types to define:
  - CaveatDefinition { Name string, Parameters map[string]CaveatParamType, Expression string }
  - CaveatParamType = int enum: TypeInt, TypeString, TypeBool, TypeDouble
  - CaveatResult = int enum: CaveatSatisfied, CaveatNotSatisfied, CaveatMissingContext
  - CaveatEvaluator { definitions map[string]*CaveatDefinition }

Functions to implement:
  - NewCaveatEvaluator() *CaveatEvaluator
  - (ce *CaveatEvaluator) Register(def CaveatDefinition) error
  - (ce *CaveatEvaluator) Evaluate(caveatName string, tupleContext map[string]interface{}, requestContext map[string]interface{}) (CaveatResult, error)
  - (ce *CaveatEvaluator) MissingFields(caveatName string, ctx map[string]interface{}) []string

Internal expression evaluation:
  The Evaluate function must:
  1. Look up the caveat definition by name
  2. Merge tupleContext + requestContext (tuple context takes priority)  
  3. Check if all required parameters are present → if not, return CaveatMissingContext
  4. Parse the expression string and evaluate it:
     - Support operators: ==, !=, >, <, >=, <=
     - Support &&, ||
     - Type coerce: string "5000" → number 5000 when comparing to number
     - Return CaveatSatisfied (true) or CaveatNotSatisfied (false)

DO NOT use google/cel-go. Write a self-contained evaluator. The expression format is simple:
  "amount <= max_amount"
  "currency == \"USD\""
  "amount <= max_amount && currency == \"USD\""
```

**Test file:** `internal/rebac/caveat_test.go`

```
Test cases (minimum 6):
  1. Simple numeric: amount(5000) <= max_amount(10000) → Satisfied
  2. Simple numeric fail: amount(15000) <= max_amount(10000) → NotSatisfied
  3. String equality: currency("USD") == expected_currency("USD") → Satisfied
  4. Missing context: amount not provided → MissingContext
  5. Compound: amount <= max && currency == "USD" → Satisfied
  6. Bool: is_verified == true → Satisfied
```

### Step 1.2 — Modify `internal/rebac/schema.go`

**What to change:** The `ParseSchema` function currently skips `caveat` blocks. Change it to parse them.

```
Current behavior (line 58):
  if strings.HasPrefix(line, "caveat") { continue }

New behavior:
  if strings.HasPrefix(line, "caveat ") {
    // Parse: caveat amount_limit(max_amount int, currency string) {
    //            max_amount > request.amount && currency == request.currency
    //        }
    // Extract name, parameters with types, and the expression body
    // Store in Schema.Caveats map
  }

Add to Schema struct:
  Caveats map[string]*CaveatDefinition

The parser should:
  1. Extract caveat name from "caveat <name>(<params>) {"
  2. Parse params: "max_amount int, currency string" → map of name→type
  3. Read lines until "}" to get the expression body
  4. Store as CaveatDefinition in Schema.Caveats
```

### Step 1.3 — Modify `internal/rebac/check.go`

**What to change:** The `checkDirectRelation` function at line 148. When a matching tuple is found and it has a non-empty `CaveatName`, evaluate the caveat.

```
Current code (line 162-164):
  t, err := iter.Next()
  if err == nil && t != nil {
    return CheckAllowed, nil    // ← BUG: ignores caveats
  }

New code:
  t, err := iter.Next()
  if err == nil && t != nil {
    if t.CaveatName == "" {
      return CheckAllowed, nil   // No caveat, always allowed
    }
    // Evaluate caveat
    result := e.caveats.Evaluate(t.CaveatName, t.CaveatContext, req.CaveatContext)
    switch result {
    case CaveatSatisfied:
      return CheckAllowed, nil
    case CaveatMissingContext:
      return CheckConditional, nil
    case CaveatNotSatisfied:
      // This tuple doesn't match, continue to check other tuples
    }
  }

Also: Engine struct needs a `caveats *CaveatEvaluator` field.
Also: NewEngine needs to create a CaveatEvaluator and register caveats from the schema.
```

### Step 1.4 — Verify Phase 1

```bash
cd /mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay
go build ./internal/rebac/...
go vet ./internal/rebac/...
go test ./internal/rebac/... -v -count=1
# Expected: ALL PASS, including new caveat tests
```

---

## PHASE 2: ABAC Condition Evaluator (Policy Layer)

### Step 2.1 — Create `internal/policy/abac.go`

**What this file does:** Evaluates ABAC conditions from Cedar `when { ... }` blocks. This replaces the weak `evalSingleCondition` in `engine.go`.

```
Functions to implement:
  - EvalCondition(condition string, ctx map[string]interface{}) bool
    Master function that parses and evaluates a condition string.

  - evalCompare(left, op, right string, ctx map[string]interface{}) bool
    Evaluates: "context.amount > 5000"
    Supports: ==, !=, >, <, >=, <=
    Type-aware: automatically detects number vs string vs bool

  - evalContains(listExpr, element string, ctx map[string]interface{}) bool
    Evaluates: ["transfer","payout"].contains(action)

  - evalIn(element, listExpr string, ctx map[string]interface{}) bool
    Evaluates: context.day_of_week in ["Saturday","Sunday"]

  - evalLogical(condition string, ctx map[string]interface{}) bool
    Splits on "&&" and "||" (with correct precedence: && before ||)
    Handles "!" negation

  - resolveValue(expr string, ctx map[string]interface{}) interface{}
    Resolves "context.amount" → looks up ctx["amount"]
    Resolves "5000" → returns 5000 (number)
    Resolves "\"USD\"" → returns "USD" (string)
    Resolves "true"/"false" → returns bool

The resolver should strip prefixes: "context.", "principal.", "resource."
  so "context.kyc_status" resolves to ctx["kyc_status"]
```

**Test file:** `internal/policy/abac_test.go`

```
Test cases (minimum 10):
  1. Numeric >:  "context.amount > 5000" with amount=8000 → true
  2. Numeric >:  "context.amount > 5000" with amount=3000 → false
  3. Numeric <=: "context.amount <= 10000" with amount=10000 → true
  4. String ==:  "context.kyc_status == \"verified\"" with kyc_status="verified" → true
  5. String !=:  "context.kyc_status != \"verified\"" with kyc_status="pending" → true
  6. Bool:       "context.is_frozen == true" with is_frozen=true → true
  7. Compound &&: "context.amount > 1000 && context.kyc_status == \"verified\"" → true
  8. Compound ||: "context.is_admin == true || context.role == \"manager\"" → true
  9. List contains: "[\"transfer\",\"payout\"].contains(context.action)" with action="transfer" → true
  10. List in:    "context.day in [\"Monday\",\"Tuesday\"]" with day="Monday" → true
  11. Negation:   "!context.is_frozen" with is_frozen=false → true
```

### Step 2.2 — Modify `internal/policy/engine.go`

**What to change:** Replace `evalSingleCondition(cond string, ctx map[string]interface{}) bool` (lines 223-246) with a call to the new ABAC evaluator:

```
Old:
  func evalSingleCondition(cond string, ctx map[string]interface{}) bool {
    // Only handles == and "frozen == true"
  }

New:
  func evalSingleCondition(cond string, ctx map[string]interface{}) bool {
    return EvalCondition(cond, ctx)   // Delegates to abac.go
  }
```

### Step 2.3 — Verify Phase 2

```bash
go build ./internal/policy/...
go vet ./internal/policy/...
go test ./internal/policy/... -v -count=1
# Expected: ALL PASS including all new ABAC tests
```

---

## PHASE 3: Temporal Policy Engine

### Step 3.1 — Create `internal/policy/temporal.go`

**What this file does:** Evaluates time-based policy conditions.

```
Functions:
  - IsBusinessHours(t time.Time, timezone string) bool
    Returns true if t is between 09:00 and 17:00 on a weekday in the given timezone.

  - IsValidDayOfWeek(t time.Time, allowedDays []string) bool
    Returns true if t's day of week is in the allowedDays list.

  - IsTokenValid(expiresAt time.Time) bool
    Returns true if time.Now() is before expiresAt.

  - EnrichContextWithTime(ctx map[string]interface{}) map[string]interface{}
    Adds "hour", "minute", "day_of_week", "is_business_hours", "current_time" to the context map.
    This is called BEFORE condition evaluation so Cedar policies can reference time.

integration point:
  In orchestrator.go Authorize(), call EnrichContextWithTime on req.PolicyContext
  BEFORE passing to the policy engine.
```

**Test file:** `internal/policy/temporal_test.go`

```
Test cases (minimum 4):
  1. Business hours on Tuesday 10:00 → true
  2. Business hours on Saturday 10:00 → false  
  3. Token valid with future expiry → true
  4. Token expired → false
```

### Step 3.2 — Verify Phase 3

```bash
go test ./internal/policy/... -v -count=1
```

---

## PHASE 4: Server Middleware

### Step 4.1 — Create `internal/server/middleware/auth.go`

```
What it does:
  HTTP middleware that checks for "Authorization: Bearer <api-key>" header.
  Validates against a configured set of API keys (passed as []string).
  Returns 401 Unauthorized if missing/invalid.

Types:
  - AuthMiddleware { keys map[string]bool }
  - NewAuthMiddleware(keys []string) *AuthMiddleware
  - (am *AuthMiddleware) Wrap(next http.Handler) http.Handler
  - (am *AuthMiddleware) GRPCInterceptor() grpc.UnaryServerInterceptor
```

### Step 4.2 — Create `internal/server/middleware/ratelimit.go`

```
What it does:
  Token-bucket rate limiter per client (by IP or API key).
  No external dependencies (no Redis).

Types:
  - RateLimiter { mu sync.Mutex, buckets map[string]*bucket, rate float64, burst int }
  - bucket { tokens float64, lastRefill time.Time }
  - NewRateLimiter(ratePerSecond float64, burst int) *RateLimiter
  - (rl *RateLimiter) Allow(clientID string) bool
  - (rl *RateLimiter) Wrap(next http.Handler) http.Handler
  - (rl *RateLimiter) GRPCInterceptor() grpc.UnaryServerInterceptor
```

### Step 4.3 — Create `internal/server/middleware/metrics.go`

```
What it does:
  Prometheus metrics middleware. Tracks:
  - zanzipay_request_duration_seconds (histogram by method)
  - zanzipay_requests_total (counter by method, status)
  - zanzipay_active_requests (gauge)

Uses: github.com/prometheus/client_golang/prometheus

Functions:
  - NewMetricsMiddleware() *MetricsMiddleware
  - (mm *MetricsMiddleware) Wrap(next http.Handler) http.Handler
  - (mm *MetricsMiddleware) GRPCInterceptor() grpc.UnaryServerInterceptor
```

### Step 4.4 — Extract interceptors from server.go

Move `recoveryInterceptor` and `loggingInterceptor` from `server.go` into:
- `internal/server/interceptors/recovery.go`
- `internal/server/interceptors/audit.go` (rename loggingInterceptor to auditInterceptor, enhance to log full decision details)

### Step 4.5 — Verify Phase 4

```bash
go build ./internal/server/...
go vet ./internal/server/...
go test ./internal/server/... -v -count=1
```

---

## PHASE 5: gRPC Handler Wiring

### Step 5.1 — Modify `internal/server/server.go`

**What to change:** Register proper REST handlers for all 6 operations.

```
Current REST routes (2):
  /v1/check    → handleCheck (exists, works)
  /v1/health   → inline handler (exists, works)

Add these REST routes:
  /v1/tuples          POST → handleWriteTuples (call rebac.WriteTuples)
  /v1/tuples/delete   POST → handleDeleteTuples (call rebac.DeleteTuples)
  /v1/schema          POST → handleWriteSchema (call rebac.WriteSchema)
  /v1/schema          GET  → handleReadSchema  (call rebac.ReadSchema)
  /v1/lookup          POST → handleLookupResources
  /v1/policies        POST → handleDeployPolicies (call policy.DeployPolicies)

The Server struct needs additional fields:
  rebac  *rebac.Engine
  policy *policy.Engine
  audit  *audit.Logger
```

### Step 5.2 — Modify `cmd/zanzipay-server/main.go`

Wire up the new middleware and handlers to the server. The main function should:
1. Load config
2. Create storage backend
3. Create all engines
4. Create auth middleware (from config API keys)
5. Create rate limiter
6. Create metrics middleware
7. Create server with all engines injected
8. Start

### Step 5.3 — Verify Phase 5

```bash
go build ./cmd/zanzipay-server/
go build ./...
go vet ./...
```

---

## PHASE 6: Audit Reporter & Exporter

### Step 6.1 — Create `internal/audit/reporter.go`

```
Types:
  - ComplianceReport {
      TimeRange      [2]time.Time
      TotalDecisions int
      AllowCount     int
      DenyCount      int
      AllowRate      float64
      TopDeniedResources []ResourceCount
      TopDeniedSubjects  []SubjectCount
      ComplianceScore    float64
    }
  - ResourceCount { ResourceType, ResourceID string; Count int }
  - SubjectCount  { SubjectType, SubjectID string; Count int }

Functions:
  - GenerateReport(records []storage.DecisionRecord, from, to time.Time) *ComplianceReport
    Iterates records, counts allow/deny, finds top denied entities.
  
  - GenerateSOXReport(records []storage.DecisionRecord, from, to time.Time) *ComplianceReport
    Same as above but adds SOX-specific fields (audit trail completeness check).
```

### Step 6.2 — Create `internal/audit/exporter.go`

```
Functions:
  - ExportJSON(w io.Writer, records []storage.DecisionRecord) error
    Writes one JSON object per line (JSON Lines format).

  - ExportCSV(w io.Writer, records []storage.DecisionRecord) error
    Writes CSV with headers: timestamp, subject_type, subject_id, resource_type, 
    resource_id, action, allowed, verdict, decision_token, reasoning, eval_duration_ns
```

### Step 6.3 — Add tests

Create `internal/audit/reporter_test.go` and `internal/audit/exporter_test.go`.

### Step 6.4 — Verify Phase 6

```bash
go test ./internal/audit/... -v -count=1
```

---

## PHASE 7: Error Types & Codes

### Step 7.1 — Expand `pkg/errors/errors.go`

```
Add compliance-specific errors:
  ErrSanctionsMatch    = errors.New("sanctions list match")
  ErrKYCInsufficient   = errors.New("KYC tier insufficient")
  ErrAccountFrozen     = errors.New("account is frozen")
  ErrRegulatoryBlock   = errors.New("regulatory override active")
  ErrPolicyViolation   = errors.New("policy forbids action")
  ErrCaveatMissing     = errors.New("caveat context missing")
  ErrRateLimited       = errors.New("rate limit exceeded")

Add gRPC status mapping function:
  func ToGRPCStatus(err error) codes.Code {
    switch {
    case errors.Is(err, ErrNotFound): return codes.NotFound
    case errors.Is(err, ErrPermissionDenied): return codes.PermissionDenied
    case errors.Is(err, ErrUnauthenticated): return codes.Unauthenticated
    case errors.Is(err, ErrRateLimited): return codes.ResourceExhausted
    case errors.Is(err, ErrDeadlineExceeded): return codes.DeadlineExceeded
    default: return codes.Internal
    }
  }
```

---

## PHASE 8: Compliance Sub-Modules

### Step 8.1 — Extract from `internal/compliance/engine.go`

The compliance engine currently has all logic in one 348-line file. Extract into separate files:

```
internal/compliance/sanctions.go   — Move screenSanctions() + jaroWinkler() + jaroSim()
internal/compliance/kyc.go         — Move checkKYC() + KYCTier types + ActionKYCRequirements
internal/compliance/freeze.go      — Move checkFreeze() + FreezeResult
internal/compliance/regulatory.go  — Move checkRegulatory() + RegulatoryResult
internal/compliance/lists/loader.go   — Function to load sanctions lists from OFAC CSV format
internal/compliance/lists/matcher.go  — Move jaroWinkler/jaroSim here (reuse from sanctions.go)
```

Keep `engine.go` as the orchestrator that calls the sub-modules.

### Step 8.2 — Verify Phase 8

```bash
go test ./internal/compliance/... -v -count=1
# Existing tests must still pass — this is a refactor, not new logic
```

---

## PHASE 9: Benchmark Accuracy

### Step 9.1 — Fix the comparison table

**CRITICAL:** The current `BENCHMARKS.md` compares ZanziPay in-memory benchmarks with fabricated competitor numbers. This is dishonest and will get you rejected in any technical review.

Replace the competitor numbers with these REAL, source-cited numbers:

```
REAL BENCHMARK DATA (from official sources):

Google Zanzibar (2019 paper, USENIX ATC):
  - Median latency: ~3ms
  - P95 latency: < 10ms
  - Throughput: > 10 million checks/second
  - Scale: 2+ trillion tuples
  - Source: https://www.usenix.org/conference/atc19/presentation/pang

SpiceDB (AuthZed, published benchmarks):
  - P95 latency: ~5.76ms at 1M QPS against 100B relationships
  - Typical P95: sub-10ms for optimized workloads
  - Cached simple check: 2-5ms range
  - Fully consistent check: higher (10-50ms)
  - Source: https://authzed.com/blog/performance-benchmarking

OpenFGA (Auth0/Okta, 2024):
  - No officially published RPS numbers
  - Claims "millisecond-level" check latency
  - 2024 optimizations: up to 20x improvement, 98% P99 reduction for complex models
  - Introduced BatchCheck API in 2024
  - Source: https://openfga.dev, https://auth0.com (blog)

AWS Cedar (Amazon, OOPSLA 2024 paper):
  - Policy evaluation: < 1ms for hundreds of policies (policy-only, no graph DB)
  - 28.7x-35.2x faster than OpenFGA
  - 42.8x-80.8x faster than Rego (OPA)
  - Note: Cedar evaluates policies only, NOT relationship graphs
  - Source: https://www.amazon.science/publications/cedar

Ory Keto:
  - No officially published benchmarks
  - Targets sub-10ms for optimized setups
  - Community reports: varies widely (10ms to 500ms depending on setup)
  - Source: https://www.ory.sh/docs/keto
```

### Step 9.2 — Add disclaimers to ZanziPay benchmark

Update `BENCHMARKS.md` and `bench/results/` to include this mandatory caveat:

```
IMPORTANT: ZanziPay benchmarks use an in-memory storage backend with no network
round-trips. This measures the engine's computational overhead ONLY. Real-world
latency with PostgreSQL will be higher (add ~1-5ms for DB round-trip).

To estimate production latency:
  Production P50 ≈ Engine P50 + DB latency ≈ 0.064ms + 2ms ≈ ~2.1ms
  Production P95 ≈ Engine P95 + DB latency ≈ 0.905ms + 5ms ≈ ~5.9ms
```

### Step 9.3 — Update `BENCHMARKS.md`

Rewrite the comparison table with the real data from Step 9.1. The table should have columns:
- System | Measurement Type | P50 | P95 | P99 | Peak RPS | Source

Make clear which are in-memory and which are end-to-end with a database.

---

## PHASE 10: Final Verification

### Step 10.1 — Full build

```bash
cd /mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay
export GOPATH=/tmp/gopath GOCACHE=/tmp/gocache
go mod tidy
go build ./...
go vet ./...
go test ./... -v -count=1
```

ALL must pass with exit code 0.

### Step 10.2 — Run benchmarks

```bash
./bin/zanzipay-bench --duration=8s --concurrency=50 --warmup=1s --output=bench/results
```

### Step 10.3 — Build frontend

```bash
npm --prefix frontend install
npm --prefix frontend run build
```

### Step 10.4 — Verify file count

Count the files changed/created. The minimum new file count is:

```
New files (minimum 15):
  internal/rebac/caveat.go
  internal/rebac/caveat_test.go
  internal/policy/abac.go
  internal/policy/abac_test.go
  internal/policy/temporal.go
  internal/policy/temporal_test.go
  internal/server/middleware/auth.go
  internal/server/middleware/ratelimit.go
  internal/server/middleware/metrics.go
  internal/server/interceptors/recovery.go
  internal/server/interceptors/audit.go
  internal/audit/reporter.go
  internal/audit/reporter_test.go
  internal/audit/exporter.go
  internal/audit/exporter_test.go

Modified files (minimum 6):
  internal/rebac/check.go        (caveat evaluation wiring)
  internal/rebac/schema.go       (caveat parsing)
  internal/rebac/engine.go       (CaveatEvaluator field)
  internal/policy/engine.go      (use new ABAC evaluator)
  internal/server/server.go      (new REST routes + middleware)
  pkg/errors/errors.go           (new error types + gRPC mapping)
  BENCHMARKS.md                  (real competitor data)
```

---

## APPENDIX A: Real Competitor Benchmark Data

### Google Zanzibar (2019, production at Google)
| Metric | Value | Source |
|--------|-------|--------|
| Median check latency | ~3ms | USENIX ATC 2019 paper |
| P95 check latency | < 10ms | USENIX ATC 2019 paper |
| Peak throughput | > 10M checks/sec | USENIX ATC 2019 paper |
| Total relationships | > 2 trillion | USENIX ATC 2019 paper |
| Availability | 99.999%+ | USENIX ATC 2019 paper |
| Consistency trick | Zookies (quantized timestamps) | USENIX ATC 2019 paper |
| Latency optimization | Request hedging, geographic replication | USENIX ATC 2019 paper |
| "Safe" request P95 | ~10ms | Paper Figure 8 |
| "Recent" request P95 | ~60ms (requires leader round-trip) | Paper Figure 8 |

### SpiceDB (2024, AuthZed published)
| Metric | Value | Source |
|--------|-------|--------|
| P95 at 1M QPS | ~5.76ms | authzed.com benchmarking guide |
| Typical P95 (optimized) | sub-10ms | authzed.com |
| Cached simple check | 2-5ms | authzed.com |
| Fully consistent check | 10-50ms | authzed.com |
| Scale tested | 100B relationships | authzed.com |
| Caveats | Yes (Netflix-sponsored) | SpiceDB docs |
| Storage backends | PostgreSQL, CockroachDB, Spanner, MySQL | SpiceDB docs |

### OpenFGA (2024, Auth0/Okta)
| Metric | Value | Source |
|--------|-------|--------|
| Official RPS numbers | Not published | openfga.dev |
| Claimed latency | "millisecond-level" | openfga.dev |
| 2024 optimization | Up to 20x improvement | auth0.com blog |
| Complex model P99 reduction | Up to 98% | auth0.com blog |
| BatchCheck API | Introduced 2024 | openfga.dev |
| Storage backends | PostgreSQL, MySQL, DynamoDB | openfga.dev |

### AWS Cedar (2024, Amazon OOPSLA paper)
| Metric | Value | Source |
|--------|-------|--------|
| Evaluation latency | < 1ms for 100s of policies | Amazon Science |
| vs OpenFGA | 28.7x-35.2x faster | OOPSLA 2024 |
| vs Rego/OPA | 42.8x-80.8x faster | OOPSLA 2024 |
| Implementation | Rust | cedar-policy GitHub |
| Note | Policy-only (no graph DB) | Cedar docs |

### Ory Keto
| Metric | Value | Source |
|--------|-------|--------|
| Official benchmarks | Not published | ory.sh |
| Target latency | sub-10ms | Ory docs |
| Community reports | 10ms-500ms (varies widely) | GitHub issues |

### ZanziPay (this project)
| Metric | Value | Note |
|--------|-------|------|
| Engine P50 (in-memory) | 0.064ms | No DB, no network |
| Engine P95 (in-memory) | 0.905ms | No DB, no network |
| Engine P99 (in-memory) | 2.636ms | No DB, no network |
| Peak RPS (in-memory) | 208,061 | No DB, no network |
| Estimated production P50 | ~2.1ms | Engine + ~2ms DB latency |
| Estimated production P95 | ~5.9ms | Engine + ~5ms DB latency |
| **Honest comparison** | **Comparable to SpiceDB/Zanzibar** when including DB latency | Not faster than Google |

---

## APPENDIX B: Architecture Reference

```
Client Request (gRPC :50053 / REST :8090)
    │
    ▼
┌─────────────────────────────────────────┐
│         API Gateway Layer               │
│  Auth middleware → Rate limiter →        │
│  Metrics → Logging → Request Router     │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│       Decision Orchestrator             │
│  Parallel fan-out (3 goroutines)        │
│  • Each engine has 50ms timeout         │
│  • Global timeout: 100ms               │
│  • ANY deny = final DENY               │
└──┬──────────────┬──────────────┬────────┘
   │              │              │
   ▼              ▼              ▼
┌────────┐  ┌──────────┐  ┌───────────┐
│ ReBAC  │  │  Cedar   │  │Compliance │
│ Engine │  │  Policy  │  │ Engine    │
│        │  │  Engine  │  │           │
│ Graph  │  │ permit/  │  │ Sanctions │
│ walk   │  │ forbid   │  │ KYC gate  │
│ with   │  │ with     │  │ Freeze    │
│ caveat │  │ ABAC +   │  │ Regulatory│
│ eval   │  │ temporal │  │ override  │
└───┬────┘  └────┬─────┘  └─────┬─────┘
    │            │              │
    ▼            ▼              ▼
┌─────────────────────────────────────────┐
│          Storage Layer                  │
│  Memory (dev) │ PostgreSQL (prod)       │
│  MVCC tuples, changelog, audit log      │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  Immutable Audit Log (SOX / PCI-DSS)   │
│  Every decision recorded with:          │
│  • Full reasoning chain                 │
│  • Decision token (HMAC-signed)         │
│  • Engine sub-verdicts                  │
│  • Eval duration in nanoseconds         │
└─────────────────────────────────────────┘
```

---

## EXECUTION ORDER SUMMARY

```
Phase 1 → internal/rebac/caveat.go + schema.go + check.go (3 files)
Phase 2 → internal/policy/abac.go + engine.go (2 files)  
Phase 3 → internal/policy/temporal.go (1 file)
Phase 4 → internal/server/middleware/* (3 files)
Phase 5 → internal/server/server.go + cmd/zanzipay-server/main.go (2 files)
Phase 6 → internal/audit/reporter.go + exporter.go (2 files)
Phase 7 → pkg/errors/errors.go (1 file)
Phase 8 → internal/compliance/* refactor (4 files, no new logic)
Phase 9 → BENCHMARKS.md rewrite (1 file)
Phase 10 → go build + go test + benchmark run (verification)

Total: ~21 files touched, 10 phases
After EACH phase: run go build ./... && go vet ./... && go test ./...
```
