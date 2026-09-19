# ADR-003: V5 Corporation and Territory Capacity Model

- Status: **Accepted / current V5 authority**
- Date: 2026-09-16
- Owners: EARTH product and engineering
- Scope: Gameplay V5 hierarchy, Corporation affiliation, Territory ownership/capacity, land charges, admission, insolvency
- Runtime effect: **Current V5 domain authority**

## Decision

Gameplay V5 adopts the following institutional and physical model:

1. **EARTH UC is the ultimate owner/authority over all standardized Territory capacity.**
2. **Corporation is the single local political/economic institution relevant to a House.**
3. A House may have **zero or one active Corporation affiliation**.
4. Territory is a **physical capacity concept**, not a government, tax authority,
   constitution, political membership, or independent economic owner.
5. Every active House consumes **one residential capacity unit**.
6. Every private/public building consumes additional capacity according to its
   canonical footprint.
7. Corporation Territory capacity auto-scales from actual occupied capacity.
   There is no routine player/governance action to create an identical Territory.
8. While Territory units are standardized and identical, Houses and buildings
   are **not assigned to a specific Territory unit**. They consume pooled
   Corporation capacity.
9. EARTH charges Corporations for actual occupied capacity through a universal
   marginal progressive bracket engine.
10. Corporations charge Houses for residential + private building capacity
    through the same universal marginal progressive engine.
11. EARTH governance controls the global progressive schedule and EARTH base
    capacity/Territory rate. Corporation governance controls only the local
    House base capacity rate and permitted Corporation-level fiscal rules.
12. Corporation admission supports exactly `OPEN`, `APPROVAL`, and
    `INVITE_ONLY`. `APPROVAL` is the recommended default.
13. Territory/capacity obligations are mandatory while capacity remains
    occupied. Delinquency creates arrears and staged resolution; it does not
    immediately delete Houses, Corporations, buildings, or history.
14. The global Market remains cross-Corporation.

## Why this model

The previous City/Corporation hierarchy created multiple overlapping political,
tax, budget, and constitutional layers. A later V4 direction separated
Territory, Organization, House, and residency more aggressively, but created a
potentially expensive many-to-many spatial model in which every House/building
could carry a Territory identity despite standardized Territory units.

V5 keeps the valuable distinctions while removing unnecessary player-facing
complexity:

- **EARTH**: global rules, Treasury, central systems, progressive policy.
- **Corporation**: local polity/economy, membership, governance, Treasury,
  taxation, technology, public spending.
- **Territory**: scarce standardized physical capacity.
- **House**: persistent private owner and player economic principal.
- **Human**: current mortal representative.

This prevents V5 from recreating a three-government hierarchy while still
making land/capacity economically meaningful.

## Authority and ownership

### EARTH

EARTH owns/controls the underlying physical capacity and may charge lawful,
versioned Corporation Territory/capacity rent. Revenue belongs to the EARTH
Treasury and may fund global programs. Low revenue is valid gameplay and may
make discretionary EARTH programs unavailable or delayed; core game-engine
functionality must never depend on discretionary Treasury solvency.

### Corporation

Corporation has jurisdiction over its members and local fiscal/technology/public
programs. It consumes pooled Territory capacity equal to its members'
residential units plus eligible public/private footprints. It pays EARTH for
that occupied capacity.

### House

A House consumes one residential capacity unit from the moment its Corporation
affiliation becomes active. Its buildings consume more units. It pays the
Corporation for total occupied capacity according to the local base rate and
global progressive schedule.

### Territory

Territory is not a sovereign layer. In V5 launch semantics:

- no Territory constitution;
- no Territory tax authority;
- no mayor/governor office;
- no Territory political membership;
- no independent Territory treasury required for authority;
- no per-House Territory residency selection;
- no building-to-specific-standard-Territory assignment.

A lightweight Territory/lease record may remain for accounting, audit,
history, future differentiation, and capacity container identity.

## Progressive charging

V5 uses a single universal **marginal bracket algorithm** for progressive prices
and taxes. Entering a higher bracket affects only usage inside that bracket.
Earlier usage is never repriced at the higher marginal rate.

This ADR intentionally does not freeze balance numbers. Brackets, rates, and
capacity sizes are versioned rule/catalog parameters.

## Automatic physical expansion

Required standardized Territory units are derived from actual occupancy:

```text
required_territory_units = ceil(occupied_capacity / standard_territory_capacity)
```

A Corporation does not vote every time an identical capacity container is
needed. The economic cost changes automatically as occupied capacity grows.

This does **not** mean capacity is free or infinite. Higher total usage enters
higher progressive marginal ranges. Very large Houses and Corporations can
continue to grow, but face increasing marginal land/capacity cost.

## Admission

Corporation members control who may join through one of three policies:

- `OPEN` — eligible House joins immediately;
- `APPROVAL` — application requires authorized approval/governance;
- `INVITE_ONLY` — valid server-side invite token is required.

Invite tokens may be time-limited and use-limited. The invite mechanism is an
implementation detail; `INVITE_ONLY` is the gameplay policy.

Joining increases occupied Corporation capacity by one residential unit but
never requires a manual Territory expansion vote.

## Delinquency and resolution

### House

Non-payment follows staged resolution:

1. arrears recorded;
2. grace period;
3. new capacity acquisition blocked;
4. productive capacity/buildings may be suspended;
5. prolonged default may trigger mothball/liquidation and release productive
   capacity;
6. the residential/House continuity rule is handled separately and must not be
   silently destroyed by a normal missed payment.

### Corporation

Corporation non-payment to EARTH follows:

1. arrears;
2. grace/warning;
3. spending/expansion restrictions where configured;
4. EARTH receivership/revenue interception where authorized;
5. restructuring;
6. dissolution only through explicit resolution rules preserving history and
   protecting House assets from instant deletion.

## Relationship to historical pre-V5 documents

This ADR supersedes important pre-V5 assumptions. In particular:

- V4 describes Corporation/Community as Organization archetypes and permits a
  House to participate in multiple Organizations independently of Territory.
  V5 keeps Communities as many-to-many voluntary associations but restores
  **Corporation as the single local polity/economic affiliation**.
- Current schema contains `house_affiliations.primary_territory_id` and
  `buildings.territory_id`. V5 launch gameplay removes dependence on those
  specific-unit bindings while Territory units are standardized.
- Current Territory capacity/read models may remain temporarily during
  migration but must not remain an independent political authority.

This ADR does not authorize destructive schema changes by itself. The exact
migration is defined in `docs/v5/V5_DOMAIN_AND_DATA_MIGRATION.md`.

## Alternatives considered

### One Corporation → one fixed Territory

Rejected as the final V5 model because Corporation growth would hit a hard
capacity ceiling or require repeated manual expansion decisions for identical
capacity blocks.

### Manual Territory purchase/lease per expansion

Rejected for standardized V5 Territory because the action is administrative,
not strategically distinct. Governance remains meaningful through admission,
local base rates, taxes, budgets, technology, and spending.

### House/building assigned to individual Territory unit

Rejected for V5 launch because identical Territory units make the relationship
non-decision-bearing while greatly increasing schema, UI, migration, and
settlement complexity.

### Flat capacity pricing

Rejected because very large Houses/Corporations could concentrate scarce
capacity at the same marginal price as small actors. Progressive marginal
brackets provide a transparent, governable counterweight without hard caps.

### Highest-bracket-reprices-all pricing

Rejected because crossing a boundary would create discontinuous cost cliffs and
strong threshold gaming. V5 always uses marginal brackets.

## Consequences

- Corporation directory and My Corporation must show capacity utilization and
  pricing rather than a political Territory directory.
- A standalone Society → Territories page is no longer required for V5 launch
  unless it is repurposed as a read-only global capacity/land view.
- Building construction/upgrade previews must include footprint and the exact
  incremental House capacity charge.
- House Finance/Daily Briefing must include capacity rent and arrears.
- Corporation Finance must include House capacity-rent revenue and EARTH land
  expense.
- Governance must expose authorized base-rate and global progressive-policy
  proposals with server-calculated impact previews.
- Settlement must calculate and post both levels of capacity charge in a
  deterministic, replay-safe phase.

## Current authority

V5 is current. This ADR is part of the active domain authority together with the
Constitution, V5 master gameplay specification, and current repository evidence.
