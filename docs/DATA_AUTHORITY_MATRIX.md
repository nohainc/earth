# EARTH Data-Authority Matrix

Status: authoritative implementation map  
Scope: economic values, rates, capacities, and permissions

Every value that affects gameplay must have one authoritative source. Seeds,
API serializers, caches, and compatibility adapters may copy a value, but they
must not define a competing value. A copied value is marked **projection** or
**compatibility** and must be safe to rebuild from the authority.

| Economic value | Authority | Allowed consumers | Non-authoritative copies to remove or constrain |
|---|---|---|---|
| Building construction cost | `building_catalog` | construction, proposals, balance model | TypeScript catalog is compatibility fallback only |
| Building construction time | `building_catalog.construction_days` | construction, `building_construction_time_model` | no tier formulas |
| Building daily operating cost | `building_catalog.operating_service_cost_units` or explicit daily compatibility field | Building V2, operating-cost model | generic catalog/UI fallbacks must not settle |
| Building resource recipe | `building_catalog` and effective `building_economic_rule_versions` | Building V2 planner | duplicated TypeScript economics |
| Tier unlock | `corporation_building_unlocks` and catalog blueprint | construction and governance | generated tier formulas |
| Technology definition/cost/RP | `technology_catalog` | research, UI, balance model | static technology numbers |
| Technology effect | `technology_effects` plus modifier rules | modifier cache and subsystem resolvers | subsystem-specific if-statements |
| Tax rate and base | `tax_rule_versions` selected by settlement day | tax assessment and proposals | legacy `tax_rules` is compatibility history only |
| Market price | completed Spot Market batches/fills | candles, analytics, UI | `market_prices` is a transitional read projection only |
| Bank rates and limits | effective versioned bank rules | Finance V2 | hard-coded loan/deposit rates |
| Human needs | Human Needs rules and daily needs projection | life, city dynamics, mortality | UI estimates |
| Budget authority | `institution_budget_lines` | budget engine and proposals | legacy `budgets` |
| Fiscal commitments | `institution_budget_commitments` | spending and distress | counters without source rows |
| City service capacity | `city_service_capacity_daily` | city dynamics and needs | scalar capacity as independent authority |
| Research capacity | Building V2 daily capacity projection | research scheduler | fixed project-duration formulas |
| Reference balance price | `economic_reference_prices` | balance/read models only | market prices and live account balances |
| Live monetary balance | `economic_accounts` (Economy V2) | all financial flows | legacy account/balance tables |

## Required audit rules

1. A settlement path must query the database authority for the game day; a
   static catalog may only be a clearly labeled compatibility fallback.
2. A seed is an initialization mechanism, not a second runtime authority.
3. A projection must include its source identity or be rebuildable from the
   authority and must never be written back as a new source value.
4. Balance analysis uses stable reference prices. It never substitutes current
   Spot Market prices for balance inputs.
5. Historical values are selected by effective game day and version, never by
   whichever row is currently active.

## Current compatibility findings

The active codebase still contains legacy compatibility reads in a few
presentation/starter paths, including `market_prices`, `tax_rules`, and the
static `BUILDING_CATALOG`. These are intentionally recorded here as migration
findings; they must not be used by authoritative settlement or posting paths.
The matrix is a release checklist for removing those reads, not permission to
add new ones.

The building catalog no longer contains a monetary output field. `output_credits`
was removed from the canonical schema in migration 349; the world snapshot may
retain a zero-valued response field temporarily for API compatibility, but no
settlement path may read or write it. Building condition, wear, and repair
fields were removed by migration 340. Historical migration files may still
mention those fields because migration history is append-only; they are not
part of the current schema authority.
