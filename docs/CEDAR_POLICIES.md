# Cedar Policy Authoring Guide

## Overview

ZanziPay uses a Cedar-compatible policy language for ABAC (Attribute-Based Access Control). Policies run as the **second layer** of the authorization pipeline, after the ReBAC relationship graph check.

## Policy Structure

Every policy is either a `permit` or `forbid` statement:

```cedar
permit | forbid (
    principal [in <group>] [is <type>],
    action    [== <action> | in [<action>, ...]],
    resource  [is <type>]
)
[when   { <condition> }]
[unless { <condition> }];
```

## Evaluation Model

| Rule | Behaviour |
|------|-----------|
| Base case | **DENY** (implicit deny) |
| Any `permit` matches | → ALLOW (unless a `forbid` also matches) |
| Any `forbid` matches | → DENY (even if `permit` also matches) |

`forbid` always wins — this is called **deny-overrides**.

## Common Fintech Patterns

### KYC Tier Enforcement

```cedar
// Block all financial actions for unverified users
forbid(principal, action, resource)
when {
    ["transfer", "payout", "capture", "refund"].contains(action) &&
    context.kyc_status != "verified"
};

// Tier 3 required for large transactions
forbid(principal, action == Action::"transfer", resource)
when {
    context.transfer_amount_usd > 50000 &&
    context.kyc_tier < 3
};
```

### Time-Based Restrictions

```cedar
// Block large transfers outside business hours
forbid(principal, action == Action::"transfer", resource)
when {
    context.transfer_amount > 10000 &&
    !context.is_business_hours
};

// Weekend restrictions for international wires
forbid(principal, action == Action::"international_wire", resource)
when { context.day_of_week in ["Saturday", "Sunday"] };
```

### Account Freeze

```cedar
// Freeze blocks all financial operations
forbid(principal, action, resource is Account)
when { resource.is_frozen == true };
```

### Role-Based Escalations

```cedar
// Compliance officers can view everything
permit(
    principal in Role::"compliance_officer",
    action in [Action::"view", Action::"audit", Action::"generate_report"],
    resource
);

// Operators have limited capture rights
permit(
    principal in Role::"operator",
    action == Action::"capture",
    resource is PaymentIntent
)
when { context.amount <= principal.capture_limit };
```

### Sanctions Override

```cedar
// Platform admins can lift temporary transaction blocks (NOT sanctions - those are engine-level)
permit(
    principal in Role::"platform_admin",
    action == Action::"unblock_transaction",
    resource is Transaction
)
when { resource.block_type == "temporary" };
```

## Loading Policies into ZanziPay

```bash
# Write policies via CLI
./bin/zanzipay-cli policy write --file schemas/stripe/policies.cedar --version v1.0.0

# or via REST API
curl -X POST http://localhost:8090/v1/policies \
  -H "Content-Type: application/json" \
  -d '{"version":"v1.0.0","policies":"permit(principal,...)"}'
```

## Testing Policies

```bash
# Simulate a policy-only check
./bin/zanzipay-cli check \
  --subject "user:alice" \
  --resource "account:acme-main" \
  --action "transfer" \
  --context '{"kyc_status":"verified","transfer_amount":5000,"is_business_hours":true}'
```

## Policy Versioning

All policy versions are stored in `zp_policies` (immutable history). Rolling back:

```sql
-- See all versions
SELECT version, created_at FROM zp_policies ORDER BY created_at DESC;

-- Re-activate previous version (re-insert as new latest)
INSERT INTO zp_policies (version, source)
SELECT 'v1.0.0-rollback', source FROM zp_policies WHERE version = 'v1.0.0';
```

## Integration with Compliance Engine

Cedar policies run **in parallel** with the compliance engine. They operate on:
- **Context attributes**: `kyc_status`, `transfer_amount`, `is_business_hours`, `mfa_verified`
- **Principal attributes**: `kyc_tier`, `capture_limit`, `roles`
- **Resource attributes**: `is_frozen`, `block_type`, `product_type`

> **Important**: Cedar policies **cannot** override a Compliance Engine veto. Sanctions, account freezes, and regulatory holds always win.
