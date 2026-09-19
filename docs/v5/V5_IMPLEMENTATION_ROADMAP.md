# EARTH Gameplay V5 — Implementation Roadmap

Status: **IMPLEMENTATION HISTORY / REFERENCE**  
Version: 5.0-design

## 1. Purpose

This roadmap defines the order in which V5 must be implemented. The sequence is
intentional. Do not start with broad Flutter redesigns or delete V4 schema before
server authority, rule versioning, settlement, and migration safety are in place.

Every phase is a complete reviewable program increment. Within a phase, AI work
should be split into the smallest complete vertical slices described in
`V5_AI_EXECUTION_PLAYBOOK.md`.

---

# 2. Program rules

- V5 is now current; old phase/cutover wording below is retained only to explain implementation sequencing.
- PostgreSQL is authoritative.
- Schema changes are forward-only and update canonical schema/manifest.
- Existing history/ledger data is preserved.
- Consequential client actions use server quote/preview + explicit confirmation.
- New economic paths require idempotency, ledger/history/outbox, replay tests,
  and monitored settlement evidence.
- Flutter does not duplicate economic formulas.
- A phase can ship behind a disabled rule/feature gate where useful.
- Do not combine unrelated cleanup with a core economic cutover.

---

# PHASE V5-00 — Design, authority, and repository freeze

## Goal

Make V5 unambiguous to future humans and AI agents before changing runtime.

## Work

1. Review/accept V5 documentation pack.
2. Add/accept ADR-003.
3. Prepare Constitution amendment plan for:
   - removal of City as independent V5 governing layer;
   - Corporation as local polity/economic affiliation;
   - Territory as EARTH-owned physical capacity;
   - progressive marginal-bracket authority;
   - capacity-rent obligations and staged resolution.
4. Map V4/current runtime conflicts explicitly.
5. Keep `DOCUMENT_STATUS.md` aligned with V5 as the sole active gameplay authority.
6. Add V5 section to `AI_DEVELOPMENT_INSTRUCTIONS.md` telling agents to read the
   V5 pack for V5-labelled tasks.
7. Freeze naming:
   - `EARTH`
   - `Corporation`
   - `House`
   - `Human`
   - `Territory capacity`
   - `Community`
8. Decide exact initial canonical admission enums.
9. Decide which legacy terminology is compatibility-only.

## Deliverables

- accepted ADR/docs;
- conflict matrix;
- constitutional amendment PR or explicitly scheduled amendment phase;
- no production behavior change.

## Acceptance

- AI agent can identify current vs V5 target without ambiguity;
- no current document calls V5 already implemented;
- all V5 terms have one canonical meaning.

---

# PHASE V5-01 — Universal progressive policy engine

## Goal

Implement one deterministic marginal-bracket engine before any V5 rent/tax
feature depends on it.

## Backend work

1. Add pure progressive calculation module.
2. Add schedule/bracket schema + constraints.
3. Add schedule-version resolver by game day.
4. Add validators:
   - contiguous ordered ranges;
   - monotonic multipliers/rates;
   - no overlaps/gaps;
   - immutable active versions;
   - valid effective dates.
5. Seed inactive V5 target schedules for tests/staging.
6. Add query/read DTO for schedule explanation.
7. Add generic deterministic quote helper.

## Tests

- boundary tests;
- property-based monotonicity tests;
- huge quantity tests;
- one-bracket flat schedule;
- invalid schedule rejection;
- version/effective-date selection;
- exact-money/fixed-point tests.

## Expected result

EARTH has one reusable authority for every future progressive price/tax. No
capacity behavior is posted yet.

## Gate

No Phase 02 financial work until this engine is stable and covered.

---

# PHASE V5-02 — Canonical V5 capacity model and shadow projections

## Goal

Compute authoritative House and Corporation physical occupancy without changing
money yet.

## Schema/domain work

1. Add V5 capacity rule/version records:
   - standard Territory capacity;
   - EARTH base capacity rate reference;
   - progressive schedule references;
   - Corporation House base-rate rule/version.
2. Add/derive canonical House residential unit (`1` per active affiliated House).
3. Use `building_catalog.slot_footprint` as canonical building capacity usage.
4. Add Corporation occupancy aggregation service.
5. Add automatic required-Territory-container calculation.
6. Add V5 capacity statement/projection tables/read model if needed.
7. Backfill current runtime data in shadow mode.
8. Produce reconciliation report against current Territory/building state.

## Read APIs

Introduce server-authoritative read endpoints/models:

- House capacity summary;
- Corporation capacity summary;
- EARTH/world capacity summary.

## No financial posting yet

All rent/charge amounts are calculated as shadow estimates only.

## Tests

- one residential unit per active House;
- building footprint aggregation;
- destroyed building excluded;
- join/leave simulation;
- Territory container count at boundaries;
- deterministic backfill/re-run;
- Corporation total = included component sum.

## Expected result

The backend can answer exactly how much physical capacity every House and
Corporation uses under V5.

---

# PHASE V5-03 — Capacity quotes and mutation integration

## Goal

Make all commands that change physical occupancy aware of V5 consequences.

## Required command integrations

1. Corporation join/approve/invite acceptance.
2. Corporation leave/removal where allowed.
3. Private building construction.
4. Demolition/liquidation/release.
5. Footprint-changing upgrades/capital projects.
6. Public/institutional construction where billable.
7. Corporation founding.

## Quote model

Every relevant command should return/consume a server quote containing:

- current usage;
- delta;
- after usage;
- current/after House capacity charge;
- incremental House charge;
- Corporation occupancy impact;
- current relevant bracket(s);
- rule versions;
- eligibility/blockers;
- effective timing.

## Client impact

Only minimal UI integration is required in this phase: expose quotes in existing
flows. Do not perform full V5 page redesign yet.

## Tests

- quote equals actual state transition under same rule version;
- race/locking tests around capacity-changing commands;
- idempotent command replay;
- authorization;
- concurrent join/construction cases.

## Expected result

No capacity-changing command can execute without knowing exact V5 physical/fiscal
consequences.

---

# PHASE V5-04 — House capacity rent assessment and settlement

## Goal

Begin authoritative Corporation → House capacity billing.

## Work

1. Add Corporation House base-rate versioning/governance rule.
2. Add daily House capacity assessment.
3. Post House → Corporation CREDIT transfer through Economy V2.
4. Record assessment, payment, rule versions, and correlation.
5. Add partial payment/arrears integration.
6. Add House delinquency state machine hooks:
   - CURRENT;
   - ARREARS;
   - GRACE;
   - EXPANSION_BLOCKED;
   - productive suspension candidate;
   - later liquidation/release.
7. Add daily statement/Finance transaction visibility.
8. Add settlement replay/idempotency protection.

## Important

Do not immediately implement harsh final liquidation if existing insolvency
framework can first support arrears/grace safely. Separate final resolution into
a focused slice.

## Tests

- exact progressive assessment;
- insufficient funds;
- partial payment;
- arrears aging;
- next-day cure;
- multiple Houses;
- replay;
- ledger balance;
- no negative normal account balance;
- join on effective day;
- building constructed/demolished around settlement boundary.

## Expected result

Every House pays a real daily price for one residence + productive footprint,
with increasing marginal cost for large estates.

---

# PHASE V5-05 — Corporation EARTH capacity rent and EARTH Treasury

## Goal

Complete the second level: Corporation → EARTH progressive capacity billing.

## Work

1. Add/version EARTH base capacity rate.
2. Calculate Corporation total occupied capacity daily.
3. Assess progressive EARTH capacity charge.
4. Post Corporation → EARTH Treasury transfer.
5. Record assessment/payment/rule versions.
6. Add Corporation arrears state.
7. Add grace/restriction hooks.
8. Add EARTH receivership primitives only where clearly specified/tested.
9. Expose Corporation land margin:
   - House capacity-rent revenue;
   - EARTH capacity expense;
   - net land/capacity margin.
10. Expose EARTH total capacity revenue.

## Tests

- small/medium/large Corporation brackets;
- Corporation with many inactive-but-valid Houses;
- bankrupt/non-paying Houses and Corporation exposure;
- Corporation insufficient Treasury;
- arrears/recovery;
- multiple Corporation aggregation;
- ledger balance/replay.

## Expected result

EARTH now has a real fiscal role funded partly by the physical capacity used by
Corporations.

---

# PHASE V5-06 — Automatic Territory container lifecycle

## Goal

Make Territory units fully automatic accounting/capacity containers.

## Work

1. Define standard Territory unit record semantics.
2. On occupancy growth, ensure enough active standardized units exist.
3. On sustained occupancy decline, allow safe retirement/surrender of excess
   empty standardized units where desired.
4. Preserve activation/retirement history.
5. Ensure no House/building movement is required between identical containers.
6. Remove manual routine Territory-create/acquire flows from active V5 gameplay.
7. Ensure container count itself is not the billing basis.

## Tests

- exact `capacity-1`, `capacity`, `capacity+1` boundaries;
- growth to many containers;
- deterministic IDs/sequence;
- downsize without assigned-building migration;
- no billing discontinuity at container boundary.

## Expected result

Territory expansion no longer requires player/governance administration.

---

# PHASE V5-07 — Corporation membership and founding V5

## Goal

Make Corporation the clear single local affiliation and finalize admission.

## Admission

Implement exactly:

- `OPEN`;
- `APPROVAL`;
- `INVITE_ONLY`.

## Work

1. Normalize/migrate legacy admission values.
2. Add membership applications with explicit status/history.
3. Add invite tokens:
   - secure random server token;
   - expiry;
   - use limit;
   - issuer/Corporation;
   - revocation;
   - audit.
4. Add membership consequence preview.
5. Enforce one active Corporation per House.
6. Build founding quote + atomic founding transaction.
7. Define leaving/switching consequences and transition period.
8. Remove any V5 flow that treats generic multi-Organization membership as
   Corporation affiliation.

## Tests

- open join;
- approval apply/approve/reject;
- invite expiry/use count/replay;
- one-active-affiliation constraint;
- simultaneous join attempts;
- founding rollback/no partial institution;
- capacity/rent consequences.

## Expected result

Corporation affiliation is coherent, safe, and economically connected to V5
capacity.

---

# PHASE V5-08 — Progressive governance proposals and previews

## Goal

Allow lawful player governance over V5 rates without letting clients invent
financial consequences.

## EARTH proposal types

At minimum:

- EARTH base capacity rate amendment;
- progressive schedule amendment;
- related constitutional/global fiscal policy where authorized.

## Corporation proposal types

At minimum:

- House base capacity rate amendment;
- admission policy amendment where governance-owned;
- related tax/budget rules.

## Work

1. Define proposal target/payload schemas.
2. Add server validators.
3. Add canonical financial/distribution previews.
4. Require future effective game day.
5. Record immutable approved rule version.
6. Update Governance UI to Review → Vote.
7. Show turnout/quorum/decisive approval correctly.

## Tests

- invalid regressive bracket rejected;
- retroactive date rejected;
- proposal preview matches activated rule;
- governance authorization;
- rule activation at correct day;
- rejected/no-quorum leaves active rule unchanged.

## Expected result

Land/capacity pricing becomes a transparent player-governed economic system.

---

# PHASE V5-09 — House delinquency, suspension, and capacity release

## Goal

Complete the lifecycle of non-paying House capacity without destroying the House
on the first missed payment.

## Work

1. Formalize arrears aging and cure.
2. Block new capacity after configured delinquency stage.
3. Define productive suspension ordering.
4. Suspend production without destroying ownership/history.
5. Add mothball/liquidation process for prolonged default.
6. Apply liquidation proceeds by lawful priority.
7. Release footprint only when asset/right state changes.
8. Protect residential/House continuity according to Constitution/lifecycle
   rules.
9. Surface all states in Finance/Daily Briefing/Buildings.

## Tests

- missed one day/cure next day;
- prolonged default;
- suspension stops production;
- liquidation releases correct capacity;
- arrears priority;
- no accidental House deletion;
- inactive-but-solvent House remains valid.

---

# PHASE V5-10 — Corporation default and EARTH receivership

## Goal

Create predictable consequences when a Corporation cannot meet EARTH capacity
obligations.

## Work

1. Corporation arrears aging.
2. Grace/warnings.
3. Restrict optional expansion/discretionary spending at configured stages.
4. Add lawful receivership/revenue interception mechanics.
5. Define restructuring plan/action(s).
6. Define dissolution as last resort.
7. Preserve House assets during Corporation distress.
8. Define temporary transition/admin behavior if Corporation dissolves.
9. Expose distress clearly to members/directory.

## Tests

- underfunded Corporation;
- recovery before receivership;
- receivership transfer priority;
- no duplicate collection;
- dissolution preserves history/assets;
- multiple delinquent Corporations do not break EARTH settlement.

---

# PHASE V5-11 — Economy authority cleanup: Buildings and Technology

## Goal

Remove current client-side duplicated economy formulas and align productive
progression with V5 capacity.

## Buildings

- server-authoritative construction quote;
- complete resource affordability;
- capacity/rent impact preview;
- authoritative upgrade/demolition/policy preview;
- explicit lifecycle states;
- group/batch operations where needed.

## Technology

- delete client fallback blueprint catalog/formulas;
- canonical technology/blueprint read DTO;
- authoritative research quote/effects/duration;
- Corporation funding authority aligned with backend;
- remove dead incremental funding mechanics;
- Research → Unlock → Deploy semantics.

## Expected result

Land scarcity and technology productivity work together: higher tiers/generations
can improve value per scarce capacity unit.

---

# PHASE V5-12 — Economy authority cleanup: Market, Finance, Automation

## Market

- last clearing semantics;
- server clearing schedule;
- canonical available/reserved balances;
- one order ticket;
- server fee/escrow preview;
- fills/history;
- resource-key normalization.

## Finance

- canonical Available to Spend;
- canonical Next Settlement;
- capacity rent/arrears/upcoming obligations;
- Activity ledger;
- safe loan quote/review/accept.

## Automation

- one canonical House automation config;
- correct fixed-point units;
- daily spend-cap allocation;
- current/scheduled policy lifecycle;
- server Next Run Preview;
- history/pause controls.

## Expected result

All major House economic surfaces explain one backend economy instead of
reconstructing it independently.

---

# PHASE V5-13 — Command read models: Overview, Daily Briefing, News

## Goal

Make the Command group trustworthy and decision-oriented.

## Overview

- one canonical OverviewSummary;
- House-centric current state;
- server Attention Queue;
- no synthetic objectives/resource values;
- compact last-day strip.

## Daily Briefing

- canonical DailySummaryV2;
- daily statement as authority;
- credit/resource changes;
- capacity rent and arrears;
- structured changes/directives;
- historical day navigation.

## News

- server-owned News read model;
- explicit publication rules;
- scope + topic + importance;
- chronology/cursor pagination;
- story detail/deep links.

---

# PHASE V5-14 — Society/UI restructuring

## Goal

Reflect the final V5 world model in navigation and pages.

Key changes:

- Corporation pages become central to local institution/capacity economics;
- move `Land & Capacity` into My Corporation/profile;
- remove/repurpose standalone Territories management page;
- keep Communities voluntary/multi-membership;
- Governance shows EARTH + Corporation scopes, not a full third Territory
  government tier;
- Directory/profile shows admission, base rent, capacity use, fiscal health,
  technology, and relevant taxes;
- standardize vocabulary and remove City/legacy wording.

Detailed page matrix: `V5_UI_MIGRATION_MATRIX.md`.

---

# PHASE V5-15 — Shadow economy simulation and balancing

## Goal

Prove V5 can sustain different player strategies before declaring balance
stable.

## Simulation cohorts

At minimum:

### Houses

- residence-only/new House;
- small 2–4 slot House;
- medium 8–16 slot House;
- large industrial House;
- high-tech/high-productivity House;
- inactive but solvent House;
- inactive insolvent House;
- leveraged/debt-heavy House.

### Corporations

- small approval-based Corporation;
- fast-growth open Corporation;
- private invite-only Corporation;
- low base rent/high tax;
- high base rent/low tax;
- technology-heavy spender;
- underfunded Corporation;
- mega-Corporation crossing many brackets.

### EARTH policies

- low base rate;
- high base rate;
- shallow progression;
- steep progression;
- low-revenue EARTH policy;
- high global-program spending.

## Metrics

- House survival/wealth distribution;
- Corporation concentration;
- capacity utilization;
- EARTH revenue/reserve runway;
- Corporation land margin;
- delinquency rates;
- Market prices/liquidity;
- technology adoption;
- new-Corporation formation incentives;
- effect of inactivity.

## Expected result

Identify balance parameters without changing fundamental V5 architecture.

---

# PHASE V5-16 — Cutover rehearsal

## Goal

Prove migration and settlement in an environment mirroring production.

## Required rehearsal

1. backup/restore drill;
2. migrate production-shaped dataset;
3. backfill V5 capacity;
4. shadow settlement for multiple days;
5. compare expected/actual ledger totals;
6. run full API/Flutter suite;
7. exercise Corporation join/found/build/default flows;
8. verify real-time/read-model refresh;
9. validate rollback/rule-gate strategy;
10. produce signed cutover report.

No production cutover without successful rehearsal.

---

# PHASE V5-17 — Production cutover

## Goal

Switch current gameplay authority to V5 safely.

## Cutover steps

1. deploy schema/code with V5 path disabled where appropriate;
2. run migration/backfill and reconciliation;
3. activate V5 rule versions at planned game-day boundary;
4. enable House capacity assessment;
5. enable Corporation EARTH assessment;
6. switch read models/client;
7. monitor complete settlement day;
8. verify ledger, arrears, occupancy, Territory count, Treasury flows;
9. verify gameplay journeys manually;
10. update `DOCUMENT_STATUS.md` and `CURRENT_STATE.md` to mark V5 current only
    after evidence is complete.

---

# PHASE V5-18 — Post-cutover cleanup

Only after usage/evidence proves compatibility structures are dead:

- archive V4-only routes/read models;
- remove client fallback formulas;
- remove obsolete Territory-government UI;
- remove old City compatibility paths;
- consider deprecating/dropping `primary_territory_id`;
- consider making/removing `buildings.territory_id` as appropriate;
- archive superseded V4 target docs without destroying historical record;
- update file map/AI instructions;
- run final canonical schema rebaseline if project policy calls for it.

Do not combine cleanup with the initial financial cutover.

---

# 3. Dependency summary

```text
V5-00 Documentation/authority
        ↓
V5-01 Progressive engine
        ↓
V5-02 Capacity model (shadow)
        ↓
V5-03 Mutation quotes
        ↓
V5-04 House rent
        ↓
V5-05 Corporation→EARTH rent
        ↓
V5-06 Territory auto-containers
        ↓
V5-07 Membership/founding
        ↓
V5-08 Governance policy
        ↓
V5-09/10 Resolution
        ↓
V5-11/12 Economy surface cleanup
        ↓
V5-13 Command read models
        ↓
V5-14 Society/UI restructuring
        ↓
V5-15 Simulation/balance
        ↓
V5-16 Rehearsal
        ↓
V5-17 Cutover
        ↓
V5-18 Cleanup
```

Parallel work is allowed only where authority dependencies do not conflict. For
example, design-system-only UI cleanup may run in parallel, but a page must not
invent final V5 data before its read model exists.

---

# 4. Definition of program done

V5 is complete only when:

- V5 is marked current in repository status docs;
- no production economic path depends on V4 Territory political semantics;
- capacity assessment is authoritative and audited;
- progressive policy is governance-controlled and versioned;
- every House/Corporation financial consequence appears in ledger/statements;
- arrears/resolution paths are live and tested;
- affected Flutter screens consume server values without fake fallback economics;
- V5 navigation/vocabulary is consistent;
- migration/replay/full test/smoke/monitored game-day evidence exists;
- known deferred V5+ features are explicitly documented rather than half-built.
