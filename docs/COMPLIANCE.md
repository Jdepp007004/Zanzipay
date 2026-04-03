# Compliance Engine Guide

## Overview

The ZanziPay Compliance Engine implements a **Compliance Veto** architecture — any compliance violation results in an **absolute DENY** that no other engine can override.

## Checks Performed (in parallel)

### 1. Sanctions Screening

Checks subject names against:
- **OFAC** (US Treasury SDN List)
- **EU Consolidated Sanctions**
- **UN Security Council Sanctions**

Uses **Jaro-Winkler fuzzy matching** (threshold: 0.85) to catch name variations.

```go
dec, _ := compliance.Evaluate(ctx, &compliance.ComplianceRequest{
    SubjectNames: []string{"Vladimir Putin", "V. Putin"},
    Action:       "transfer",
})
// dec.Allowed == false if name hits sanctions
```

### 2. KYC Gate

Maps actions to minimum KYC tiers:

| Action | Required Tier |
|--------|--------------|
| `view`, `read_balance` | Tier 1 |
| `transfer`, `refund`, `initiate_payout` | Tier 2 |
| `large_transfer`, `regulatory_report` | Tier 3 |

### 3. Account Freezes

Checks `zp_freezes` table for active (non-lifted) freezes on the resource.

### 4. Regulatory Overrides

Checks `zp_regulatory_overrides` for active court orders, AML investigations, or regulator-issued holds.

## Adding a Custom Compliance Check

Implement the `ComplianceStore` interface and inject into the engine:

```go
engine := compliance.NewEngine(myStore, func(ctx context.Context, id string) (compliance.KYCTier, error) {
    return lookupKYCTier(ctx, id) // your KYC resolver
})
```

## SOX / PCI-DSS Reporting

```go
report, _ := auditLogger.GenerateSOXReport(ctx, audit.TimeRange{
    Start: time.Now().AddDate(0, -3, 0),
    End:   time.Now(),
})
// report.TotalDecisions, report.DeniedDecisions, report.Summary
```
