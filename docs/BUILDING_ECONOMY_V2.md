# EARTH Building Economy V2

## Plan 1: authority boundary and overlap audit

Building settlement is being migrated in dependency order. During the
transition, the durable authority for value is Economy V2:

- `economic_accounts` holds live balances.
- `settlement_effects` is disposable calculation state.
- `economic_transactions` and `economic_entries` are durable postings.
- `building_settlement_journals` records gameplay explanation and outcome.

The generic `daily_settlement_profiles` path and the building settlement path
must not both apply the same building effect. Until the later planner and
profile-cutover plans are complete, `earth_building_v2_integrity()` reports
profile/building overlap risk, effects without building provenance, and
journal/effect mismatches. A non-zero overlap-risk result is expected for
transitional data and is a cutover blocker, not a reason to suppress the
diagnostic.

Building catalog economics are descriptive inputs until the canonical planner
and posting phases are complete. `output_credits` must not be treated as money
creation; service revenue requires a funded customer transfer in a later plan.

The authority boundary is:

> Buildings describe production, consumption, service capacity and condition;
> only Economy V2 posting primitives may mutate economic balances.

The V2 settlement journal is an audit/read model, not an authority. It records
the plan's requested, allocated and consumed inputs, atomic-unit production,
service delivery and revenue, operating costs, wear, repairs, condition and
operational state transitions, together with the posted economic batch and
correlation ID. It is written from staged settlement data so the explanation
can be reproduced without using the journal as a balance source.

Fixed-point settlement values use integer atomic units, PPM ratios and basis
point condition values. The older decimal plan inputs remain only as a
temporary compatibility surface for the preceding migrations; generated
fixed-point columns are the canonical values for V2 posting and reconciliation.

Building economics are selected from `building_economic_rule_versions` by
`effective_from_game_day`/`effective_to_game_day`. Production recipes, upkeep,
condition curves and decay, repair costs, service capacity/pricing, and service
matching behavior therefore remain pinned to the rules that applied on the
settled day, even when the scheduler is catching up or replaying history.

The former `building-settlement-engine.ts` has been deleted. The production
scheduler and all active building callers use `building-settlement-v2.ts`.
Shared accounting adapters remain only where their owning subsystem has not
completed its Economy V2 cutover.

Generic `daily_settlement_profiles` are explicitly non-building profiles. They
must not carry building production, upkeep, service, repair, or other building
economic deltas; those effects belong exclusively to the Building V2 planner
and economic batch. `earth_building_profile_overlap_integrity()` reports any
nonzero generic profile or source observed in both posting paths.

## Canonical daily settlement pipeline

Building V2 uses one ordered pipeline for each eligible owner shard. The
calculation stages do not mutate authoritative balances or building state:

1. select eligible buildings;
2. resolve rules/catalog versions for the settlement day;
3. snapshot owner inputs;
4. calculate requirements;
5. allocate constrained owner resources;
6. calculate input utilization;
7. calculate start-of-day condition efficiency;
8. calculate physical consumption;
9. calculate physical production;
10. calculate service capacity;
11. match service demand;
12. calculate customer-funded revenue;
13. resolve explicit operating expenses;
14. calculate operational wear;
15. allocate repair resources;
16. calculate repair points;
17. calculate end-of-day condition and status;
18. compile Economy V2 effects;
19. validate conservation and non-negative results;
20. atomically post the settlement batch;
21. set-wise update building condition/status;
22. set-wise insert settlement journals;
23. complete building/day idempotency keys.

The machine-readable ordering is maintained in
`cloudflare/src/building-settlement-pipeline.ts`. Posting must precede building
state, journal, and idempotency completion.
