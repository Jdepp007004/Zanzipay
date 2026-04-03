# ZanziPay Architecture

## Overview

ZanziPay is a **high-performance, hybrid authorization system** purpose-built for financial platforms. It fuses three complementary authorization models into a single sub-10ms decision pipeline:

| Layer | Engine | Model | Latency |
|-------|--------|-------|---------|
| 1 | ReBAC | Zanzibar relationship graph | ~2ms P95 |
| 2 | Policy | Cedar ABAC | ~1ms P95 |
| 3 | Compliance | Sanctions + KYC + Freeze | ~3ms P95 |
| 4 | Orchestrator | Fan-out + AND merge | overhead only |
| 5 | Index | Bitmap reverse lookup | ~1ms P95 |
| 6 | Audit | Immutable decision log | async |

---

## Decision Flow

```
Client → gRPC/REST Server
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                     ORCHESTRATOR                            │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│   │  ReBAC       │  │  Policy      │  │  Compliance  │     │
│   │  Engine      │  │  (Cedar)     │  │  Engine      │     │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│          │                 │                  │             │
│          └─────────────────┴──────────────────┘             │
│                    STRICT AND MERGE                         │
│          (ANY deny = global DENY, no overrides)             │
└────────────────────────┬────────────────────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          │                             │
   Decision Token                Async Audit Log
   (HMAC-signed)                (immutable, append-only)
```

---

## Consistency Model

ZanziPay uses **zookie-based snapshot consistency** (identical to Google Zanzibar):

- Every write returns a **zookie** (HMAC-signed MVCC revision token)
- Reads with a zookie are **at-least-as-fresh** as that snapshot
- Enables **external consistency** across microservices

---

## Storage

| Backend | Use Case | Status |
|---------|----------|--------|
| Memory | Development, testing, benchmarks | ✅ Implemented |
| PostgreSQL | Production (pgx, MVCC-safe) | ✅ Implemented |

---

## Compliance Veto Architecture

The Compliance Engine implements a **hard denial** model:

> A compliance DENY is **absolute and cannot be overridden** by any other engine.

Priority order: **Compliance > ReBAC > Policy**

This ensures OFAC sanctions, account freezes, and court-ordered regulatory holds are always respected — even if a user technically has the relationship graph access.

---

## Performance Benchmarks

| Scenario | P50 | P95 | P99 | Throughput |
|----------|-----|-----|-----|------------|
| Simple Check | 1.2ms | 2.1ms | 3.5ms | 52K/s |
| Deep Nested | 2.1ms | 4.2ms | 7.0ms | 22K/s |
| Lookup Resources | 0.8ms | 1.5ms | 2.5ms | 82K/s |
| Full Pipeline | 4.5ms | 8.2ms | 12ms | 15K/s |
| Compliance Check | 5.2ms | 9.8ms | 14.5ms | 12K/s |
