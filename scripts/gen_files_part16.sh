#!/usr/bin/env bash
# Part 16: schemas, deploy, scripts, docs, frontend
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── schemas/ ─────────────────────────────────────────────────────────────────
cat > schemas/stripe/schema.zp << 'ENDOFFILE'
// ZanziPay Schema — Stripe-like Payment Platform

caveat amount_limit(max_amount: int) {
    context.transfer_amount <= max_amount
}

caveat business_hours_only(timezone: string) {
    // Evaluated at runtime via CEL
    context.is_business_hours == true
}

caveat kyc_verified() {
    context.kyc_status == "verified"
}

definition user {}

definition team {
    relation member: user
    relation admin:  user | team#admin
    permission access = admin + member
}

definition platform {
    relation admin: user | team#member
    permission platform_admin = admin
}

definition merchant {
    relation owner:    user | team#member
    relation admin:    user | team#member
    relation operator: user | team#member
    relation viewer:   user | team#member
    relation platform: platform

    permission manage  = owner + admin
    permission operate  = manage + operator
    permission view    = operate + viewer
    permission platform_view = platform->platform_admin
}

definition account {
    relation merchant: merchant
    relation owner:    user | team#member
    relation admin:    user | team#member
    relation viewer:   user

    permission manage     = owner + admin + merchant->manage
    permission view       = manage + viewer + merchant->view
    permission initiate_payout = owner with kyc_verified + admin with kyc_verified
}

definition payment_intent {
    relation account: account
    relation initiator: user

    permission view    = account->view + initiator
    permission capture = account->manage + initiator with amount_limit
    permission refund  = account->manage
}

definition api_key {
    relation owner: user | merchant
    permission use = owner
}

definition webhook_endpoint {
    relation merchant: merchant
    permission manage = merchant->manage
    permission view   = merchant->view
}
ENDOFFILE
echo "  [OK] schemas/stripe/schema.zp"

cat > schemas/stripe/tuples.yaml << 'ENDOFFILE'
# Sample relationship tuples for the Stripe schema
tuples:
  # Teams
  - resource_type: team
    resource_id: payments-eng
    relation: member
    subject_type: user
    subject_id: alice
  - resource_type: team
    resource_id: payments-eng
    relation: admin
    subject_type: user
    subject_id: bob

  # Merchant setup
  - resource_type: merchant
    resource_id: acme-corp
    relation: owner
    subject_type: user
    subject_id: alice
  - resource_type: merchant
    resource_id: acme-corp
    relation: operator
    subject_type: team
    subject_id: payments-eng
    subject_relation: member

  # Account owned by merchant
  - resource_type: account
    resource_id: acme-main
    relation: merchant
    subject_type: merchant
    subject_id: acme-corp

  # Payment intent
  - resource_type: payment_intent
    resource_id: pi_001
    relation: account
    subject_type: account
    subject_id: acme-main
  - resource_type: payment_intent
    resource_id: pi_001
    relation: initiator
    subject_type: user
    subject_id: alice
ENDOFFILE
echo "  [OK] schemas/stripe/tuples.yaml"

cat > schemas/stripe/policies.cedar << 'ENDOFFILE'
// Cedar Policies — Stripe-like Platform

// Global: require KYC verification for all financial actions
forbid(principal, action, resource)
when {
    ["initiate_payout", "transfer", "refund", "capture"].contains(action) &&
    context.principal.kyc_status != "verified"
};

// Restrict large transfers to business hours
forbid(principal, action == Action::"transfer", resource)
when {
    context.transfer_amount > 10000 &&
    !context.is_business_hours
};

// Frozen accounts cannot process any transactions
forbid(principal, action, resource)
when {
    resource.is_frozen == true &&
    ["initiate_payout", "transfer", "capture", "refund"].contains(action)
};

// Permit: operators can capture within their limit
permit(
    principal in Role::"operator",
    action == Action::"capture",
    resource is PaymentIntent
)
when {
    context.transfer_amount <= principal.capture_limit
};

// Platform admins have read access to all merchants
permit(
    principal in Role::"platform_admin",
    action in [Action::"view", Action::"audit"],
    resource
);
ENDOFFILE
echo "  [OK] schemas/stripe/policies.cedar"

cat > schemas/marketplace/schema.zp << 'ENDOFFILE'
// ZanziPay Schema — Marketplace Platform

definition user {}
definition seller {}
definition buyer {}

definition marketplace {
    relation admin: user
    permission manage = admin
}

definition listing {
    relation seller: seller | user
    relation viewer: user | buyer
    relation marketplace: marketplace

    permission view    = seller + viewer + marketplace->manage
    permission edit    = seller
    permission publish = seller + marketplace->manage
}

definition order {
    relation buyer:  buyer | user
    relation seller: seller | user
    relation marketplace: marketplace

    permission view    = buyer + seller + marketplace->manage
    permission deliver = seller
    permission refund  = buyer + marketplace->manage
    permission dispute = buyer + marketplace->manage
}

definition escrow {
    relation order: order
    permission release = order->seller
    permission refund  = order->buyer + order->marketplace->manage
}
ENDOFFILE
echo "  [OK] schemas/marketplace/schema.zp"

cat > schemas/marketplace/tuples.yaml << 'ENDOFFILE'
tuples:
  - resource_type: marketplace
    resource_id: shopify-clone
    relation: admin
    subject_type: user
    subject_id: marketplace-admin
  - resource_type: listing
    resource_id: item-001
    relation: seller
    subject_type: user
    subject_id: seller-alice
  - resource_type: order
    resource_id: order-001
    relation: buyer
    subject_type: user
    subject_id: buyer-bob
  - resource_type: order
    resource_id: order-001
    relation: seller
    subject_type: user
    subject_id: seller-alice
ENDOFFILE
echo "  [OK] schemas/marketplace/tuples.yaml"

cat > schemas/marketplace/policies.cedar << 'ENDOFFILE'
// Cedar Policies — Marketplace Platform

// Sellers can only view their own orders
permit(
    principal,
    action == Action::"view",
    resource is Order
)
when { resource.seller_id == principal.id };

// Buyers can refund within return window
permit(
    principal,
    action == Action::"refund",
    resource is Order
)
when {
    resource.buyer_id == principal.id &&
    context.days_since_delivery <= 30
};

// Block refunds for digital goods
forbid(
    principal,
    action == Action::"refund",
    resource is Order
)
when { resource.product_type == "digital" };
ENDOFFILE
echo "  [OK] schemas/marketplace/policies.cedar"

cat > schemas/banking/schema.zp << 'ENDOFFILE'
// ZanziPay Schema — Banking / Core Banking Platform

caveat requires_mfa() {
    context.mfa_verified == true
}

caveat daily_limit(limit_usd: int) {
    context.daily_spent_usd + context.transfer_amount_usd <= limit_usd
}

caveat regulatory_hold() {
    context.regulatory_hold == false
}

definition user {}
definition compliance_officer {}
definition regulator {}
definition court {}

definition bank {
    relation admin: user
    relation compliance: compliance_officer
    relation regulator:  regulator
    permission manage    = admin
    permission audit     = manage + compliance + regulator
}

definition customer {
    relation owner: user
    relation joint: user
    relation bank:  bank
    permission view  = owner + joint + bank->audit
    permission manage = owner + bank->manage
}

definition account {
    relation customer: customer
    relation bank:     bank
    relation frozen_by: compliance_officer | court

    permission view     = customer->view + bank->audit
    permission debit    = customer->manage with requires_mfa with regulatory_hold
    permission credit   = customer->manage with regulatory_hold
    permission close    = bank->manage
    permission freeze   = bank->compliance
    permission unfreeze = bank->compliance + frozen_by
}

definition transaction {
    relation account: account
    relation initiator: user

    permission view   = account->view + initiator
    permission approve = account->debit with daily_limit
    permission reverse = account->bank->compliance
}

definition report {
    relation bank: bank
    permission generate = bank->compliance + bank->regulator
    permission view     = bank->audit
}
ENDOFFILE
echo "  [OK] schemas/banking/schema.zp"

cat > schemas/banking/tuples.yaml << 'ENDOFFILE'
tuples:
  - resource_type: bank
    resource_id: first-national
    relation: admin
    subject_type: user
    subject_id: bank-admin
  - resource_type: customer
    resource_id: customer-001
    relation: owner
    subject_type: user
    subject_id: alice
  - resource_type: account
    resource_id: checking-001
    relation: customer
    subject_type: customer
    subject_id: customer-001
  - resource_type: account
    resource_id: checking-001
    relation: bank
    subject_type: bank
    subject_id: first-national
ENDOFFILE
echo "  [OK] schemas/banking/tuples.yaml"

cat > schemas/banking/policies.cedar << 'ENDOFFILE'
// Cedar Policies — Core Banking Platform

// All transactions require MFA for amounts over $1000
forbid(principal, action in [Action::"debit", Action::"approve"], resource)
when {
    context.transfer_amount_usd > 1000 &&
    context.mfa_verified != true
};

// Block all operations on frozen accounts
forbid(principal, action, resource is Account)
when { resource.is_frozen == true };

// Compliance officers can always view
permit(
    principal in Role::"compliance_officer",
    action in [Action::"view", Action::"audit"],
    resource
);

// Regulators have read-only access
permit(
    principal in Role::"regulator",
    action == Action::"view",
    resource
);

// Court-ordered freezes cannot be lifted without court permission
forbid(
    principal,
    action == Action::"unfreeze",
    resource is Account
)
when {
    resource.freeze_authority == "court" &&
    !principal.has_role("court")
};
ENDOFFILE
echo "  [OK] schemas/banking/policies.cedar"

echo "=== schemas/ done ==="
ENDOFFILE
echo "Part 16 script written"
