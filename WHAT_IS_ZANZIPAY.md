# ZanziPay — What It Is, How It Works, and Why It Matters

**Written for someone with zero computer science knowledge.**

---

## Part 1: What Problem Does This Solve?

### The Lock and Key Problem

Imagine you run a bank. You have millions of customers, thousands of employees, and hundreds of different actions people can take — transfer money, view balances, freeze accounts, approve loans, generate reports.

Now imagine you need to answer this question **millions of times per second**:

> "Is this person allowed to do this thing to this account?"

That question seems simple. But the rules behind the answer are incredibly complex:

- **Alice** can view **her own** account
- **Bob** can manage **any** account in **his company** — but only during business hours
- **Charlie** is a compliance officer who can **read** anything but **change** nothing
- **Eve's** company is on a **government sanctions list** — she should be blocked from everything
- **Mallory's** account is **frozen** by court order — no one can touch it
- **The CEO** can override a freeze, but only with **two-factor authentication**

Now multiply that by millions of accounts, thousands of employees, regulatory requirements from multiple countries, and you begin to see the problem. You can't hardcode these rules. You need a **system** that evaluates them in real time.

That system is what ZanziPay builds.

---

## Part 2: What Is ZanziPay?

ZanziPay is an **authorization platform** — a system that answers one question:

> **"Is Subject X allowed to perform Action Y on Resource Z?"**

It answers this question by consulting **three independent engines** simultaneously:

### Engine 1: The Relationship Engine (ReBAC)

Think of this as a **family tree for permissions**.

Real-world example: Alice works at Acme Corp. Acme Corp owns Account #1234. Because Alice works at Acme Corp, and Acme Corp owns Account #1234, Alice can view Account #1234.

The system stores these relationships as simple statements called **tuples**:

```
company:acme#employee@user:alice         (Alice works at Acme)
account:1234#owner@company:acme          (Acme owns Account 1234)
```

When someone asks "Can Alice view Account 1234?", the engine **walks the graph**:
1. Is Alice directly listed as a viewer? → No
2. Does Account 1234 have an owner? → Yes, company:acme
3. Is Alice a member of company:acme? → Yes, she's an employee
4. Permission rule says: `view = owner + employee` → **ALLOWED**

This is called **Relationship-Based Access Control (ReBAC)** and it's what Google uses internally to manage permissions across Gmail, Drive, YouTube, and every other Google product. Google published a research paper about their system called **Zanzibar** in 2019 — that paper is the inspiration for ZanziPay.

**How a "tuple" works in plain English:**  
A tuple is like writing "Alice → works at → Acme Corp" on an index card. The system stores millions of these cards and can search through them in microseconds.

**What "walking the graph" means:**  
Imagine the index cards are connected by strings. "Alice → Acme" and "Acme → Account 1234" are connected. Following the strings from Alice to Account 1234 is "walking the graph."

### Engine 2: The Policy Engine (Cedar ABAC)

The relationship engine answers **who has access**. But some rules are about **conditions**, not relationships:

- "Only allow transfers under $10,000"  
- "Only allow API access during business hours"  
- "Block any action if the user hasn't verified their identity"

These rules are written in a language called **Cedar** (created by Amazon for AWS). Cedar rules look like this:

```
forbid(principal, action == "transfer", resource)
when { context.amount > 10000 && context.kyc_status != "verified" };
```

Translation: "Deny any transfer over $10,000 if the user isn't KYC-verified."

The policy engine reads these rules and checks them against the details of each request.

**What "ABAC" means:**  
ABAC stands for "Attribute-Based Access Control." Instead of checking relationships (who you are connected to), it checks **attributes** (properties like your KYC level, the transaction amount, the time of day).

### Engine 3: The Compliance Engine

Financial companies must follow laws. These laws aren't suggestions — violating them can result in billion-dollar fines or criminal charges. The compliance engine enforces:

1. **Sanctions Screening (OFAC/EU/UN):**  
   Governments maintain lists of people and companies that are banned from financial transactions — terrorists, money launderers, sanctioned regimes. Before allowing any action, the system checks if the user's name approximately matches anyone on these lists using **fuzzy name matching** (because "Mohammed al-Rahman" might be listed as "Mohammad Al Rahman"). The matching algorithm is called Jaro-Winkler and produces a similarity score from 0 to 1.

2. **KYC Gate (Know Your Customer):**  
   Banks are legally required to verify customers' identities before allowing financial actions. KYC has tiers:
   - Tier 1: Basic identity (can view balances)
   - Tier 2: Full ID verification (can transfer money)
   - Tier 3: Enhanced due diligence (can do large transactions)

3. **Account Freezes:**  
   Courts can order accounts frozen. When an account is frozen, NO action is allowed — not even viewing — until the freeze is lifted.

4. **Regulatory Overrides:**  
   Government agencies (like the SEC or FCA) can issue blanket blocks on specific accounts or entities.

**The compliance engine has absolute veto power.** Even if the relationship engine says "ALLOWED" and the policy engine says "ALLOWED," if the compliance engine says "DENIED," the answer is **DENIED**. A sanctions match can never be overridden by a Cedar policy.

---

## Part 3: How They Work Together

When a request comes in, this happens in about **0.1 milliseconds** (that's 0.0001 seconds):

```
Step 1: Request arrives
        "Can user:alice do transfer on account:1234?"

Step 2: Orchestrator receives the request
        Launches 3 checks IN PARALLEL (at the same time):
        
        ┌─ ReBAC Engine  ──→ walks relationship graph ──→ ALLOWED
        │
        ├─ Policy Engine  ──→ evaluates Cedar rules    ──→ ALLOWED  
        │
        └─ Compliance     ──→ sanctions + KYC + freeze ──→ ALLOWED

Step 3: Merge verdicts (AND logic)
        ReBAC=ALLOWED ∧ Policy=ALLOWED ∧ Compliance=ALLOWED
        → Final verdict: ALLOWED

Step 4: Log the decision (immutable audit trail)
        Record: who, what, when, verdict, reasoning, signed token

Step 5: Return to client
        { "allowed": true, "decision_token": "aB3xK9..." }
```

If **any** engine says DENIED, the final answer is DENIED.

**Why parallel?** Because running them one-after-another would take 3× as long. Running them simultaneously means the total time equals the slowest engine (not the sum of all three).

---

## Part 4: What Is a "Zookie" and Why Does It Matter?

Imagine this scenario:
1. Alice's access is **revoked** at 10:00:00.000 AM
2. At 10:00:00.001 AM (1 millisecond later), Alice tries to access the account
3. The system processes her request — but the server hasn't received the revocation update yet
4. Result: Alice is **incorrectly allowed** in — the "new enemy" problem

Google solved this with **Zookies** (named after "Zanzibar cookies"). A zookie is a **timestamp token** that proves "this answer is based on data at least as fresh as time T."

When you write a permission change, the system returns a zookie. When you check a permission, you can include that zookie to say "give me an answer that includes changes at least as recent as this zookie." The system uses these tokens to guarantee **causal consistency** — meaning "if I just changed something, the next check will see that change."

**In plain English:** A zookie is like a receipt that says "I made a change at 10:00 AM." When you present that receipt with your next question, the system guarantees its answer reflects everything that happened up to 10:00 AM.

---

## Part 5: The Storage System

### Where the data lives

All those relationship tuples, Cedar policies, sanctions lists, and audit logs need to be stored somewhere reliable.

ZanziPay supports two storage backends:

1. **Memory (for development and benchmarks):**  
   Everything is stored in the computer's RAM. Extremely fast (no disk access) but everything disappears when the program restarts. This is how we got the 208,000 requests/second benchmark — it's measuring pure computation speed without any disk or network delays.

2. **PostgreSQL (for production):**  
   A real database that stores data on disk. Data survives restarts, supports multiple servers reading simultaneously, and provides transaction guarantees (if the power goes out mid-write, the database won't be corrupted). This adds ~2-5ms of latency to every operation.

### MVCC — How updates work without blocking readers

MVCC stands for "Multi-Version Concurrency Control." Here's what it means in plain English:

When someone updates a permission, we don't **modify** the old record. We write a **new version** and mark the old one as "deleted at revision N." This means:
- Readers looking at revision N-1 will still see the old data (consistent view)
- Readers looking at revision N will see the new data
- No reader is ever blocked by a writer

This is the same technique used by Google Spanner, CockroachDB, and PostgreSQL.

---

## Part 6: The Audit Trail (Why Banks Need This)

Every authorization decision is recorded in an **immutable, append-only log**. "Immutable" means once a record is written, it can **never** be changed or deleted — not even by a database administrator. The database enforces this with triggers that reject any UPDATE or DELETE command on the audit table.

Each audit record contains:
- **Who** asked (subject type + ID, client IP, user agent)
- **What** they wanted to do (action, resource)
- **When** they asked (nanosecond-precision timestamp)
- **What was decided** (ALLOWED/DENIED + reasoning from each engine)
- **How long it took** (evaluation duration in nanoseconds)
- **A signed token** (HMAC-SHA256 hash proving this record is authentic and hasn't been tampered with)

**Why this matters:** Regulations like SOX (Sarbanes-Oxley), PCI-DSS (Payment Card Industry), and GDPR require companies to maintain complete, tamper-proof audit trails. If a regulator asks "show me every permission decision about Account X in the last 90 days," the company must be able to produce that instantly.

---

## Part 7: How Fast Is It? (Honest Benchmarks)

### ZanziPay Performance (measured, real)

We ran 5 different test scenarios, each for 8 seconds with 50 simultaneous workers:

| What We Tested | Average Response Time | Maximum Sustained Speed |
|----------------|----------------------|------------------------|
| Simple permission check | 0.064 milliseconds | 208,061 checks/second |
| Denied permission check | 0.088 milliseconds | 145,285 checks/second |
| Multi-hop group membership | 0.133 milliseconds | 126,343 checks/second |
| High contention (50 workers, same data) | 0.130 milliseconds | 137,688 checks/second |
| Full compliance pipeline (all 3 engines) | 0.141 milliseconds | 138,484 checks/second |

**Total:** 7,047,401 authorization decisions in ~45 seconds with **zero errors**.

### Important Caveat

These numbers use an **in-memory** backend with **no network**. This is like measuring how fast a car's engine can spin without actually driving on the road. The engine speed is real, but a real deployment would add:

- **Database latency:** ~2-5ms per query (PostgreSQL)
- **Network latency:** ~0.1-1ms between services

**Estimated production performance:** ~2-6ms per check (comparable to Google Zanzibar and SpiceDB)

### How This Compares to Real Systems

| System | Who Made It | Typical P95 Latency | Scale | Notes |
|--------|------------|---------------------|-------|-------|
| **Google Zanzibar** | Google (internal) | < 10ms | > 10M checks/sec, 2T tuples | Not publicly available. Powers Gmail, Drive, YouTube |
| **SpiceDB** | AuthZed (startup) | ~5.76ms at 1M QPS | 100B relationships tested | Open source. Closest to Zanzibar |
| **OpenFGA** | Auth0 (Okta) | "millisecond-level" | Not published | Open source. 20x improvement in 2024 |
| **AWS Cedar** | Amazon | < 1ms (policy only) | Used by AWS Verified Permissions | Policy engine only — no relationship graph |
| **Ory Keto** | Ory (startup) | sub-10ms (target) | Not published | Open source. Zanzibar-inspired |
| **ZanziPay** | This project | ~0.1ms (engine only) / ~2-6ms (estimated production) | 208K checks/sec (bench) | Adds compliance + Cedar policies on top of Zanzibar |

---

## Part 8: How Is the Code Organized?

```
zanzipay/
│
├── cmd/                           ← Programs you can run
│   ├── zanzipay-server/           ← The main server (receives requests, returns answers)
│   ├── zanzipay-cli/              ← Command-line tool (for admins to manage schemas/tuples)
│   └── zanzipay-bench/            ← Benchmark program (measures speed)
│
├── internal/                      ← The brain — private code nobody outside the project uses
│   ├── rebac/                     ← Engine 1: Relationship graph walker
│   │   ├── engine.go              ← Main entry point for checks
│   │   ├── check.go               ← The graph-walking algorithm
│   │   ├── schema.go              ← Schema parser (understands "definition user {}")
│   │   ├── caveat.go              ← Conditional relationship evaluator
│   │   └── zookie.go              ← Consistency token manager
│   │
│   ├── policy/                    ← Engine 2: Cedar policy evaluator
│   │   ├── engine.go              ← Main entry point for policy checks
│   │   ├── abac.go                ← Condition evaluator (>, <, ==, contains, etc.)
│   │   └── temporal.go            ← Time-based rules (business hours, expiry)
│   │
│   ├── compliance/                ← Engine 3: Legal compliance checks
│   │   ├── engine.go              ← Orchestrates all 4 sub-checks
│   │   ├── sanctions.go           ← OFAC/EU/UN name matching
│   │   ├── kyc.go                 ← Identity verification tier gate
│   │   ├── freeze.go              ← Account freeze enforcement
│   │   └── regulatory.go          ← Government override enforcement
│   │
│   ├── orchestrator/              ← The coordinator: runs all 3 engines in parallel
│   ├── audit/                     ← Immutable decision logging + report generation
│   ├── index/                     ← Fast reverse lookups ("what can Alice access?")
│   ├── storage/                   ← Where data is stored (memory or PostgreSQL)
│   └── server/                    ← HTTP/gRPC server + middleware (auth, rate limiting)
│
├── schemas/                       ← Example permission configurations
│   ├── stripe/                    ← For payment platforms (like Stripe)
│   ├── marketplace/               ← For two-sided marketplaces (like Airbnb)
│   └── banking/                   ← For banks and neobanks
│
├── frontend/                      ← Web dashboard showing benchmark results
├── bench/results/                 ← Raw benchmark data (JSON)
├── deploy/                        ← Docker, Kubernetes, Terraform configs
└── docs/                          ← Documentation
```

---

## Part 9: Who Would Use This?

### Target Users

1. **Payment platforms** (like Stripe, Square, Adyen)  
   Need to control which merchants can access which accounts, which employees can issue refunds, which APIs each client can call.

2. **Neobanks** (like Revolut, Chime, Nubank)  
   Need KYC-gated permissions, sanctions screening on every transaction, and immutable audit trails for regulators.

3. **Marketplace platforms** (like Airbnb, Uber, Etsy)  
   Need multi-tenant permissions (host owns listing, guest can book, platform admin can override).

4. **Any financial SaaS company** that needs to prove to regulators that their access controls are correct, auditable, and compliant.

### What It Replaces

Without ZanziPay, companies typically:
- Hardcode permissions in their application code (fragile, not auditable)
- Use basic RBAC (roles like "admin" and "user" — too coarse for fintech)
- Build custom authorization from scratch (expensive, bug-prone)
- Use SpiceDB or OpenFGA (no compliance engine, no Cedar policies)

---

## Part 10: Key Technical Decisions Explained

### Why Go (the programming language)?

Go is fast (compiled, not interpreted), concurrent (built-in goroutines for parallel execution), and has a simple dependency model (single binary, no runtime needed). Google's original Zanzibar is written in C++, but SpiceDB, OpenFGA, and Ory Keto are all written in Go — it's the standard language for authorization systems.

### Why not use an existing library for Cedar?

AWS Cedar is officially implemented in Rust, and the Go ecosystem doesn't have a mature Cedar library. Rather than adding a complex Rust-to-Go bridge (which would require CGO, making cross-compilation difficult), ZanziPay implements a Cedar-compatible evaluator in pure Go. It handles the same `permit`/`forbid` syntax with `when` conditions and uses the same deny-overrides algorithm.

### Why three separate engines instead of one?

Separation of concerns. A relationship check ("is Alice connected to this account?") is fundamentally different from a policy check ("is this transfer within business hours?") and a compliance check ("is this person sanctioned?"). Running them separately means:
- Each engine can be tested independently
- The compliance engine can never be bypassed
- Performance can be measured per-engine
- Bugs in one engine don't affect the others

### Why is the audit log "immutable"?

If someone could delete audit records, they could cover their tracks after unauthorized access. Financial regulations require that audit logs be tamper-proof. The database enforces this with triggers that **reject** any attempt to update or delete records.

---

## Glossary

| Term | Plain English |
|------|--------------|
| **Authorization** | Deciding if someone is allowed to do something |
| **Authentication** | Proving who someone is (usually with a password) — NOT the same as authorization |
| **Tuple** | A single relationship fact: "Alice works at Acme" |
| **ReBAC** | Relationship-Based Access Control — permissions based on who you're connected to |
| **ABAC** | Attribute-Based Access Control — permissions based on properties (amount, time, role) |
| **Cedar** | A policy language created by Amazon for writing access rules |
| **Zanzibar** | Google's internal authorization system (the inspiration for this project) |
| **Zookie** | A consistency token that prevents stale permission data from causing errors |
| **MVCC** | Multi-Version Concurrency Control — reading old data while new data is being written |
| **Sanctions** | Government lists of people/companies banned from financial transactions |
| **KYC** | Know Your Customer — legal requirement to verify client identities |
| **SOX** | Sarbanes-Oxley Act — US law requiring financial audit trails |
| **PCI-DSS** | Payment Card Industry Data Security Standard |
| **gRPC** | A fast network protocol for computer-to-computer communication |
| **REST** | A simpler network protocol using HTTP (like web browsers use) |
| **Latency** | How long something takes (measured in milliseconds) |
| **Throughput** | How many things can be done per second |
| **P50/P95/P99** | The time within which 50%/95%/99% of requests complete |
| **PostgreSQL** | A popular open-source database |
| **Go/Golang** | A programming language by Google, used for servers |
| **Graph walk** | Following connections between data points to find a path |
| **HMAC** | A cryptographic signature that proves data hasn't been tampered with |
