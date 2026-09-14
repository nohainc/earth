# ADR-002: Subsidiarity and mechanic responsibilities

- Status: Accepted
- Date: 2026-09-14
- Scope: Domain boundaries, authority, ownership, payment, location, and
  state ownership for future mechanics
- Depends on: [Canonical world vocabulary](../ADR-002-canonical-world-vocabulary.md)

## Decision

EARTH uses subsidiarity: a responsibility belongs to the lowest domain that
can perform it without violating the EARTH Constitution.

The canonical model is:

> EARTH → Corporation → House

Territory is a geographic object within that model. It is where things exist,
not an institution, treasury, owner, electorate, or payer.

The following definitions are frozen:

| Domain object | Definition | Primary responsibilities | Forbidden responsibilities |
|---|---|---|---|
| **EARTH UC** | Global authority and constitutional framework | Civilization-wide law, global taxation, cross-polity rules, global programs, Constitution, Bank charter | Local Corporation administration, House property ownership, Territory treasury |
| **Corporation** | Chartered autonomous local polity and economic community | Local governance, treasury, Corporation taxation, public infrastructure, local services, local technology adoption | Persistent private ownership of House assets, geographic identity, global constitutional authority |
| **House** | Persistent private economic principal | Private property, private buildings, contracts, debts, migration choice, succession continuity | Global or Corporation public authority, acting as a mortal representative |
| **Human** | Mortal representative of a House | Personal actions, votes where eligible, offices, biography, current representation | Persistent House ownership or House economic continuity |
| **Territory** | First-class geographic area | Location, boundaries, capacity, spatial projections, building scarcity | Treasury, taxation, governance, ownership, electorate, independent economic identity |
| **Building** | Constructed asset located in a Territory | Production, services, capacity, maintenance, use by its owner | Authority, electorate, treasury, independent government, jurisdiction |
| **Global Bank** | EARTH-chartered financial institution | Banking, deposits, loans, liquidity, settlement services under EARTH rules | Corporation governance, House succession, Territory ownership, constitutional authority |

Initially, each Corporation has one primary Territory. The data model may
support additional Territories without making Territory a separate polity.

## Responsibility separation rule

Every mechanic specification must distinguish:

> `authority ≠ actor ≠ payer ≠ owner ≠ location ≠ state holder`

These roles may refer to the same domain object only when the mechanic record
explicitly justifies that coincidence. A generic `entityType` must not be used
as a substitute for these separate roles.

Examples:

- Corporation authority may authorize a public building.
- A Human may act for the House and submit the action.
- The Corporation may pay for the building.
- The Corporation owns public infrastructure; a House owns private assets.
- Territory is the building's location.
- The settlement projection or ledger is the state holder.

## Domain boundary types

New domain-facing code should use the shared boundary types in
`cloudflare/src/domain-boundaries.ts`:

- `AuthorityScope = EARTH | CORPORATION`
- `EconomicPrincipalType = EARTH | CORPORATION | HOUSE | BANK | SYSTEM`
- `ActorType = HUMAN | SYSTEM`

Territory, Building, and Human are deliberately absent from
`EconomicPrincipalType`. They may be identifiers in other roles, but they are
not economic principals merely because a mechanic references them.

## Governance and fiscal boundaries

- Governance scope is limited to `EARTH` or `CORPORATION`.
- Tax jurisdiction is limited to `EARTH` or `CORPORATION`.
- Corporation public budgets are the sole local public budgets.
- Territory capacity and service projections are state projections, not
  Territory authority.
- House actions remain private and should not require a proposal unless a
  later mechanic explicitly creates a public externality.

## Future mechanic requirement

Every mechanic introduced from Point 3 onward must include a completed
Mechanic Responsibility Record. The template is stored at
`docs/architecture/MECHANIC_RESPONSIBILITY_RECORD.yaml`.

This ADR does not require an immediate `ActionContext` migration, a complete
financial transaction rewrite, or a settlement-engine rewrite. Those changes
remain scoped to the mechanics that need them.

## Guardrails

The schema and architecture tests must prevent these regressions:

1. Territory cannot be an economic principal.
2. Building cannot be a government or authority.
3. Human cannot be the persistent owner of House economic state.
4. Governance scope can only be EARTH or CORPORATION.
5. `CITY` must not be introduced into new domain code.
