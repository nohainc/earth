# EARTH Design Document Status

This index distinguishes the **current runtime authority** from the accepted V5
target. Future AI-assisted work must not confuse a target specification with
implemented production behavior.

## V5 Accepted Target Specifications

> [!IMPORTANT]
> V5 is the accepted target gameplay architecture and is **not yet fully the
> current runtime**. The repository has an active Constitution & Governance
> Kernel slice, including migrated capacity and tax consumers; those slices are
> tracked by `v5/V5_CONSTITUTION_GOVERNANCE_KERNEL.md`. Current-runtime documents
> remain authoritative for all behavior that has not been explicitly migrated
> until the V5 cutover gates are completed and this file is updated again.

| Document | Status | Scope & Purpose |
|---|---|---|
| `ADR-003-v5-corporation-territory-capacity-model.md` | ACCEPTED TARGET | V5 Corporation/Territory/capacity boundary and migration decision |
| `v5/README.md` | TARGET INDEX / PARTIAL IMPLEMENTATION | Required read order, implemented-slice pointer, and V5 cutover definition |
| `v5/V5_MASTER_GAMEPLAY_SPEC.md` | TARGET-CANONICAL | V5 hierarchy, responsibilities, gameplay loops, invariants |
| `v5/V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md` | TARGET-CANONICAL | Universal marginal brackets, land/capacity billing and fiscal semantics |
| `v5/V5_DOMAIN_AND_DATA_MIGRATION.md` | TARGET-CANONICAL | Current-to-V5 data/schema/API/read-model migration |
| `v5/V5_IMPLEMENTATION_ROADMAP.md` | TARGET-CANONICAL | Ordered implementation phases and cutover gates |
| `v5/V5_AI_EXECUTION_PLAYBOOK.md` | EXECUTION | AI-ready task packages, constraints, tests, handoff evidence |
| `v5/V5_UI_MIGRATION_MATRIX.md` | TARGET-UX | Page/navigation migration after authoritative backend slices |

### V5 authority rule

For a task explicitly labelled V5, read the V5 pack. For questions about what is
currently implemented/deployed, use the current runtime documents and repository
evidence. A V5 specification becomes current runtime authority only after its
phase is implemented, verified, and the repository status is updated.

## V4 / Current Runtime Specifications

| Document | Status | Scope & Purpose |
|---|---|---|
| `CONSTITUTION.md` | CURRENT-CANONICAL | Current permanent rules of the world; requires V5 amendment before V5 cutover |
| `V4_DOMAIN_MODEL.md` | CURRENT-CANONICAL | Current V4 meanings and implemented target assumptions |
| `V4_TARGET_ARCHITECTURE.md` | CURRENT-CANONICAL | Current authority, settlement, economy, and product boundaries |
| `V4_IMPLEMENTATION_STATUS.md` | CURRENT-CANONICAL | Evidence-based implementation status across settlement and features |
| `GAME_ECONOMY_SPEC.md` | CURRENT-CANONICAL | Shared formulas, units, timing, and economic semantics until replaced by implemented V5 rules |
| `BUILDING_ECONOMY_CONTRACT.md` | CURRENT-CANONICAL | Current building accounting, fixed-point formulas, settlement contract |
| `CONSTITUTION_COMPLIANCE.md` | CURRENT-CANONICAL | Current implementation/test mapping for constitutional clauses |
| `ADR-002-canonical-world-vocabulary.md` | CURRENT-CANONICAL | Current canonical world vocabulary; V5 ADR-003 refines target relationships without erasing historical meaning |
| `ARCHITECTURE.md` | REFERENCE | Cross-system implementation boundaries and Worker-PostgreSQL topology |
| `FLUTTER_ARCHITECTURE.md` | REFERENCE | Flutter client design system and feature modularity guidelines |
| `API_CONTRACT.md` | REFERENCE | Active REST API and Nano Markup endpoints |
| `TIME_HANDLING_RULES.md` | REFERENCE | Server/database time handling rules |
| `OPERATIONS_RUNBOOK.md` | REFERENCE | Operational procedures and health checks |
| `BACKUP_AND_RESTORE.md` | REFERENCE | Recovery procedures |

## Historical & Superseded Archive (`docs/archive/v2-v3/`)

> [!WARNING]
> Documents in `docs/archive/v2-v3/` represent earlier prototype milestones (V2
> and V3) and MUST NOT be used as current gameplay authority.

| Document | Archive Status | Original Topic |
|---|---|---|
| `docs/archive/v2-v3/SCHEMA_V3.md` | SUPERSEDED | V3 database schema |
| `docs/archive/v2-v3/CORPORATION_LIFECYCLE_V3.md` | SUPERSEDED | V3 Corporation hierarchy |
| `docs/archive/v2-v3/TERRITORY_CAPACITY_V3.md` | SUPERSEDED | V3 Territory ownership/capacity |
| `docs/archive/v2-v3/BUILDING_OWNERSHIP_V3.md` | SUPERSEDED | V3 building slots |
| `docs/archive/v2-v3/CORPORATION_PUBLIC_INFRASTRUCTURE_V3.md` | SUPERSEDED | V3 Corporation public works |
| `docs/archive/v2-v3/CORPORATION_FISCAL_V3.md` | SUPERSEDED | V3 Corporation fiscal layer |
| `docs/archive/v2-v3/GOVERNANCE_V3.md` | SUPERSEDED | V3 Corporation politics |
| `docs/archive/v2-v3/SETTLEMENT_V3.md` | SUPERSEDED | V3 settlement |
| `docs/archive/v2-v3/CLIENT_V3.md` | SUPERSEDED | V3 client navigation |
| `docs/archive/v2-v3/CITIES_CORPORATIONS_BUDGETS_V2.md` | SUPERSEDED | V2 City hierarchy |
| `docs/archive/v2-v3/BUILDING_ECONOMY_V2.md` | SUPERSEDED | V2 building economy |
| `docs/archive/v2-v3/MARKET_V2.md` | SUPERSEDED | V2 market draft |
| `docs/archive/v2-v3/FINANCE_V2.md` | SUPERSEDED | V2 finance |
| `docs/archive/v2-v3/DEATH_HOUSE_CONTINUITY_V2.md` | SUPERSEDED | V2 succession draft |
| `docs/archive/v2-v3/TECHNOLOGY_RD_V2.md` | SUPERSEDED | V2 technology/R&D |
