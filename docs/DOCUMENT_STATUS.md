# EARTH Design Document Status

This index prevents stale design material from being mistaken for current
authority.

| Document | Status | Use |
|---|---|---|
| `CONSTITUTION.md` | CANONICAL | Permanent rules of the world |
| `GAME_ECONOMY_SPEC.md` | CANONICAL | Shared formulas, units, timing, and economic semantics |
| `CONSTITUTION_COMPLIANCE.md` | CANONICAL | Implementation and test mapping for constitutional clauses |
| `BUILDING_ECONOMY_V2.md` | CANONICAL | Current Building V2 model |
| `BUILDING_ECONOMY_CONTRACT.md` | CANONICAL | Building accounting and settlement contract |
| `MARKET_V2.md` | CANONICAL | Spot Market architecture |
| `FINANCE_V2.md` | CANONICAL | Finance and monetary accounting boundaries |
| `DEATH_HOUSE_CONTINUITY_V2.md` | CANONICAL | House/Human identity and succession model |
| `TECHNOLOGY_RD_V2.md` | CANONICAL | Technology, research, patents, and licenses |
| `CITIES_CORPORATIONS_BUDGETS_V2.md` | CANONICAL | Institutional budgets and fiscal authority |
| `ARCHITECTURE.md` | REFERENCE | Cross-system implementation boundaries |
| `ARCHITECTURE_BASELINE.md` | REFERENCE | Frozen implementation inventory and rollout state |
| `TIME_HANDLING_RULES.md` | REFERENCE | Server/database time handling rules |
| `OPERATIONS_RUNBOOK.md` | REFERENCE | Operational procedures and health checks |
| `BACKUP_AND_RESTORE.md` | REFERENCE | Recovery procedures |
| `GAMEPLAY_REDESIGN_AUDIT.md` | HISTORICAL | Evidence record of an earlier product redesign; not a rules source |
| `ECONOMY_V2_PLAN_0.md` | HISTORICAL | Migration history and prior boundary decisions |
| `AI_DEVELOPMENT_GUIDE.md` | REFERENCE | Guidance for future development tooling; it does not describe an in-game assistant |
| `AI_DEVELOPMENT_INSTRUCTIONS.md` | REFERENCE | Development process guidance; not game mechanics |

## Stale-document rule

Documents marked HISTORICAL must not be used to implement gameplay. When a
historical document contradicts a CANONICAL document, the canonical document
wins. New mechanics require an update to the relevant canonical document and
its compliance mapping before code changes are treated as complete.

