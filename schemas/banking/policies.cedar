// Cedar Policies — Core Banking Platform

// MFA required for large debits
forbid(principal, action in [Action::"debit", Action::"approve"], resource)
when { context.transfer_amount_usd > 1000 && context.mfa_verified != true };

// All operations blocked on frozen accounts
forbid(principal, action, resource is Account)
when { resource.is_frozen == true };

// Compliance officers can always view
permit(principal in Role::"compliance_officer", action in [Action::"view", Action::"audit"], resource);

// Regulators have read-only access
permit(principal in Role::"regulator", action == Action::"view", resource);

// Default deny for unverified principals
forbid(principal, action, resource)
when { context.kyc_status != "verified" && ["debit","credit","approve"].contains(action) };
