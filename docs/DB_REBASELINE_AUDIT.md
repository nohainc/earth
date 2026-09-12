# EARTH Database Re-baseline audit

Status: `PLAN 1 — AUDITED; migration redesign not started`

This document is the gate between the historical experimental migration chain
and the clean database baseline. The inventory is generated from the canonical
`db/schema.sql` and `db/functions.sql` sources by:

```bash
npm run db:audit:model
```

Every discovered table, column, view, function, and trigger receives exactly
one decision: `KEEP`, `REDESIGN`, or `DELETE`. The checker is intentionally
conservative: an object is not removed by this plan; it is classified so the
baseline can be built without an unexamined “maybe legacy” object.

## Authority matrix

| Domain | Authoritative objects | Historical objects to delete | Decision |
| --- | --- | --- | --- |
| CREDIT/resources | `owner_registry`, `economic_assets`, `economic_accounts`, `economic_transactions`, `economic_entries` | `account_balances`, `resource_balances`, `ledger_entries`, `resource_ledger_entries` | KEEP / DELETE |
| Buildings | `building_catalog`, `building_catalog_effects`, `buildings`, `building_economic_batches`, `building_economic_effects` | condition/repair-only structures and columns | KEEP / DELETE |
| Spot market | `market_instruments`, `market_orders`, `market_batches`, `market_fills`, `market_candles`, market escrow accounts | Futures/derivative structures | KEEP / DELETE |
| Tax | `tax_rule_versions`, `tax_obligations`, `tax_daily_summary` | `tax_rules` | KEEP / DELETE |
| Banking | `bank_deposits`, `bank_loans`, `global_bank_balance_sheet`, bank settlement journals | `global_bank_deposits`, `global_bank_loans` | KEEP / DELETE |
| Technology/IP | `technology_catalog`, `technology_effects`, research projects, patents, licenses, access/cache projections | Human adoption/share/subscription structures | KEEP / DELETE |
| House identity | `houses`, `humans`, `house_affiliations`, succession/lineage events | Human-to-Human estate transfer structures | KEEP / DELETE |
| Budgets | `fiscal_periods`, `budget_categories`, `institution_budget_lines`, commitments, grants, financial events | `budgets` and legacy percentage allocation logic | KEEP / DELETE |
| Governance | proposals, actions, ballots, constitutional/governance rules, vacancies | obsolete role/authority compatibility fields | KEEP / REDESIGN |
| Scheduler/outbox | settlement control/run/phase tables, `event_outbox`, scheduler state | obsolete phase and feature-specific worker state | KEEP / REDESIGN |

## Classification rules

Objects whose names identify removed systems—legacy balances/ledgers, old bank
and tax models, Business, Futures/derivatives, Human technology adoption, AI,
or Human-to-Human inheritance—are marked `DELETE`. Transitional projections,
shadow reconciliation tables, old membership bridges, and legacy financial
state tables are marked `REDESIGN`. Everything else is provisionally `KEEP`
until its dependencies and seed rows are reviewed in the following plans.

Column-level decisions are qualified by their table decision. A column with a
removed mechanic (for example a legacy balance, Business, Futures, or repair
field) is marked `DELETE`; otherwise it inherits its table's current decision.

## Re-baseline gates

Plan 2 may begin only when:

1. `npm run db:audit:model` reports a decision for every discovered object.
2. Each `DELETE` object has no production caller or required seed row.
3. Each `REDESIGN` object has a named replacement and migration/cutover plan.
4. The authority matrix and classification changes are reviewed together.
5. No new schema object is added without an authority decision.
