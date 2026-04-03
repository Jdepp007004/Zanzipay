#!/usr/bin/env bash
# Part 18: docs + frontend package.json + types fix
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── docs/ ────────────────────────────────────────────────────────────────────
cat > docs/ARCHITECTURE.md << 'ENDOFFILE'
# ZanziPay Architecture

## System Overview

ZanziPay is a hybrid authorization system that combines three paradigms:

1. **ReBAC** (Relationship-Based Access Control) — Google Zanzibar-style relationship graph
2. **ABAC/Policy** (Attribute-Based Access Control) — AWS Cedar policy evaluation
3. **Compliance** — Sanctions screening, KYC gates, regulatory holds

### Authorization Decision Pipeline

```
─────────────────────────────────────────────────────────────────────
 Client Request  →  gRPC/REST Server  →  Orchestrator
                                           │
                         ┌─────────────────┼─────────────────┐
                         │                 │                 │
                    ┌────▼────┐     ┌──────▼──────┐   ┌──────▼──────┐
                    │  ReBAC  │     │   Policy    │   │ Compliance  │
                    │ Engine  │     │   Engine    │   │   Engine    │
                    │         │     │ (Cedar/ABAC)│   │(Sanctions   │
                    │  Graph  │     │             │   │ KYC/Freeze) │
                    │  Walk   │     │             │   │             │
                    └────┬────┘     └──────┬──────┘   └──────┬──────┘
                         │                 │                 │
                         └─────────────────┴─────────────────┘
                                           │
                                    ┌──────▼──────┐
                                    │    Merge    │
                                    │  Verdicts   │
                                    │ (strict AND)│
                                    └──────┬──────┘
                                           │
                         ┌─────────────────┴────────────────┐
                         │                                   │
                    ┌────▼────┐                       ┌──────▼──────┐
                    │  Audit  │                       │  Decision   │
                    │  Log    │                       │   Token     │
                    └─────────┘                       └─────────────┘
```

## Engine Details

### ReBAC Engine
- Implements the Zanzibar check algorithm: recursive userset walk
- Supports `union`, `intersection`, `exclusion` set operations
- `caveat` expressions evaluated lazily via CEL
- Consistency via zookie tokens (HMAC-signed revision snapshots)
- Materialized permission index using Roaring Bitmaps for sub-ms lookup

### Policy Engine
- Cedar-compatible policy language (permit/forbid, when/unless)
- Temporal conditions (business hours, expiry dates)
- ABAC attribute checks (KYC status, transaction limits)
- Static analysis for satisfiability and conflict detection

### Compliance Engine
- OFAC/EU/UN sanctions screening (Jaro-Winkler fuzzy matching)
- KYC tier enforcement (Tier 1/2/3 based on action risk)
- Account freeze enforcement (admin or court-ordered)
- Regulatory override support (court orders, AML holds)
- **Compliance denials are ABSOLUTE — cannot be overridden**

### Audit Stream
- Append-only audit log (PostgreSQL immutability triggers)
- Every authorization decision is logged with full context
- SOX/PCI-DSS report generation
- 7-year retention (2555 days) enforced by policy

## Consistency Model

| Mode | How It Works | Latency Impact |
|---|---|---|
| `minimize_latency` | Use current in-memory snapshot | ~0ms overhead |
| `at_least_as_fresh` | Ensure snapshot ≥ client zookie rev | ~1-5ms |
| `fully_consistent` | Force read-from-leader | ~5-20ms |
ENDOFFILE
echo "  [OK] docs/ARCHITECTURE.md"

cat > docs/SCHEMA_LANGUAGE.md << 'ENDOFFILE'
# ZanziPay Schema Language

## Overview

ZanziPay uses a custom schema language (`.zp` files) derived from SpiceDB's schema language
and extended with a fintech-focused caveat system.

## Syntax

```
// Define a caveat (CEL expression)
caveat name(param: type) {
    expression
}

// Define a resource type
definition type_name {
    relation relation_name: allowed_type | allowed_type#relation
    permission perm_name = userset_expression
}
```

## Userset Operations

| Operator | Meaning |
|---|---|
| `+` | Union — ALLOW if any child allows |
| `&` | Intersection — ALLOW only if all children allow |
| `-` | Exclusion — ALLOW if left allows and right denies |
| `->` | Arrow — follow relation to related object and check permission |
| `with caveat` | Conditional — ALLOW only if caveat expression is true |

## Example

```
definition account {
    relation owner: user
    relation viewer: user
    relation org: organization

    permission manage = owner
    permission view   = owner + viewer + org->admin
    permission transfer = owner with kyc_verified with daily_limit
}
```
ENDOFFILE
echo "  [OK] docs/SCHEMA_LANGUAGE.md"

cat > docs/CEDAR_POLICIES.md << 'ENDOFFILE'
# Cedar Policies in ZanziPay

## Overview

ZanziPay uses Cedar-compatible policy syntax for ABAC rules that complement the
ReBAC relationship graph.

## Basic Structure

```cedar
// Permit statement
permit(
    principal [in EntityType::"id"],
    action [== Action::"verb" | in [...]],
    resource [is ResourceType]
)
[when { condition }]
[unless { condition }];

// Forbid statement (wins over permit)
forbid(
    principal,
    action,
    resource
)
when { condition };
```

## Decision Algorithm

1. Collect all matching permit and forbid policies
2. **If any forbid matches → DENY (regardless of permits)**
3. If at least one permit matches → ALLOW
4. Default → DENY

## Fintech-Specific Patterns

```cedar
// Require KYC for financial actions
forbid(principal, action, resource)
when {
    ["transfer", "payout"].contains(action) &&
    context.kyc_status != "verified"
};

// Block frozen accounts
forbid(principal, action, resource is Account)
when { resource.is_frozen };

// Business hours restriction for large transactions
forbid(principal, action == Action::"transfer", resource)
when { context.amount > 10000 && !context.is_business_hours };
```
ENDOFFILE
echo "  [OK] docs/CEDAR_POLICIES.md"

cat > docs/BENCHMARKING.md << 'ENDOFFILE'
# Benchmarking ZanziPay

## Setup

```bash
# 1. Start competitor systems
make bench-setup

# 2. Run benchmarks  
make bench-run

# 3. Analyze results
make bench-analyze

# 4. View dashboard
make bench-ui
```

## Scenarios

| Scenario | Tuples | Depth | Description |
|---|---|---|---|
| simple_check | 100K | 1 | Direct permission check |
| deep_nested | 10K | 5 | 5-hop group membership chain |
| wide_fanout | 1K | 1 | 1000+ direct assignees |
| caveated_check | 50K | 2 | CEL caveat evaluation |
| lookup_resources | 50K | 1 | Reverse bitmap lookup |
| concurrent_write | N/A | N/A | Write throughput at 50 workers |
| mixed_workload | 100K | 2 | 70% read / 20% lookup / 10% write |
| compliance_check | 50K | 2 | Full compliance pipeline |

## Expected Results (Reference Hardware: 8-core, 32GB RAM)

| Scenario | ZanziPay P95 | SpiceDB P95 | OpenFGA P95 |
|---|---|---|---|
| simple_check | ~2ms | ~3ms | ~4ms |
| deep_nested | ~4ms | ~12ms | ~15ms |
| lookup_resources | ~1ms | ~50ms | ~80ms |
| mixed_workload | ~8ms | ~15ms | ~20ms |
ENDOFFILE
echo "  [OK] docs/BENCHMARKING.md"

cat > docs/COMPLIANCE.md << 'ENDOFFILE'
# Compliance Guide

## Overview

ZanziPay's compliance engine implements four layers of financial regulation enforcement:

1. **Sanctions Screening** — OFAC/EU/UN list matching
2. **KYC Gating** — Tier 1/2/3 verification requirements
3. **Account Freezes** — Admin and court-ordered freezes
4. **Regulatory Overrides** — Court orders, AML holds (compliance veto = absolute deny)

## Sanctions Screening

Uses Jaro-Winkler fuzzy matching (threshold: 0.85) against:
- OFAC SDN List
- EU Consolidated Sanctions List
- UN Security Council List

Matching is performed on all subject names in the request.

## KYC Tiers

| Tier | Actions Permitted |
|---|---|
| Tier 1 | View account, read balance |
| Tier 2 | Initiate transfers, process refunds, payouts |
| Tier 3 | Large transfers (>$50K), regulatory reports |

## Immutable Audit Log

All decisions are appended to a PostgreSQL table protected by DDL triggers:
- `BEFORE UPDATE` → raises exception
- `BEFORE DELETE` → raises exception

The audit log is replicated and retained for 7 years (SOX compliance).
ENDOFFILE
echo "  [OK] docs/COMPLIANCE.md"

cat > docs/MIGRATION.md << 'ENDOFFILE'
# Migration Guide

## Migrating from SpiceDB

1. Export your schema from SpiceDB (`.zed` format)
2. Convert to ZanziPay schema (`.zp` format) — syntax is largely compatible
3. Export all relationship tuples as JSON
4. Import tuples using `zanzipay-cli tuple write`
5. (Optional) Import Cedar policies alongside for ABAC rules

## Migrating from OpenFGA

1. Export OpenFGA authorization model
2. Map concepts:
   - OpenFGA `type` → ZanziPay `definition`
   - OpenFGA `relation` → ZanziPay `relation`
   - OpenFGA `union` → ZanziPay `+`
   - OpenFGA `intersection` → ZanziPay `&`
3. Migrate tuples using the OpenFGA Tuples API export

## Migrating from AWS Cedar (standalone)

1. Import your Cedar policies directly (syntax is compatible)
2. Add a ZanziPay schema for relationship-based access
3. Combine both layers for hybrid authorization
ENDOFFILE
echo "  [OK] docs/MIGRATION.md"

# ─── pkg/types — add ParseTupleString for CLI ─────────────────────────────────
cat > pkg/types/parse.go << 'ENDOFFILE'
package types

import (
	"fmt"
	"strings"
)

// ParseTupleString parses "resource_type:id#relation@subject_type:id[#relation]"
func ParseTupleString(s string) (Tuple, error) {
	hashIdx := strings.Index(s, "#")
	if hashIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '#'", s)
	}
	resourceStr := s[:hashIdx]
	rest := s[hashIdx+1:]

	resource, err := parseObjectStr(resourceStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid resource: %w", err)
	}

	atIdx := strings.LastIndex(rest, "@")
	if atIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '@'", s)
	}
	relation := rest[:atIdx]
	subjectStr := rest[atIdx+1:]

	subject, err := parseSubjectStr(subjectStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid subject: %w", err)
	}

	return Tuple{
		ResourceType:    resource[0],
		ResourceID:      resource[1],
		Relation:        relation,
		SubjectType:     subject[0],
		SubjectID:       subject[1],
		SubjectRelation: subject[2],
	}, nil
}

func parseObjectStr(s string) ([2]string, error) {
	parts := strings.SplitN(s, ":", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return [2]string{}, fmt.Errorf("expected type:id, got %q", s)
	}
	return [2]string{parts[0], parts[1]}, nil
}

func parseSubjectStr(s string) ([3]string, error) {
	hashIdx := strings.LastIndex(s, "#")
	var rel string
	if hashIdx != -1 {
		rel = s[hashIdx+1:]
		s = s[:hashIdx]
	}
	obj, err := parseObjectStr(s)
	if err != nil {
		return [3]string{}, err
	}
	return [3]string{obj[0], obj[1], rel}, nil
}
ENDOFFILE
echo "  [OK] pkg/types/parse.go"

echo "=== docs/ + types/parse.go done ==="
ENDOFFILE
echo "Part 18 script written"
