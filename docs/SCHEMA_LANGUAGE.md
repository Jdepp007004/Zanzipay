# ZanziPay Schema Language Reference

## Overview

ZanziPay uses a Zanzibar-inspired schema language (`.zp` files) to define resource types, relations, and permissions.

## Syntax

### Definition

```
definition <type-name> {
    relation <name>: <allowed-subject-type> [| ...]
    permission <name> = <expression>
}
```

### Caveats

```
caveat <name>(<param>: <type>) {
    <cel-expression>
}
```

### Set Expressions

| Operator | Symbol | Meaning |
|----------|--------|---------|
| Union | `+` | Subject is in either set |
| Intersection | `&` | Subject is in both sets |
| Exclusion | `-` | Subject is in left but not right |
| Arrow | `->` | Follow relation, check permission on result |
| Computed | `name` | Directly evaluate another relation/permission |

## Example

```zanzibar
caveat kyc_verified() {
    context.kyc_status == "verified"
}

definition user {}

definition account {
    relation owner:  user
    relation viewer: user
    relation org:    team

    permission manage = owner
    permission view   = owner + viewer + org->access
    permission payout = owner with kyc_verified
}
```

## Arrow Expressions

Arrows follow a relation and evaluate a permission on the resulting object:

```
org->access
```

Means: *find all objects in the `org` relation, then check if subject has `access` on each*.

## Caveat Expressions

Caveats are CEL (Common Expression Language) conditions evaluated at check time:

```zanzibar
caveat amount_limit(max: int) {
    context.amount <= max
}
permission transfer = owner with amount_limit(10000)
```

## Subject Sets (Usersets)

A subject can be a userset reference:
```yaml
subject_type: team
subject_id:   payments-eng
subject_relation: member
```

This means: *all members of `team:payments-eng`*.
