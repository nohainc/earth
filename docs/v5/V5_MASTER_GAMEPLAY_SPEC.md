# EARTH Gameplay V5 — Master Gameplay Specification

Status: **CURRENT-CANONICAL V5 GAMEPLAY**  
Version: 5.0-design  
Date: 2026-09-16  
Audience: product, engineering, AI development agents, QA, balancing

## 1. Purpose

This document defines the current canonical gameplay model for EARTH V5. It defines the
responsibility of each world layer, the long-term player loop, the ownership and
capacity model, the relationships between EARTH, Corporations, Houses, Humans,
Territory, Buildings, Technology, Market, Governance, and Community systems, and
the design boundaries future work must preserve.

This document defines **gameplay semantics**, not current implementation status.
Current V5 source, schema, migrations, tests, and this specification define the
runtime model. Historical V4 documents are not active authority.

Balance numbers in examples are illustrative. Authoritative rates, bracket
boundaries, capacities, costs, and thresholds belong in versioned database rules
or catalogs and must never be copied into Flutter as economic truth.

---

# 2. V5 design goals

V5 should provide a persistent economic strategy game in which players make
meaningful choices across many game years without relying on unlimited building
tiers or repetitive manual administration.

The target qualities are:

1. **Simple hierarchy, deep consequences.** Players should understand the world
   quickly while still facing meaningful economic and political trade-offs.
2. **Long-term decisions.** Growth should create increasing opportunity cost,
   not just more linear production.
3. **Scarcity without hard caps.** Houses and Corporations may grow indefinitely,
   but scarce physical capacity becomes progressively more expensive.
4. **Two governing layers only.** EARTH and Corporation govern. Territory is
   physical capacity, not a third government.
5. **House continuity.** The House remains the persistent private economic player;
   Humans are mortal representatives.
6. **Global interdependence.** Corporations remain economically connected through
   the global Market and EARTH-level systems.
7. **Real fiscal feedback.** EARTH and Corporations can become underfunded because
   of player decisions. Governance is consequential rather than decorative.
8. **Server authority.** The backend owns economics, time, rules, eligibility,
   previews, and settlement. Flutter explains decisions and submits commands.
9. **Graceful failure.** Insolvency causes arrears, suspension, receivership, and
   restructuring rather than arbitrary deletion/reset.
10. **AI-development clarity.** Every mechanic must have one canonical owner,
    formula, contract, and implementation phase.

---

# 3. Canonical V5 hierarchy

```text
EARTH UC
│
├── Constitution / global rules
├── Global Treasury
├── Global Bank
├── Global Market framework
├── Global Technology Programs
├── Progressive policy framework
├── Territory ownership / physical capacity authority
│
└── CORPORATIONS
      │
      ├── membership / admission
      ├── Corporation Charter / rules
      ├── Corporation Treasury / taxes
      ├── House capacity base rent
      ├── infrastructure / public spending
      ├── technology / R&D
      ├── local governance
      │
      └── HOUSES
            │
            ├── 1 residential capacity unit
            ├── CREDIT
            ├── resources
            ├── private buildings
            ├── investments / banking
            ├── market activity
            ├── automation
            └── dynasty / succession
```

Territory exists underneath this hierarchy as standardized physical capacity
owned by EARTH and consumed by Corporations. It is intentionally **not another
political layer**.

---

# 4. Responsibility of each layer

## 4.1 EARTH UC

EARTH UC is the civilization-wide authority. It owns/controls the global legal
framework and underlying standardized physical Territory capacity.

EARTH responsibilities:

- global Constitution and constitutional limits;
- CREDIT/monetary framework and authorized issuance/retirement rules;
- Global Bank framework;
- global Market framework;
- EARTH Treasury;
- global technology/research programs;
- universal progressive-bracket framework;
- EARTH base Territory/capacity rate;
- global fiscal programs and major planetary initiatives;
- cross-Corporation legal/order framework;
- world-level governance and proposals;
- Corporation receivership/dissolution rules where applicable;
- ownership of underlying Territory capacity.

EARTH must **not** micromanage ordinary House construction, Corporation
membership approvals, Corporation base House rent, or daily private decisions.

## 4.2 Corporation

Corporation is the one local political/economic institution that a House may
join. A House may have at most one active Corporation affiliation.

Corporation responsibilities:

- admission policy and membership;
- local governance;
- Corporation Charter/rules;
- Corporation Treasury;
- lawful Corporation taxes/fees;
- Corporation base House-capacity rent;
- public/infrastructure spending;
- local grants/programs;
- Corporation technology/R&D and technology adoption;
- public projects;
- fiscal management;
- arrears/receivership response for House capacity obligations;
- representation of members within EARTH-level systems where applicable.

Corporation does **not** own Houses' private buildings/resources merely because
those Houses are members.

## 4.3 House

House is the persistent private economic player and ownership boundary.

House responsibilities/assets:

- one active residential capacity unit while actively affiliated;
- CREDIT;
- five canonical physical resources;
- private buildings;
- market orders/trades;
- financial assets, deposits, debt;
- House automation policies;
- private investments;
- succession/dynasty continuity;
- private economic decisions.

A House attempts to build sustainable wealth through productive assets,
specialization, trade, investment, technology, and good liquidity management.

## 4.4 Human

Human is the mortal representative currently acting for a House.

Human may have:

- age/health/biography;
- personal standing;
- personal offices/roles;
- lifecycle/death/succession.

Human death does not destroy House assets, debts, contracts, Corporation
affiliation, or economic history unless an explicit rule says otherwise.

## 4.5 Territory

Territory in V5 launch is standardized scarce physical capacity.

Territory is **not**:

- a government;
- an independent tax authority;
- an independent constitution;
- a political membership layer;
- an independent House residence choice;
- a reason for separate House/building assignment while all units are identical.

Territory provides:

- physical capacity;
- the accounting/history basis for EARTH land/capacity rights;
- an automatic capacity-container count derived from Corporation occupancy;
- future extension point for genuinely differentiated geography.

## 4.6 Community

Community remains a voluntary many-to-many House association.

Community purpose:

- culture;
- professions/guilds;
- social coordination;
- mutual aid/social organization;
- communications.

Community does not become a duplicate Corporation. It does not need land,
Territory rent, sovereign taxes, or another full economic treasury by default.

---

# 5. Cardinality and relationship rules

| Relationship | V5 rule |
| --- | --- |
| House → Corporation | `0..1` active |
| Corporation → Houses | many |
| House → Communities | `0..N` |
| EARTH → Territory | owns/authorizes all |
| Corporation → standardized Territory units | derived `1..N` as needed |
| House → specific Territory unit | none in V5 launch |
| Building → specific standardized Territory unit | none in V5 launch |
| House → residential capacity | exactly 1 while active/affiliated, subject to lifecycle rules |
| House → productive capacity | sum of building footprints |
| Corporation occupied capacity | residential + eligible private/public footprints |

A future V5+ feature may introduce differentiated planetary/geographic Territory,
but that must be a new explicit design/ADR. V5 does not build other planets.

---

# 6. Territory capacity model

## 6.1 Standard Territory unit

EARTH defines one standard Territory capacity unit through versioned rules.
Illustrative shape:

```text
Standard Territory Unit
Physical Capacity: X units
Optional public-capacity accounting: Y units
```

Exact values are balance parameters.

## 6.2 Automatic Territory count

Corporation Territory-unit count is derived automatically:

```text
required_territory_units = ceil(total_occupied_capacity / standard_territory_capacity)
```

There is no ordinary gameplay button to “found Territory #4.”

When occupancy grows beyond current standardized container capacity, the world
creates/activates the next capacity container/audit record automatically.

When occupancy later falls sufficiently, excess empty standardized Territory
units may be surrendered/retired according to implementation rules without
moving individual Houses/buildings between identical units.

## 6.3 Real occupancy

A Corporation's occupied capacity is based on actual usage, not nominal member
counts alone:

```text
occupied_capacity =
  active_house_residential_units
  + active_private_building_footprints
  + included_public/institutional_footprints
```

Every active affiliated House consumes one residential unit even if it has no
productive building.

Inactive login status alone does not remove capacity. Economic/lifecycle status
controls eventual suspension/release.

---

# 7. Universal progressive economic model

V5 uses one progressive method everywhere progressive prices/taxes are needed:
**marginal brackets**.

Core rule:

> Each bracket applies only to the quantity inside that bracket. Crossing into a
> higher range never reprices earlier usage.

This is defined in detail in
`V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md`.

Primary V5 uses:

1. EARTH → Corporation occupied Territory/capacity charge;
2. Corporation → House residential/building capacity charge;
3. progressive taxes where authorized later/current rules require them.

Flat pricing/taxation is represented as one bracket rather than another engine.

---

# 8. EARTH → Corporation capacity economy

## 8.1 Billable quantity

Corporation EARTH charge is based on **actual occupied capacity**, normalized to
standard Territory equivalents where useful for policy display:

```text
territory_equivalent_usage =
  occupied_capacity / standard_territory_capacity
```

The authoritative billing function uses exact fixed-point/integer/numeric
semantics.

## 8.2 Base rate and progression

EARTH governance controls:

- EARTH base Territory/capacity rate;
- universal progressive bracket schedule;
- standard Territory capacity size where constitutionally permitted;
- effective date/rule version.

A large Corporation therefore faces a higher marginal capacity cost than a
small Corporation without an arbitrary maximum Corporation size.

## 8.3 Mandatory obligation

EARTH capacity rent is a mandatory Corporation obligation. Corporation members
may govern taxes, base House rent, budgets, and spending, but cannot retain
occupied EARTH capacity while choosing to ignore the lawful EARTH charge.

## 8.4 EARTH fiscal consequence

EARTH Territory/capacity revenue flows to the EARTH Treasury.

If world governance reduces EARTH revenue too far, consequences are real:

- discretionary global programs may be delayed;
- new global research may not start;
- grants/matching programs may be reduced;
- EARTH reserves may decline.

Core game-engine functionality and canonical ledgers do not stop working merely
because the discretionary EARTH Treasury is underfunded.

---

# 9. Corporation → House capacity economy

## 9.1 Billable House quantity

Each active affiliated House consumes:

```text
house_capacity_usage = 1 residential unit + sum(active billable building footprints)
```

The residential unit is simply the first/lowest progressive capacity unit. V5
avoids a separate hidden residential formula unless later balancing evidence
requires one.

## 9.2 Corporation base rate

Corporation governance controls one primary land/capacity pricing parameter:

```text
Corporation House Base Capacity Rate
```

EARTH controls the shape of the progressive schedule. Corporations cannot create
regressive/custom curves favoring large consumers.

## 9.3 Construction impact

Every construction/upgrade/demolition/capital action that changes footprint must
return an authoritative preview containing at least:

- current House capacity usage;
- capacity delta;
- resulting House usage;
- current daily capacity charge;
- resulting daily capacity charge;
- incremental daily capacity cost;
- Corporation occupied-capacity delta;
- blockers/eligibility.

The UI must not calculate these values independently.

---

# 10. Corporation admission

V5 supports exactly three admission policies:

## OPEN

Eligible Houses join immediately.

## APPROVAL

House submits an application. Authorized Corporation governance/roles accept or
reject it. This is the recommended/default V5 policy.

## INVITE_ONLY

House requires a valid server-side invite token. Tokens may have expiry and
maximum-use limits.

Membership admission never requires a Territory-expansion vote. Physical
capacity auto-scales as real occupancy grows.

Joining creates at least one new residential capacity unit and therefore changes
both Corporation EARTH cost and House Corporation rent according to current
marginal brackets.

---

# 11. Corporation founding

Founding is a consequential, server-quoted action.

Founding must define/validate at least:

- Corporation name/identity;
- founding House/Human authority;
- admission policy;
- Charter/rule version;
- founding/registration cost;
- required initial Corporation Treasury reserve if configured;
- first residential capacity requirement;
- current EARTH capacity policy implications;
- correlation/idempotency key.

A newly founded Corporation does not receive free profitable land. It pays the
EARTH capacity charge as members/assets occupy capacity.

Founding another Corporation must never be the cheaper exploit for escaping a
large Corporation's progressive land burden without the real political/economic
consequences of creating/leaving institutions.

---

# 12. Buildings and productive economy

Buildings remain the primary private productive assets.

A building has:

- canonical ownership scope;
- tier/blueprint/generation;
- footprint/capacity usage;
- construction cost/time;
- resource inputs;
- resource outputs/service capacity;
- explicit operating CREDIT cost where applicable;
- operating policy/state;
- authoritative lifecycle state.

A private building does not create CREDIT merely because it exists. CREDIT
income must come from explicit economic activity, transfers, market sales,
service rules, contracts, investment return, or other defined source.

Buildings consume scarce House/Corporation capacity. Consequently, higher
productivity per capacity unit becomes a major long-term strategic dimension.

---

# 13. Technology and long-term progression

V5 retains tiered/predefined building blueprints and general Corporation
technology/R&D but requires all economic effects to be authoritative.

Long-term progression should not depend on unlimited building tiers. It comes
from a combination of:

- better technology/blueprints/generations;
- higher productivity per scarce capacity unit;
- market specialization;
- Corporation technology strategy;
- infrastructure/public investment;
- financial/investment choices;
- governance/fiscal policy;
- House diversification and succession.

Research lifecycle:

```text
RESEARCH → UNLOCK/ACCESS → DEPLOY/BUILD/UPGRADE
```

Research completion does not silently upgrade every building unless the
canonical technology effect explicitly defines automatic adoption.

---

# 14. Market

EARTH has one global resource Market for the five physical resources quoted in
CREDIT.

V5 preserves the batch/limit-order architecture unless a later ADR changes it.

Market responsibilities:

- global price discovery;
- specialization between Houses/Corporations;
- escrow/reservations;
- partial fills;
- authoritative fees;
- price history;
- resource redistribution.

Market does not become Corporation-local merely because capacity is locally
priced.

---

# 15. Finance and banking

House Finance should answer:

1. how much CREDIT is actually available to spend/trade;
2. what happens at the next settlement;
3. what mandatory obligations are upcoming;
4. what CREDIT is reserved/locked/invested/borrowed;
5. why balances changed.

Capacity rent must be represented as a canonical obligation/transaction, not
hidden inside UI math.

Corporation Finance should expose:

- taxes/fees;
- House capacity-rent revenue;
- EARTH capacity-rent expense;
- public/infrastructure spending;
- R&D spending;
- obligations/arrears;
- Treasury/reserve position.

EARTH Finance should expose equivalent high-level global fiscal flows.

---

# 16. Automation

House Automation remains a server-evaluated daily policy system. It may manage
resource reserve targets and Market orders but cannot bypass normal economic
systems.

Capacity obligations are not optional automation decisions. They settle as
mandatory obligations according to the active rule/version.

Automation must be predictable before acting and explainable after acting.

---

# 17. Governance

There are two meaningful governing levels:

```text
EARTH governance
Corporation governance
```

Territory has no separate governance tier in V5 launch.

## EARTH proposal examples

- amend global progressive bracket schedule;
- amend EARTH base Territory rate;
- constitutional amendments;
- global technology programs;
- global fiscal programs;
- major global initiatives.

## Corporation proposal examples

- change Corporation House base capacity rate;
- change Corporation tax rules;
- budget/public spending;
- technology/R&D spending;
- infrastructure/public projects;
- admission policy where governance controls it;
- major local rules.

Every financially meaningful proposal should use a server-side impact preview
showing current/proposed revenue, expenses, affected population ranges, Treasury
impact, and effective date where feasible.

---

# 18. Fiscal policy and taxes

V5 deliberately supports progressive policy as a reusable concept.

Important separation:

- Territory/capacity rent is payment for scarce physical capacity;
- taxes are lawful fiscal transfers under tax rules;
- fees are charges for specific economic/institutional actions;
- budgets are spending authority;
- Treasury is actual cash.

Do not use ambiguous UI labels such as “Local Tax” for multiple unrelated rules.

All progressive taxes/charges should use the same marginal bracket engine where
progression is desired.

---

# 19. Arrears, insolvency, and resolution

## 19.1 House capacity non-payment

Suggested state progression:

```text
CURRENT
→ ARREARS
→ GRACE
→ EXPANSION_BLOCKED
→ PRODUCTIVE_CAPACITY_SUSPENDED
→ MOTHBALL / LIQUIDATION
→ PRODUCTIVE_CAPACITY_RELEASED
```

Principles:

- obligation/history is never silently erased;
- normal missed payment does not instantly delete buildings;
- no new capacity may be consumed while delinquent after the configured stage;
- productive assets may be suspended before liquidation;
- liquidation proceeds follow lawful priority;
- the House/residential continuity rule is handled deliberately, not by accidental
  cascade deletion.

## 19.2 Corporation EARTH non-payment

Suggested progression:

```text
CURRENT
→ EARTH_RENT_ARREARS
→ GRACE
→ EXPANSION/SPENDING_RESTRICTIONS
→ EARTH_RECEIVERSHIP
→ RESTRUCTURING
→ DISSOLUTION (last resort)
```

EARTH receivership may lawfully intercept eligible Corporation revenue to cure
arrears if enabled by rules. Existing House assets must not be immediately
destroyed because the Corporation defaulted.

---

# 20. Daily settlement responsibilities

The exact technical phase order is frozen in implementation docs, but gameplay
requires settlement to reconcile at least:

- opening balances/inventory;
- building production/consumption;
- services/needs where active;
- market settlement/escrow effects;
- taxes/fees;
- House capacity rent;
- Corporation EARTH capacity rent;
- debt/interest/contractual obligations;
- R&D progress/funding effects;
- arrears and insolvency state transitions;
- daily statements/history/outbox;
- day-close barrier.

The UI must consume resulting statements/read models rather than attempting to
simulate these phases itself.

---

# 21. Player daily loop

A normal active player should be able to play efficiently without touching every
system every game day.

Typical loop:

1. Open Overview: check House state and important issues.
2. Read Daily Briefing: understand the completed day.
3. Resolve shortages/liquidity/market problems.
4. Review construction/upgrade/research opportunities.
5. Manage Market orders or Automation when useful.
6. Review governance decisions/deadlines.
7. Make occasional long-term investment/Corporation choices.

The game should reward decisions, not repetitive clicks.

---

# 22. Long-term House loop

```text
START SMALL
→ secure basic production/liquidity
→ specialize
→ trade
→ expand productive buildings
→ pay higher marginal capacity costs
→ improve productivity per slot through technology
→ invest/diversify
→ participate in Corporation governance
→ survive economic cycles
→ handle Human succession
→ compound House wealth/legacy
```

A large House should face increasingly expensive marginal land/capacity, making
technology and capital efficiency more valuable than simply adding unlimited
low-tier buildings.

---

# 23. Long-term Corporation loop

```text
FOUND / JOIN
→ attract/select Houses
→ collect taxes + capacity rent
→ pay EARTH capacity rent
→ build Treasury/reserves
→ fund infrastructure + technology
→ balance low member costs vs fiscal strength
→ grow occupancy
→ enter higher EARTH marginal capacity brackets
→ remain competitive through productivity/governance
→ handle arrears/receivership risk if mismanaged
```

Large Corporations are allowed; they simply face increasing marginal physical
capacity cost, creating a natural anti-concentration pressure without hard caps.

---

# 24. Long-term EARTH loop

EARTH-level governance balances:

- affordable global physical capacity;
- sufficient Treasury revenue;
- global R&D/program funding;
- progressive anti-concentration policy;
- monetary stability;
- cross-Corporation fairness/order.

Players may collectively make fiscally poor EARTH decisions. The world should
show transparent consequences rather than automatically correcting every policy.

---

# 25. UI/navigation implications

V5 target navigation should not preserve pages solely because V4 had them.

Notable implication:

- Society → Territories is not required as an independent V5 launch management
  page because Houses/buildings do not choose specific standardized Territory
  units.
- Capacity/land information belongs primarily in My Corporation, Corporation
  directory/profile, Building previews, House Finance, and relevant governance.
- A global read-only Land/Capacity page may exist later if it provides real
  comparative value.

Detailed page changes are defined in `V5_UI_MIGRATION_MATRIX.md`.

---

# 26. Server-authoritative UI rule

The following must never be calculated from duplicated Flutter formulas when
consequential:

- balance/available CREDIT;
- next settlement;
- taxes/rent;
- progressive charges;
- building production/costs;
- research cost/effects/duration;
- market fees/escrow/clearing time;
- governance thresholds/outcomes;
- eligibility;
- insolvency state;
- proposal financial impact;
- Territory-equivalent/occupied-capacity billing.

Flutter may interpolate purely visual progress from an authoritative projection
but may not own the economic rule.

---

# 27. Explicit non-goals for V5 launch

Do not add these simply because the domain model could support them:

- other planets;
- differentiated Territory geography;
- House freehold land ownership;
- Corporation-to-Corporation Territory trading;
- Territory parliament/government;
- Territory-specific tax systems;
- local currencies;
- local isolated commodity markets;
- unlimited custom progressive formulas per Corporation;
- generic IFTTT automation;
- unbounded building tiers;
- automatic destruction of delinquent player assets;
- client-side economic fallbacks disguised as real values.

---

# 28. V5 success criteria

V5 gameplay is successful when:

- a new player can explain EARTH, Corporation, House, Human, and Territory in one
  sentence each;
- joining a Corporation is meaningful but does not create a third governance
  relationship;
- every House pays a small real cost for existing and progressively more for
  consuming large physical capacity;
- every Corporation pays EARTH progressively for actual occupied capacity;
- large actors can grow but face rising marginal scarcity cost;
- Corporation admission/fiscal policy creates distinct strategies;
- EARTH policy decisions visibly affect the global Treasury/programs;
- Houses can remain viable through specialization and global trade;
- insolvency resolves gradually and auditably;
- no critical economy page needs Flutter to guess the authoritative result;
- daily play centers on decisions rather than repetitive administration.
