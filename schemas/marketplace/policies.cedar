// Cedar Policies — Marketplace Platform

// Sellers can view their own orders
permit(principal, action == Action::"view", resource is Order)
when { resource.seller_id == principal.id };

// Buyers can refund within 30 days
permit(principal, action == Action::"refund", resource is Order)
when { resource.buyer_id == principal.id && context.days_since_delivery <= 30 };

// Block refunds for digital goods
forbid(principal, action == Action::"refund", resource is Order)
when { resource.product_type == "digital" };

// Marketplace admin has full access
permit(principal in Role::"marketplace_admin", action, resource);
