# EARTH Constitution Compliance Map

This is the implementation index for the constitutional rules. A clause is
compliant only when its authoritative implementation, runtime guard, and
regression test agree. The map is intentionally concise; detailed formulas
remain in `GAME_ECONOMY_SPEC.md` and subsystem contracts.

| Clause | Authoritative implementation | Required verification |
|---|---|---|
| CONST-TIME-001 | PostgreSQL world clock; settlement runs and scheduler watermark | `game-clock.test.mjs`, scheduler recovery tests |
| CONST-TIME-002 | Daily settlement phases and explicitly daily economic rule fields | `daily-economy-contract.test.mjs`; daily settlement certification |
| CONST-MONEY-001 | `economic_accounts`, `economic_transactions`, `economic_entries`; posting primitives | Economy V2 invariant/certification tests |
| CONST-MONEY-002 | Issuance/retirement account types and reason/rule/correlation requirements | money-supply reconciliation and finance acceptance checks |
| CONST-ASSET-001 | `economic_assets`; fixed-point resource accounts and source/sink postings | economy conservation and building property tests |
| CONST-OWNER-001 | `owner_registry` and V2 account ownership | owner integrity report and House continuity tests |
| CONST-HOUSE-001 | `houses.current_human_id`; House economic owner | House/death property and session security tests |
| CONST-MARKET-001 | Spot-only `market_instruments`; Spot batches/orders/fills/escrow | `spot-market-architecture-guard.test.mjs`, Market V2 certification |
| CONST-BUILDING-001 | Building V2 planner, effects, and journals | Building Economy V2 integration/property tests |
| CONST-TAX-001 | Versioned tax rules and `tax_obligations` | Finance scenario and invariant tests |
| CONST-BUDGET-001 | `institution_budget_lines`, commitments, generic spending engine | budget certification and concurrency tests |
| CONST-CITY-001 | City fiscal stress/receivership state machine | city finance scenario tests |
| CONST-CORP-001 | Corporation distress, restructuring, liquidation, creditor waterfall | finance and institution scenario tests |
| CONST-GOV-001 | Proposal state machine, immutable ballots/rule versions, role resolver | governance rule and proposal lifecycle tests |
| CONST-RESEARCH-001 | `corporation_research_projects`, research capacity, V2 funding | Technology/IP scenario tests |
| CONST-IP-001 | Technology catalog, patents, access, and license contracts | IP lifecycle and modifier property tests |
| CONST-SUCCESSION-001 | House-owned accounts/assets and atomic succession event | full-world death and House conservation tests |
| CONST-INSOLVENCY-001 | Financial obligations and explicit resolution postings | finance acceptance and insolvency property tests |
| CONST-AMEND-001 | Versioned Constitution document and constitutional governance process | constitutional amendment review gate |

## Automated guardrails

The following checks are mandatory for changes touching the economic core:

```sh
npm run test:certification
node --experimental-strip-types --test \
  test/market-v2-foundation.test.mjs \
  test/migrations-integrity.test.mjs
```

The Spot architecture guard scans active Worker source and the canonical
schema/manifest for retired Futures concepts. Database-backed reconciliation,
fresh migration, and scale tests require the configured test PostgreSQL
environment and must pass before deployment.

## Review rule

If a change cannot be mapped to a clause, it belongs in a versioned subsystem
specification or backlog—not in an undocumented competing rule system.
