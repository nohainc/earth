# EARTH clean schema V3

- Status: Canonical
- Baseline: `db/baseline/01_schema.sql`
- Generated migration: `db/migrations/001_baseline.sql`
- Schema head: 3

## Purpose

Schema V3 is a clean-break baseline. It intentionally does not preserve the
City hierarchy or compatibility aliases for it. A fresh database must be
unable to recreate that hierarchy using the canonical tables and constrained
values.

## Canonical entities

| Entity | Database representation | Responsibility |
|---|---|---|
| EARTH | `institutions.kind = 'EARTH'`, `owner_registry.owner_type = 'EARTH'` | Global authority and global tax jurisdiction |
| Corporation | `institutions.kind = 'CORPORATION'`, `corporations` | Local polity, governance, treasury, and local tax jurisdiction |
| Territory | `territories` | Geography and physical location only; never an economic owner or polity |
| House | `houses`, `owner_registry.owner_type = 'HOUSE'` | Persistent private owner |
| Human | `humans` | Mortal representative of a House |
| Bank | `institutions.kind = 'BANK'`, `owner_registry.owner_type = 'BANK'` | Chartered financial institution |

## Structural decisions

- There is no `cities` table, City institution kind, City owner type, City tax
  scope, or City communication scope.
- A Corporation may have multiple Territories. The database permits at most
  one active primary Territory per Corporation.
- `house_affiliations` records historical House membership in a Corporation.
  A House can have at most one active Corporation affiliation. The optional
  `primary_territory_id` is constrained to a Territory belonging to that same
  Corporation.
- Every building has a required `territory_id`. Location is independent from
  economic ownership, so a House may retain a building in a Territory after
  changing Corporation affiliation.
- Territory has no treasury, economic account, governance role, proposal,
  budget, or tax authority in the baseline.
- Economic owner types are exactly `EARTH`, `CORPORATION`, `HOUSE`, `BANK`, and
  `SYSTEM`. `TERRITORY` is deliberately absent.
- Tax jurisdictions are exactly `EARTH` and `CORPORATION`.
- Communication scopes are `global`, `corporation`, `community`, and `direct`.

## Clean-break rule

No `cities_legacy` table, city-to-territory mapping, compatibility view,
dual-write path, nullable `city_id`, or V2/V3 fallback belongs in the schema.
Development databases must be recreated from the clean baseline and fresh
fixtures must use Territory vocabulary.

