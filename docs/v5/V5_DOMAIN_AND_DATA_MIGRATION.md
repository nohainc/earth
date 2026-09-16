# EARTH Gameplay V5 — Domain and Data Migration Plan

Status: **TARGET-CANONICAL MIGRATION PLAN / NOT YET EXECUTED**  
Version: 5.0-design

## 1. Purpose

This document maps the current repository/runtime model to the V5 target model.
It is intentionally migration-first: no AI agent should delete or repurpose
current Territory/Corporation data merely because V5 no longer exposes the same
relationship to players.

All schema changes are forward-only migrations. Existing economic, governance,
ownership, and world-history records must remain auditable.

---

# 2. Current baseline facts relevant to V5

At the time this V5 pack was authored, the clean baseline contains:

- `institutions` with kinds including `EARTH`, `CORPORATION`, and `BANK`;
- `corporations` as institution-backed records;
- `territories` with `corporation_id`, `is_primary`, type/status/name;
- one-active-primary-Territory index per Corporation;
- `house_affiliations` with one active Corporation affiliation per House and an
  optional `primary_territory_id`;
- `territory_capacity_state` containing House/population/private/public/service
  capacity fields per specific Territory;
- `buildings.territory_id` as a required relationship;
- `building_catalog.slot_footprint` as a canonical footprint field;
- Economy V2 accounts/transactions/entries as authoritative economic state.

These facts are current implementation evidence, not V5 target semantics.

---

# 3. Target conceptual model

V5 requires these canonical relationships:

```text
House
  └── 0..1 active Corporation affiliation

Corporation
  ├── pooled occupied physical capacity
  ├── automatically derived standardized Territory-unit count
  ├── base House capacity rate
  └── EARTH capacity obligation

House capacity usage
  = 1 residential unit
  + billable building footprints

Building
  └── Corporation/House capacity consumption
      (no gameplay requirement for specific standardized Territory unit)
```

Individual Territory records may remain as capacity-container/audit/history
records. They cease to be the player's residency/governance choice while they
are standardized and identical.

---

# 4. Migration principles

1. **Do not drop historical Territory records.**
2. **Do not rewrite historical building ownership/events.**
3. **Do not break old event/audit references.**
4. New canonical V5 fields/tables are introduced first; old fields become
   compatibility projections before optional later archival.
5. Settlement/read models cut over only after shadow verification.
6. Flutter changes happen after authoritative backend read models exist.
7. No destructive “rename everything in one migration.”
8. Every financial migration preserves balanced ledger history.
9. Every current rule/version remains immutable for game days already settled.
10. Backfill operations must be deterministic and resumable.

---

# 5. Proposed V5 data concepts

Exact names may change during implementation review, but semantics should remain.

## 5.1 Progressive policy schedules

Recommended new canonical tables/concepts:

```text
progressive_policy_schedules
- id
- code
- basis_type
- authority_institution_id
- version
- status
- effective_from_game_day
- effective_to_game_day
- created_by
- created_at

progressive_policy_brackets
- schedule_id
- ordinal
- lower_bound_units
- upper_bound_units NULL for open-ended
- marginal_multiplier_numerator/denominator OR exact numeric
- optional marginal_rate_bps for tax schedules
```

Alternatively use one JSONB rule record only if constraints/queries/tests remain
strong enough. Relational brackets are preferred because PostgreSQL can enforce
ordering/invariants more safely.

Required basis types initially:

- `EARTH_CORPORATION_CAPACITY`
- `CORPORATION_HOUSE_CAPACITY`

Future:

- `HOUSE_INCOME_TAX`
- other explicitly authorized progressive taxes.

## 5.2 Capacity policy/rates

Versioned EARTH rule fields/concepts:

```text
standard_territory_capacity_units
earth_base_capacity_rate_units
earth_corporation_progressive_schedule_id
earth_house_progressive_schedule_id
```

Corporation versioned rule:

```text
house_base_capacity_rate_units
```

Do not store a single mutable unversioned rate if governance changes it over
history.

## 5.3 Corporation capacity projection/state

Recommended canonical/projection concept:

```text
corporation_capacity_state
- corporation_id
- game_day
- residential_units_used
- private_building_units_used
- public_units_used
- total_occupied_units
- standard_territory_units_required
- earth_capacity_assessment_units
- earth_capacity_arrears_units
- rules_version / policy references
- updated_at
```

Whether this is a durable daily statement/projection or rebuilt from canonical
facts should follow the current architecture. It must not become an independent
balance authority.

## 5.4 House capacity statement/state

Recommended read/statement concept:

```text
house_capacity_statement
- house_id
- corporation_id
- game_day
- residential_units
- building_units
- total_units
- base_rate_units
- progressive_schedule_id
- assessed_rent_units
- paid_rent_units
- arrears_units
- delinquency_status
```

Daily immutable statements are preferred for audit and Daily Briefing.

## 5.5 Territory capacity-container record

Current `territories` may be evolved rather than replaced immediately.

Target semantics for standardized V5 containers:

```text
territories / territory_capacity_grants
- id
- corporation_id
- sequence_number
- status
- capacity_units
- activated_game_day
- retired_game_day
- definition/rules version
```

Names/geographic fields may remain for compatibility but should not imply each
House/building lives in a chosen numbered Territory.

---

# 6. Current field treatment

## `house_affiliations.primary_territory_id`

V5 target: not required for gameplay.

Migration strategy:

1. Keep field during transition.
2. Stop requiring/populating it for new V5 commands after compatibility read
   paths are updated.
3. Read models must derive Corporation affiliation directly.
4. Historical value remains queryable for pre-V5 history.
5. Later migration may make it explicitly legacy/deprecated or move historical
   location semantics to an event/history table.
6. Do not drop until no production caller/test/read model depends on it.

## `buildings.territory_id`

V5 target: no specific standardized Territory unit required.

Migration options, preferred order:

### Preferred transitional approach

- keep `territory_id` for compatibility;
- add/ensure unambiguous `corporation_id` derivation through House affiliation/
  owner scope in authoritative commands;
- assign a deterministic compatibility Territory container where existing
  constraints require it;
- remove all gameplay calculations that depend on the specific ID;
- later make `territory_id` nullable or move placement to an optional
  differentiated-location relation only when safe.

### Do not

- mass-move every building and rewrite historical events;
- reuse `territory_id` to mean Corporation ID;
- invent random Territory assignment.

## `territory_capacity_state`

Current table mixes multiple spatial/service concepts.

V5 treatment:

- identify which fields remain real gameplay (private/public capacity, service
  capacity, infrastructure) and which are V4-specific projections;
- aggregate standardized physical capacity at Corporation level for V5 billing;
- preserve service/infrastructure data only if still part of active gameplay;
- do not use per-Territory `active_house_count` as the basis of V5 occupancy.

---

# 7. Owner/economic account changes

No new balance authority is needed.

Existing Economy V2 owner/account model should remain authoritative.

Required V5 account/policy concepts may include:

```text
EARTH Treasury / capacity revenue account
Corporation Treasury / capacity revenue account
Corporation capacity arrears/obligation representation
House capacity arrears/obligation representation
```

Prefer the existing obligation/ledger architecture over ad-hoc balance fields.

Every capacity payment is a normal Economy V2 transfer.

---

# 8. Corporation membership migration

Current baseline already enforces one active `house_affiliations` row per House.
That aligns well with V5.

Required changes:

- freeze Corporation as the canonical single local affiliation;
- do not treat generic multi-Organization membership as a substitute for
  Corporation affiliation in V5 gameplay;
- keep Communities as separate many-to-many voluntary associations;
- normalize admission values to `OPEN`, `APPROVAL`, `INVITE_ONLY`;
- migrate legacy values such as request/invite/closed variants through an
  explicit mapping, not UI guessing;
- add invite-token persistence and application state where missing;
- join/leave commands must quote capacity/fiscal effects where required.

---

# 9. Corporation founding migration

Current Corporation creation flows must be replaced/extended by a canonical V5
founding command.

Target command semantics:

```text
POST /api/corporations/founding/quote
POST /api/corporations
```

Quote should include:

- founder eligibility;
- Corporation name availability;
- admission policy;
- founding fee;
- initial Treasury reserve requirement;
- initial House residential capacity/rent consequences;
- current EARTH capacity rules;
- blockers;
- effective date.

Creation is one idempotent transaction creating institution/Corporation,
founding membership, required accounts/rules/history/outbox records.

No separate manual first-Territory purchase is required; standardized capacity
containers are derived from occupancy.

---

# 10. Capacity mutation sources

The implementation must maintain one authoritative list of events/commands that
change capacity.

At minimum:

### Increase

- Corporation membership becomes active: `+1 residential`;
- private building construction becomes billable/active according to rule;
- public/institutional building becomes billable;
- footprint-increasing upgrade/capital project becomes effective.

### Decrease

- building footprint is lawfully released after demolition/liquidation;
- membership ends and residential capacity is released after transition rules;
- public asset retired/released;
- footprint-reducing authoritative transformation.

Capacity should not be edited directly by UI/admin convenience fields.

---

# 11. Settlement migration

V5 capacity settlement should be added as explicit resumable settlement work.

Recommended target ordering is documented in the implementation roadmap, but
migration must support shadow execution first:

1. calculate House capacity usage/assessment without posting transfers;
2. compare against expected fixtures/current model;
3. calculate Corporation aggregate occupancy/EARTH assessment;
4. verify totals and bracket invariants;
5. enable ledger posting behind feature/rule gate;
6. switch read models/UI;
7. remove old Territory rent paths after monitored days.

Every daily assessment must identify rule versions and game day.

---

# 12. Read-model migration

New V5 read models should be introduced before removing current fields.

Required read models include:

## House capacity summary

```text
residentialUnits
buildingUnits
totalUnits
currentDailyCharge
nextMarginalUnitCharge
currentBracket
baseRate
scheduleVersion
arrears/status
```

## Corporation land/capacity summary

```text
memberCount
occupiedCapacity
standardTerritoryCapacity
requiredTerritoryUnits
utilizationPercent
houseCapacityRevenue
EARTHCapacityExpense
landMargin
baseHouseRate
progressiveScheduleSummary
arrears/status
```

## EARTH capacity/fiscal summary

```text
worldOccupiedCapacity
activeCorporations
EARTHCapacityRevenue
Treasury balance/reserves
global program commitments
current base rate
current progressive policy
```

Flutter must consume these instead of assembling totals from mixed world-state
maps.

---

# 13. API migration strategy

Use additive/versioned contracts during migration.

Suggested sequence:

1. introduce new quote/read endpoints;
2. update mutation endpoints to return V5 consequences;
3. migrate Flutter callers;
4. instrument legacy endpoint usage;
5. remove/redirect legacy semantics only when usage reaches zero and tests prove
   cutover.

Do not make one endpoint return different semantic meanings under the same field
name without versioning/documentation.

---

# 14. Governance migration

Current governance remains useful but V5 needs explicit policy categories/types.

New categories should cover:

- EARTH base capacity rate;
- EARTH progressive schedule;
- Corporation House base capacity rate;
- Corporation admission policy if governed;
- related fiscal rules.

Proposal effects are previewed from canonical policy services; proposal UI must
not hard-code outcomes.

Old Territory-government proposal categories should be deprecated where they
represent a removed third governance layer.

---

# 15. Constitution/document migration

V5 implementation cannot cut over while current canonical docs still require
contradictory City/V4 rules.

Phase 0 must prepare reviewed amendments to at least:

- `CONSTITUTION.md` (remove/replace City authority clauses and align Corporation
  role where necessary);
- `CONSTITUTION_COMPLIANCE.md`;
- `ADR-002-canonical-world-vocabulary.md` only if wording needs clarification;
- `V4_DOMAIN_MODEL.md` / `V4_TARGET_ARCHITECTURE.md` status (superseded after
  cutover, not silently edited as history);
- `DOCUMENT_STATUS.md`;
- `CURRENT_STATE.md` at actual cutover.

The V5 target docs do not themselves change current runtime authority.

---

# 16. Migration/backfill plan

A production-safe backfill should be resumable and reportable.

Suggested steps:

1. Snapshot counts/checksums of Houses, active affiliations, buildings,
   territories, economic accounts, and current capacity state.
2. Introduce V5 rule/schedule tables and seed inactive target versions.
3. Backfill each active House as `1` residential unit.
4. Backfill building footprint usage from canonical `building_catalog.slot_footprint`.
5. Aggregate Corporation occupancy.
6. Calculate required standardized Territory count.
7. Map/create missing capacity-container records deterministically if needed.
8. Produce reconciliation report:
   - Houses counted;
   - building footprints counted;
   - Corporation totals;
   - current per-Territory totals vs new pooled totals;
   - discrepancies requiring manual resolution.
9. Do not post economic charges during historical backfill unless a separate
   approved migration explicitly defines historical obligations.
10. Activate V5 rule versions only at future cutover game day.

---

# 17. Rollback philosophy

Schema migrations are forward-only, but gameplay cutover must be reversible at
the rule/read-path level during the controlled rollout.

Before financial posting cutover:

- V5 calculations may run in shadow mode;
- feature/rule gate determines which assessment posts;
- old and new outputs are compared.

After V5 charges post for a game day, never delete/rewrite the economic
transactions. Correct errors through compensating transactions/rules according
to existing Economy V2 policy.

---

# 18. Required migration verification

Before enabling V5 economic posting:

- every active affiliated House contributes exactly one residential unit;
- every billable building contributes exactly its canonical footprint;
- no destroyed/released building contributes active footprint;
- Corporation totals equal sum of included House/public units;
- required Territory-unit count matches `ceil(total / standard capacity)`;
- no House has more than one active Corporation affiliation;
- progressive policy schedules pass invariants;
- quote calculation equals shadow settlement calculation;
- no Flutter/read-model path depends on fake primary-Territory identity for
  gameplay decisions;
- current economic ledger remains balanced;
- replay of a V5 assessment is idempotent;
- migration and canonical schema/manifest checks pass.

---

# 19. Deferred cleanup

Do not combine these with the first working V5 cutover unless necessary:

- physically dropping `primary_territory_id`;
- physically dropping `buildings.territory_id`;
- renaming all historical City/Territory columns;
- reworking old event payloads;
- adding planetary/differentiated geography;
- consolidating every legacy Organization table.

First make V5 behavior correct and authoritative. Then remove confirmed dead
compatibility structures in separate reviewed migrations.
