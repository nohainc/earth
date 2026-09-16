# EARTH Gameplay V5 — AI Execution Playbook

Status: **EXECUTION GUIDE**  
Version: 5.0-design

## 1. Purpose

This file is written specifically so a development AI can implement V5 in the
correct order without reinterpreting the game design.

For every V5 task, the AI must first read:

1. `docs/AI_DEVELOPMENT_INSTRUCTIONS.md`
2. `docs/ADR-003-v5-corporation-territory-capacity-model.md`
3. `docs/v5/V5_MASTER_GAMEPLAY_SPEC.md`
4. `docs/v5/V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md`
5. `docs/v5/V5_DOMAIN_AND_DATA_MIGRATION.md`
6. the relevant phase in `docs/v5/V5_IMPLEMENTATION_ROADMAP.md`
7. current source/tests/migrations for the touched domain.

The AI must explicitly state whether the task modifies **current runtime**, adds
**shadow V5 capability**, or completes a **V5 cutover**.

---

# 2. Universal AI constraints

Every V5 implementation task must obey these rules:

- PostgreSQL is authoritative.
- Do not calculate authoritative economics in Flutter.
- Do not hard-code balance values that belong in versioned rules/catalogs.
- Do not remove current schema fields merely because V5 will stop using them.
- Do not rewrite historical ledger/governance/ownership records.
- Economic mutations are atomic, idempotent, and ledgered.
- Use current money/fixed-point helpers; no floating-point authoritative math.
- Game day/rule version are explicit inputs.
- Every consequence-changing command must re-check mutable authorization and
  balances inside its transaction.
- Outbox/history records are written in the same transaction as the mutation.
- UI shows loading until server confirmation for money/governance actions.
- No silent compatibility fallback that fabricates a value.
- Keep commits small enough to review/rollback.
- Maintain the repository's 80% line-coverage requirement.

---

# 3. AI task format

Each V5 task handed to an AI should use this structure:

```text
Task ID:
Phase:
Goal:
Current-runtime evidence:
Target V5 behavior:
Read first:
Files/domains likely affected:
Schema changes:
API/read-model changes:
Settlement impact:
Flutter impact:
Migration/backfill impact:
Security/authorization rules:
Idempotency/correlation requirements:
Required tests:
Manual verification:
Out of scope:
Definition of done:
```

The AI must not broaden the task beyond `Out of scope` unless a discovered
blocking dependency makes completion impossible. In that case it should document
the blocker and implement the smallest safe prerequisite.

---

# 4. Phase task packages

The following packages are suitable to send sequentially to an AI developer.
They are intentionally ordered.

## V5-01A — Pure marginal bracket calculator

### Goal
Implement the pure deterministic marginal bracket calculation module with exact
numeric semantics and exhaustive tests. No database or UI changes.

### Must support

- ordered brackets;
- open-ended final bracket;
- marginal allocation only;
- capacity multiplier mode;
- later-compatible marginal-rate mode;
- detailed breakdown result for previews/audit.

### Required result

```text
calculateProgressiveCharge(quantity, baseRate, brackets)
→ total charge
→ per-bracket charged quantity
→ per-bracket rate/multiplier
→ marginal/current bracket
```

### Tests

- zero;
- every boundary ±1 minimal unit;
- multi-bracket quantities;
- very large integer values;
- no lower-bracket repricing;
- deterministic repeated result;
- overflow/invalid input handling.

### Out of scope
Database, governance, capacity settlement.

---

## V5-01B — Progressive policy persistence and validation

### Goal
Add forward migration/schema/manifest support for versioned progressive schedules
and brackets, plus repository/domain queries.

### Must include

- effective dates;
- authority/institution;
- immutable active versions;
- monotonic validation;
- no overlaps/gaps;
- query active schedule by code/game day.

### Verification
Fresh schema, migration path, canonical manifest, focused database tests.

---

## V5-02A — House capacity calculator

### Goal
Authoritatively calculate House V5 capacity from current canonical state.

### Formula

```text
1 residential unit for active affiliated House
+ sum(active billable private building slot footprints)
```

### Must not
Use `primary_territory_id` or count buildings from Flutter projections.

### Output
House capacity DTO + tests.

---

## V5-02B — Corporation capacity aggregator

### Goal
Aggregate House/public capacity per Corporation and derive required standardized
Territory-unit count.

### Output

- residential units;
- private building units;
- included public units;
- total occupied;
- required Territory units;
- utilization/read-model values.

### Tests
Exact Territory boundary cases.

---

## V5-02C — Capacity backfill/reconciliation command

### Goal
Build a resumable, dry-run-first reconciliation tool/report for existing data.

### Must report

- Houses counted;
- active affiliations;
- building footprint total;
- Corporation totals;
- Territory records vs V5 required count;
- invalid/unresolved data;
- no economic transactions posted.

---

## V5-03A — Capacity quote service

### Goal
Create one server service used by construction/join/upgrade previews.

### Output fields

- current usage;
- delta;
- after usage;
- current charge;
- after charge;
- incremental charge;
- bracket summaries;
- active rule versions;
- eligibility/blockers.

### Critical test
Quote must equal settlement calculation under identical inputs/rules.

---

## V5-03B — Building construction integration

### Goal
Integrate authoritative capacity quote into building construction preview and
commit.

### UI
Show capacity/rent impact before confirmation.

### Must not
Reimplement progression formula in Flutter.

---

## V5-03C — Membership integration

### Goal
Every successful Corporation join creates one residential unit consequence and
returns exact pricing/capacity preview before join/apply acceptance where useful.

---

## V5-04A — House daily capacity assessment

### Goal
Assess the daily House capacity obligation using current Corporation base rate
and EARTH progressive schedule.

### Required audit

- game day;
- House/Corporation;
- usage;
- base-rate version;
- progressive schedule version;
- assessed amount.

No hidden balance decrement.

---

## V5-04B — House capacity payment + arrears

### Goal
Settle assessed rent through Economy V2 and record unpaid remainder as arrears.

### Required cases

- full payment;
- partial payment;
- zero liquidity;
- replay;
- cure next day.

---

## V5-05A — Corporation EARTH assessment

### Goal
Apply progressive EARTH capacity charge to each Corporation's total occupied
capacity and create daily assessment.

---

## V5-05B — Corporation → EARTH settlement

### Goal
Post payment to EARTH Treasury and create Corporation arrears when underfunded.

### Required read-model result
House-rent revenue, EARTH capacity expense, land margin, arrears.

---

## V5-06A — Automatic Territory-unit provisioning

### Goal
Ensure standardized capacity-container records match derived need without being
the billing authority.

### Critical behavior
Crossing 500→501 occupied units (or configured equivalent) may activate another
container but must not create a billing cliff.

---

## V5-07A — Normalize admission policy

### Goal
Make `OPEN`, `APPROVAL`, `INVITE_ONLY` the only V5 admission semantics.

### Must include
Migration mapping, server enum validation, client labels, tests.

---

## V5-07B — Invite tokens

### Goal
Implement server-generated Corporation invite tokens with expiry, max uses,
revocation, audit, idempotent redemption.

### Security
Store token hash where practical; never trust client Corporation/issuer claims.

---

## V5-07C — Corporation founding quote/command

### Goal
Replace name-only founding with quote → review → atomic creation.

### Quote
Founding fee/reserve, admission, House residential consequence, blockers.

### Mutation
Corporation/institution + accounts + founder affiliation + rules/history/outbox
in one transaction.

---

## V5-08A — EARTH progressive policy proposal

### Goal
Add governance target/payload for global capacity schedule/base rate.

### Must reject
Regressive schedule, invalid boundaries, retroactive effective date.

### Preview
Revenue/distribution/Treasury effects from server.

---

## V5-08B — Corporation House base-rate proposal

### Goal
Govern Corporation's one local capacity-price variable with fiscal preview.

---

## V5-09A — House delinquency state machine

### Goal
Formalize arrears/grace/expansion-blocked/suspension stages.

### Must not
Delete buildings on first missed payment.

---

## V5-09B — Productive suspension/release

### Goal
Stop production of suspended assets, later mothball/liquidate according to
priority, and release footprint only after authoritative state transition.

---

## V5-10A — Corporation distress/receivership

### Goal
Implement staged Corporation EARTH-rent distress while preserving House assets.

### Separate commits
Arrears/grace first; receivership second; dissolution last.

---

# 5. Economy/UI cleanup task packages

These should start only after the relevant authoritative V5/backend contracts
exist.

## V5-BLD

- delete Flutter fallback economics;
- use server construction/upgrade/research/demolition quotes;
- show capacity/rent delta;
- normalize lifecycle status;
- move civic construction to Corporation governance semantics.

## V5-TECH

- canonical blueprint/technology catalog DTO;
- remove fallback technology catalog/formulas;
- correct Corporation R&D funding/authorization;
- remove dead incremental funding UI;
- integrate eligible Buildings.

## V5-MKT

- last-clearing terminology;
- server clearing schedule;
- canonical available/reserved assets;
- one order ticket;
- fills/history;
- server fee/escrow preview.

## V5-FIN

- House Available to Spend;
- next settlement;
- capacity rent/arrears/upcoming obligations;
- activity ledger;
- safe loan quote/accept flow.

## V5-AUTO

- one automation config;
- correct player/internal unit boundaries;
- preview/history/pause;
- atomic scheduled save.

## V5-GOV

- Needs Your Attention;
- correct rule resolution;
- Review & Vote;
- progressive policy proposals;
- no Territory government scope.

## V5-OVR

- server OverviewSummary;
- no synthetic data/objectives;
- canonical Attention Queue;
- House-centric current state.

## V5-BRIEF

- DailySummaryV2;
- statement-driven credit/resource changes;
- rent/arrears;
- changes/directives/history.

## V5-NEWS

- server publication model;
- canonical scope/topic/importance;
- cursor chronology/deep links.

## V5-CORP-UI

- Corporation directory/profile;
- admission;
- Land & Capacity;
- base rent;
- fiscal health;
- technology;
- founding flow.

---

# 6. Required AI evidence before claiming a task complete

Every handoff must include:

1. exact behavior implemented;
2. exact files changed;
3. migration number(s), if any;
4. schema/manifest updates;
5. API routes/DTO changes;
6. ledger/history/outbox effects;
7. focused tests run and results;
8. full relevant gate results;
9. manual journey exercised;
10. commit hash;
11. known deferred work;
12. confirmation that no V5 target-only behavior was falsely described as
    production unless deployed/verified.

---

# 7. Required test gates

Use focused tests while developing, then repository-standard gates before
handoff. At minimum follow `AI_DEVELOPMENT_INSTRUCTIONS.md`.

For V5 economy/capacity work additionally require:

- canonical DB verification;
- invariant tests;
- progressive engine property tests;
- settlement replay test;
- ledger balance assertion;
- migration from production-shaped fixture;
- shadow/cutover comparison where applicable.

Before V5 production cutover, also require one monitored complete game-day tick.

---

# 8. What an AI must never do during V5 work

- Treat this documentation branch as evidence that V5 runtime already exists.
- Remove `territory_id`/`primary_territory_id` in an early phase just to make the
  schema look cleaner.
- Introduce another land pricing formula.
- Hard-code bracket numbers in Flutter.
- Make Territory a political institution again.
- Allow multiple active Corporations per House.
- Replace Corporation affiliation with generic Organization membership.
- Make Community a Corporation substitute.
- Make an inactive House free merely because the user did not log in.
- Auto-delete delinquent assets.
- Apply new fiscal rules retroactively.
- Post economic effects outside Economy V2.
- silently repair balances by assignment.
- claim a green widget test proves backend economic correctness.
