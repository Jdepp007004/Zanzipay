// Cedar Policies — Stripe-like Platform

// Require KYC for all financial actions
forbid(principal, action, resource)
when {
    ["initiate_payout", "transfer", "refund", "capture"].contains(action) &&
    context.kyc_status != "verified"
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

// Operators can capture within their limit
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
