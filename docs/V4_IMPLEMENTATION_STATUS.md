# EARTH V4 implementation status

Updated: 2026-09-15

This status is deliberately evidence-based. A phase is not considered live
because a type, route, or UI label exists; it must execute authoritative state
changes and have certification coverage.

## Completed in this cut

- V4 domain vocabulary is recorded in `docs/V4_DOMAIN_MODEL.md`.
- Decision Queue uses House, Territory, Organization, and shared-world
  language for the first V4 decision-first gameplay surface.
- Queue output remains a deterministic, server-derived read model and does not
  become an economic authority.
- V4-010 settlement work ledger, database lease claim/heartbeat, bounded unit
  execution, retry handling, and a phase/day-close barrier are implemented.
- V4-020 fixed-point arithmetic is applied to building settlement: catalog
  flows, proportional utilization, and private/public operating expenses stay
  in integer units end to end.
- V4-030 daily House statements now persist opening/closing assets, physical
  production and consumption, market activity, obligations, and settlement
  exceptions from PostgreSQL canonical facts after the end-of-day barrier.
- V4-040 needs/service foundation is wired with versioned need rules, service
  types, bounded deterministic capacity allocation, payer/provider settlement,
  and explicit House need-risk projections.
- V4-050 PostgreSQL-backed Command Center and Decision Queue routes derive
  succession, service risk, proposals, obligations, and research facts from
  the canonical read model.
- V4-060 House operating policies now have versioned, future-effective,
  auditable records plus deterministic inventory and sale evaluators with
  reserve-floor and spend-cap safeguards.
- V4-060 policy actions now execute through the ordinary Spot Market path at
  first completion of a game day, with deterministic idempotency keys and
  exception logging.
- V4-070 onboarding progress is versioned per House, seeded during registration,
  exposed through authenticated status/advance routes, and grounded in live
  asset, building, and market facts. Expert skip is explicit and auditable.
- V4-080 resource behavior metadata distinguishes durable stock, perishable
  stock, and flow/capacity resources, with staged decay and settlement modes
  exposed through the canonical resource metadata endpoint. Food now applies
  bounded integer-unit decay through an owner-sharded end-of-day sink phase;
  each loss is ledger-visible and correlation-idempotent.

## Settlement classification

| Phase | Status | Evidence |
| --- | --- | --- |
| life maintenance | REQUIRED-V3-CORE | `settleLifeMaintenanceInTransaction` |
| building settlement | REQUIRED-V3-CORE | `settleBuildingUpkeepAndRevenueV2` |
| Territory capacity projections | REQUIRED-V3-CORE | `settleTerritoryCapacityProjections` |
| Corporation dynamics | IMPLEMENTED | `settleCorporationDynamics`, `corporation_operating_snapshots` |
| lifecycle | REQUIRED-V3-CORE | `processHouseMortality` |
| resource analytics snapshot | REQUIRED-V3-CORE | `refreshResourceAnalyticsInTransaction` |
| financial projections | REQUIRED-V4 | `refreshInstitutionFinancialSnapshots` |
| patent/public-domain settlement | REQUIRED-V4 | `settlePatentExpirations` |
| technology license billing | REQUIRED-V4 | `settleTechnologyLicenseFees` |
| all other registered phases | DEFERRED-V4 | Must not be presented as complete gameplay until wired and certified |

V4-010 is now the active foundation slice. Full crash/replay certification
still requires a live PostgreSQL instance with migration 015 applied.

V4-040 still requires live PostgreSQL allocation/replay certification and the
Flutter Life & Services presentation before it can be considered complete.
V4-050 still requires endpoint integration certification and a richer client
presentation. V4-070 still requires a live first-30-day end-to-end scenario.
V4-080 flow-capacity settlement remains gated on simulation evidence. Later V4 epics remain
unimplemented and must not be presented as complete.
V4-090 now records canonical building family and tier-formula metadata and
exposes it from the catalog read model; integer T1-to-T5 derivation is covered
as a shared domain primitive.
V4-100 construction now funds a durable project, keeps the building inactive
until its due settlement phase, supports deterministic completion, and records
an auditable cancellation refund path.
V4-110 now gives each Territory an explicit, backfilled governance relation and
returns the governing Organization alongside capacity facts, while retaining
the existing Corporation compatibility path during the larger institutional
cutover.
V4-120 now records manual versus House-policy order provenance, optional policy
linkage, good-til-day expiry, and bounded escrow-safe expiry processing. Policy
orders continue through the ordinary Spot Market matcher.
The market read model also exposes seven-day volume, VWAP, volatility, and
spread projections from canonical fills and instrument state.
V4-130 now provides a generic Organization core with overlapping House
memberships, role-gated membership decisions, capability declarations, and
request workflows. Corporation and Community adapters remain during cutover.
The Organization API currently exposes directory, creation, membership,
member-list, request-list, approval, and rejection operations through the
canonical Worker dispatcher.
V4-140 now includes a deterministic legacy bridge mapping Corporation and
Community identities, memberships, requests, and
capabilities into the Organization tables without deleting the legacy paths
before runtime certification.
V4-150 now gives each House an independent primary residency history with
capacity-locked move quotes and next-settlement effective moves. Moving a House
does not move or destroy its remote buildings.
V4-160 now provisions eligible Organizations through the shared Economy V2
ledger, exposes treasury/operations/reserve and budget read models, and keeps
budget authority distinct from actual ledger spending.
V4-170 now has a clean V4 proposal/ballot/execution journal with typed action
registration, immutable rule/action snapshots, House electorate semantics, and
Organization governance capability checks. Legacy governance remains an
adapter until all specialized actions are migrated.
Dedicated V4 proposal, ballot, and resolution routes are now available under
`/api/governance/v4`, while legacy governance routes remain isolated during
cutover.
V4-180 now gives every Organization a versioned, validated charter. Four
constitutional presets are seeded, existing Organizations are backfilled, and
amendments become effective at the next game-day boundary. Treasury and V4
governance authorization resolve capabilities from the active charter, with
history, validation, template-catalog, and amendment API surfaces.
V4-190 foundation now separates governance method selection, scoped delegation,
and quadratic Voice from Economy V2 CREDIT. Voice has its own cycle/allocation
tables and integer quote strategy; delegation chains reject loops.
V4-200 now establishes a permanent EARTH global-program surface distinct from
player Organizations. Programs are linked to EARTH public-project proposals,
fund only through the canonical EARTH treasury with authority/cash checks, and
advance through a bounded settlement phase without a global resource warehouse.
V4-225 now adds generic Organization offices and Human-scoped authority grants.
Membership remains House-based, while executive, treasury, governance, and
operating authority is separately time-bounded and resolved through one shared
resolver; inactive Humans therefore lose office authority without losing House
membership.
V4-230 now adds fixed-unit fractional asset ownership, capitalization history,
and next-day effective dilution subscriptions. Existing legal owners are
backfilled at 10,000 units; investor funding uses Economy V2 CREDIT and cannot
overissue the cap table. Ownership distributions now pay eligible holders
proportionally through the ledger, record payment history, and retain integer
rounding remainders explicitly.
V4-240 now adds approved typed Organization contracts with two-party signatures,
contract terms validation, first-period financial obligation materialization, and
contract/performance portfolio APIs. Unsigned contracts cannot create obligations.
V4-250 now adds global technology domains and generations with predecessor and
world-milestone eligibility, explicit research programs, immutable discoveries,
and next-day effective generation progression through the bounded settlement
engine. Generations are separate from physical building tiers.
V4-260 adds Organization-scoped technology adoption foundations and V4-270
adds derived building age/design-life burden, generation installation history,
and capital-decision comparison data. Age is not incremented daily, assets are
never auto-destroyed, overhaul resets the major-rebuild date, and retrofit does
not.
V4-280 now adds public projects with EARTH proposal authorization, explicit
House contribution escrow, bounded breadth-aware matching, replay-safe funding
records, deadline settlement in the resumable daily phase engine, and refunds
when a project does not reach its target. Matching is capped by both the
authorized/funded pool and the remaining target; no theoretical uncapped pool
is created.
V4-290 now has a canonical banking risk migration: versioned credit policy,
reserve-backed integer underwriting, collateral and guarantee records, partial
repayment history, daily interest accrual, maturity delinquency, collateral
liquidation, and append-only resolution history. Protected APIs expose server-
derived quotes, origination, repayment, guarantees, and bank risk projections.
V4-310 now adds organization financial health states, daily bounded evaluation,
resolution cases, creditor claims with explicit priority, and successor mapping
records. Insolvency opens an auditable restructuring case without deleting
assets, contracts, memberships, or economic history; merger/split execution is
implemented through a governance-approved execution slice. Resolution plans
require a passed Organization proposal, validate successors, and become
effective on the next game-day boundary.
V4-320 now adds explicit jurisdiction/nexus types to fiscal and contract
obligations, asset-jurisdiction history, and mobility quotes that distinguish
residence from remote building locations while reporting affected obligations.
A House move remains next-day effective and never forces remote asset sale.
V4-330 now expires Human-scoped Organization office grants at death while
leaving House-owned economy, memberships, assets, and contracts intact. The
existing succession engine remains the authority for next-day successor
activation and lineage history.
V4-340 now adds a bounded late-entry opportunity read model for open Territory
capacity, recruitable Organizations, and active market demand, plus a one-time
resource-only entry-support entitlement. Registration records the entry game
day; claims are transactionally revalidated, idempotent, evented, and cannot
issue Credit or bypass technology discovery. Flutter exposes the opportunity
journey and claim action from House orientation.
V4-350 now replaces placeholder wealth-only ranking payloads with eight
versioned House dimensions: wealth, productive capacity, legacy, technology,
public goods, Organization scale, Territory quality, and market role. Each
dimension has independently reproducible bounded snapshots at day close; the
API exposes methodology and explicitly returns no composite score. Flutter
rankings allow players to select a dimension.
V4-360 now adds a deterministic balance-health layer with explicit survival,
shortage, utilization, and wealth-concentration bands. The long-horizon lab
supports 100/1,000/10,000 House populations and 10/30/100-year horizons across
the resource scenario library, emitting HEALTHY/REVIEW results for CI and
balance review. Pooled market clearing plus an explicit bounded House
liquidity facility now makes all baseline 10/30/100-year runs pass at
100/1,000/10,000 House scale; credit exposure is reported and capped at 75%
of starting supply. Stress scenarios remain visible as REVIEW where their
resource shocks exceed the target bands.
V4-370 now adds an immutable, effective-dated world-condition registry and
public feed. Conditions use a constrained, versioned effect vocabulary with
explicit source, scope, modifier, and expiry; the core economy remains
unchanged when the registry is empty, and the canonical world snapshot exposes
active conditions for player-facing explanation. Supply, demand, provider
capacity, and construction-duration modifiers are now applied in fixed-point
settlement/quote paths with organization and Territory scoping; labor-index
effects remain deferred until a dedicated labor-cost authority exists.
V4-380 now adds a dedicated World Conditions Flutter surface backed by the
canonical world snapshot, updates the app and HUD branding to “A Living World,”
and adds World Conditions to the Earth navigation group. The panel explains
baseline versus active conditions without calculating or mutating authoritative
gameplay state.
V4-400 launch-gate hardening now distinguishes required settlement phases from
explicitly deferred legacy slots. Required successor activation uses the
canonical lifecycle implementation, while unimplemented profile, levy, tax,
bank, dividend, and projection slots can no longer masquerade as completed
required work. Public Pantheon, Cemetery, and market-history read models now
query bounded canonical PostgreSQL facts and preserve the client-compatible
response shapes; Cemetery filtering is explicitly parameterized by search,
House, and dynasty.
V4-300 now provides an opt-in mutual-credit experiment with Organization-scoped
units, governed member limits, transactional positions/transfers, transactional
guarantees, default records, reconciliation telemetry, and feature-gated APIs. It does
not create or modify global CREDIT and remains disabled by default. Flutter now
has an experimental Mutual Credit surface and transport methods that label
network units separately from CREDIT.

V4-210 foundation now gives Territory capacity an explicit House-scoped use-right
model with bounded slot quantity, effective dates, server-priced rent, locked
acquisition/release, beneficiary-backed CREDIT movement, and append-only lifecycle
events. Construction and building records can reference a right without conflating
private building ownership with commons land/use rights. Daily lease payment and
holdover settlement now runs through the owner-sharded required settlement engine;
live PostgreSQL replay/concurrency certification and a richer Territory client journey
remain before this epic is marked complete.

V4-220 now adds source-backed commons dividend declarations and settlement. A
governing institution snapshots lease revenue and reserve/dividend percentages;
the required settlement phase pays eligible House right-holders proportionally,
assigns integer remainder units explicitly, and blocks rather than issues CREDIT
when the commons beneficiary lacks cash. Live replay/concurrency certification
and the Flutter statement journey remain open.

V4-205 now adds an explicit public tax-authority registry and a House tax
statement read model. Active tax rules and obligations expose authority type,
nexus, rule version, base reference, beneficiary, and effective interval; the
statement includes both legacy tax rows and generic financial-obligation arrears.
The required owner-sharded tax phase now assesses the prior finalized day,
writes the obligation before collection, transfers only available CREDIT, and
records arrears when payment cannot be made. Corporation tax remains an
explicitly labelled legacy authority during cutover; live replay/concurrency
certification and the richer Finance client presentation remain open.

V4-115 now gives every building an explicit economic role (producer,
transformer, service, infrastructure, or estate). Catalog responses expose the
role, and commercial service settlement only admits role-qualified providers;
public infrastructure remains a separate public-cost and Territory-effects
path. Deterministic role classification and role-routing contract tests are
included.

V4-225 now has a complete office-action vertical slice: active Organization
members can be appointed to temporary Human offices by an authorized office
holder, current holders can resign, idempotency is enforced by correlation
keys, and succession expires Human grants without transferring authority to
the next generation. The centralized resolver remains the only office-action
authority check.
The institutions UI now includes a People & Roles panel backed by the
authority roster, with appointment and resignation actions routed through the
same server resolver.

V4-370 now has a transparent runtime modifier path for service demand and
capacity: effective World/Territory conditions are stacked in fixed-point
units during settlement, while the effective-dated feed and persisted need
assessments preserve source, rule version, and historical outcomes. Macro
condition authoring now uses the typed V4 `WORLD_CONDITION` governance action
and execution journal. The canonical world payload and World panel now expose
whether each condition is worldwide, current-Territory, organization-scoped,
or elsewhere, together with its exact effect and expiry. Construction-duration
shocks now combine scoped construction and labor indexes; direct wage and
labor-cost settlement remains deferred until a dedicated labor-cost authority
exists.

Institution finance reads now use the active Economy V2 ledger projection
service directly. Budget summaries preserve the stable DTO field names while
deriving cash, authority, obligations, and financial state from current V4
tables; removed historical `institution_financial_projections` queries are no
longer part of the runtime path.

The canonical `/api/world` payload now carries the V4 client read model rather
than only a thin world registry: authenticated House/Human facts, resource
balances, buildings and catalog roles, residency, obligations, Territory
capacity, and the server-derived decision queue are all returned from
PostgreSQL-backed queries.

The Command Center now consumes the same service assessment rows through a
compact Life & Services risk panel, showing finalized critical/watch gaps and
unallocated demand without inventing client-side service state.

## Verification in this workspace

- Focused V4 regression and mobility/resolution checks: passing.
- API contract generation and schema-contract check: passing.
- Migration order: 57 contiguous active migrations. Corporation dynamics now writes a replay-safe daily operating snapshot derived from canonical territories, affiliations, buildings, service allocations, research projects, and organization financial state; it does not mutate balances or create a competing ledger authority. Institution financial snapshots are recomputed set-wise at day close from Economy V2 balances, ledger flows, budget authority, and obligations. Patent grants and public-domain transitions now run as a required database-authoritative settlement step.
- Baseline freeze checksum: passing.
- Live PostgreSQL replay/concurrency certification and Flutter SDK tests remain
  environment-gated; the installed Flutter toolchain cannot write its protected
  cache in this workspace.
