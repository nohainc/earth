# The EARTH Constitution

Status: authoritative world rules  
Version: 1.0  
Scope: all gameplay, settlement, APIs, workers, and database procedures

This document defines the rules that make EARTH the same world across
production, local development, replay, recovery, and catch-up. It contains
principles and boundaries, not balance numbers. Rates, costs, capacities, and
other tunable values belong in versioned catalogs and rule records governed by
these clauses.

## Rule hierarchy

Rules are interpreted in this order:

1. This Constitution defines non-negotiable world invariants.
2. `GAME_ECONOMY_SPEC.md` defines the shared economic model and formulas.
3. Versioned catalogs and governance rules define time-bounded parameters.
4. Application code implements those rules and may not create a competing
   authority.

When two lower-level sources disagree, the versioned database rule selected
for the settlement game day wins. Historical rules are immutable.

## Fundamental rules

### CONST-TIME-001 — World time

EARTH is governed by authoritative PostgreSQL game time. Economic and daily
gameplay settlement occurs by complete game day, independent of the number of
Cron deliveries or Worker invocations.

### CONST-TIME-002 — Daily economic period

The complete game day is EARTH's fundamental economic accounting period.
Production, consumption, services, needs, taxes, interest, research, license
fees, and institutional payments are calculated and settled per game day.
Months, quarters, and years are aggregation, reporting, or planning periods;
they must not replace daily cash-flow calculation or derive gameplay values by
dividing a longer-period value by a number of days.

### CONST-MONEY-001 — Monetary authority

Economy V2 is the sole authority for CREDIT balances and monetary history.
`economic_accounts` hold balances; `economic_transactions` and
`economic_entries` record value movement.

### CONST-MONEY-002 — Credit creation

Only explicitly authorized monetary issuance may create CREDIT. Every issuance
and retirement must identify its rule version, source, reason, game day, and
correlation ID. Ordinary gameplay, banking, taxation, research, buildings,
markets, budgets, and succession move existing CREDIT; they do not create it.

### CONST-ASSET-001 — Physical resources

EARTH has five canonical physical resources: Material, Components, Energy,
Compute, and Food. Production and consumption use explicit source/sink or
counterparty accounting and are reconciled with the Economy V2 ledger.

### CONST-OWNER-001 — Property and ownership

Houses, Cities, and Corporations may own economic assets only through the
canonical owner/economic-account model. A read projection is never an
independent balance authority.

### CONST-HOUSE-001 — House continuity

A House is the persistent player identity and economic principal. A Human is a
mortal representative. House property, contracts, debts, affiliations, and
economic history survive Human succession; personal offices and personal
standing do not automatically survive.

### CONST-MARKET-001 — Central Spot Market

EARTH has one central Spot Market for the five physical resources. Orders,
escrow, batches, matching, fills, and price history use the shared Spot
architecture. Delivery Futures and derivative settlement are not part of the
world.

### CONST-BUILDING-001 — Buildings

Buildings consume defined physical inputs and explicit operating expenses, and
produce physical resources or service capacity. A building does not create
CREDIT merely by being active or by catalog configuration. Routine repair and
condition-degradation gameplay are not constitutional mechanics.

### CONST-TAX-001 — Lawful taxation

Taxes require an authorized, immutable, versioned rule effective for the
settlement game day. Tax rules cannot apply retroactively. An unpaid lawful tax
remains an obligation or arrears; it is not silently erased and does not make a
normal balance negative.

### CONST-BUDGET-001 — Fiscal vocabulary

Budget is spending authority. Treasury is cash. A commitment is a promise.
Spending is an actual Economy V2 transfer. Grants are transfers between
institutions and are not recipient spending merely because they increase cash.

### CONST-CITY-001 — Cities

Cities are public institutions. Financial distress is handled through defined
stress, receivership, and recovery rules. Ordinary lack of cash does not
silently delete a City or erase its residents and obligations.

### CONST-CORP-001 — Corporations

Corporations are collective economic institutions. Distress, restructuring,
liquidation, creditor priority, and dissolution follow explicit rules and
preserve accounting history.

### CONST-GOV-001 — Governance

Rules and institutional authority change only through authorized governance
procedures. Historical decisions, ballots, and rule versions are immutable
records.

### CONST-RESEARCH-001 — Research

Corporation research unlocks predefined building blueprints and technologies.
Research is funded through Economy V2 and progresses from institutional
research capacity, not arbitrary hidden time counters.

### CONST-IP-001 — Patents

Only explicitly configured technologies may receive patents. Patent rights are
time-limited, versioned, and corporation-owned. Licenses are explicit
corporation-to-corporation Economy V2 contracts.

### CONST-SUCCESSION-001 — Succession

House property survives Human death. Succession changes representation, not
the existence or ownership of the House's persistent economic world.

### CONST-INSOLVENCY-001 — Insolvency

Insolvency and resolution use actual assets, liabilities, obligations, and
priority rules. They may not reset balances or erase debts through direct field
assignment.

### CONST-AMEND-001 — Constitutional amendments

This Constitution may change only through a special constitutional amendment
process. A normal balance, catalog, scheduler, or product change cannot weaken
or bypass a constitutional invariant.

## Change control

Any implementation change that alters one of these clauses must update this
document's version, the compliance map, relevant versioned rules, and the
certification tests in the same change set.
