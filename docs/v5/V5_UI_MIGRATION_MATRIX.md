# EARTH Gameplay V5 — UI Migration Matrix

Status: **TARGET-UX / IMPLEMENT AFTER BACKEND AUTHORITY**

## Purpose

This document maps the current major pages reviewed during V5 design to their
V5 target role. It is not permission to implement UI ahead of authoritative
backend/read models.

General rule:

> The client presents server-derived state, quotes, previews, deadlines, and
> consequences. It does not recreate economic formulas.

---

# Command

## Command → Overview

### V5 purpose
Answer:

1. What is my House's current situation?
2. What requires attention now?
3. What are my most important current positions?

### Keep

- House/current Human identity;
- high-level financial/resource/building state;
- contextual deep links.

### Remove/change

- all invented fallback values;
- client-synthesized decision queue;
- client-synthesized objectives/rewards;
- old Business/Machine terminology;
- duplicated Daily Briefing content;
- arbitrary client solvency/status labels;
- hard-coded claims such as ledger “Audited”.

### Add

- canonical `OverviewSummary`;
- server Attention Queue;
- Available/Reserved CREDIT;
- capacity/rent warning when relevant;
- compact last-completed-day strip.

---

## Command → Daily Briefing

### V5 purpose
Tell the story of the last completed game day for the House.

### Structure

```text
DAY RESULT
WHAT CHANGED
NEEDS ATTENTION
(optional MARKET / TECHNOLOGY / GOVERNANCE sections when meaningful)
```

### Must include when relevant

- CREDIT flow;
- resource production/consumption/net;
- House capacity rent;
- arrears;
- building completions/inactivity;
- research milestones;
- governance events/deadlines;
- exceptions/failed obligations.

### Remove/change

- “Since your last visit” unless last visit is actually tracked;
- unsupported Net Worth fields;
- static current-operation metrics that belong on Overview;
- generic directive codes shown directly to players.

---

## Command → News

### V5 purpose
Public/world intelligence outside the House.

### Target

- server-owned News publication model;
- explicit scope/topic/importance;
- day/time chronology;
- story detail;
- related entity/deep links;
- cursor/load-earlier pagination.

### Do not
Build News by guessing from arbitrary event strings in Flutter.

---

# House

## House → House / User

Keep House as persistent private identity and Human as current representative.
V5 capacity/rent belongs to House economics, not Human ownership.

Show when useful:

- Corporation affiliation;
- residential capacity unit as part of House estate/capacity summary;
- succession continuity.

Do not present Territory #N residency in V5 launch.

---

## House → Finance

### V5 purpose
House Treasury/liquidity command center.

### Target sections

```text
OVERVIEW
BANKING
ACTIVITY
```

### Key metrics

- Available to Spend;
- next settlement;
- protected/reserved CREDIT;
- debt;
- upcoming obligations;
- House capacity rent and arrears.

### Required changes

- server-authoritative next settlement;
- safe loan quote → review → accept;
- canonical transaction activity;
- rent visible as explicit obligation;
- remove implementation/debug language.

---

## House → Automation

### V5 purpose
Predictable daily House resource/Market automation.

### Target

- one automation configuration;
- ON/OFF + per-resource buy/sell enablement;
- current/scheduled policy;
- server Next Run Preview;
- execution history;
- correct player-facing units.

Capacity rent is mandatory settlement and is not an automation rule.

---

# Society

## Society → My Corporation

### V5 role
This becomes the primary local-institution page and receives the former
Territory-capacity management information.

### Add `LAND & CAPACITY`

Show:

- active standardized Territory units;
- total physical capacity;
- occupied capacity;
- utilization;
- member residential units;
- private/public footprint totals;
- Corporation House base capacity rate;
- current progressive-policy summary;
- House capacity-rent revenue;
- EARTH capacity expense;
- land/capacity margin;
- arrears/distress state where applicable.

Leaders/governance see proposal actions; ordinary members see policy/results.

---

## Society → Corporations

### V5 purpose
Discover/compare local polities and decide where the House belongs.

### Card/profile metrics

- membership/admission policy;
- members;
- capacity utilization;
- Corporation House base capacity rate;
- representative House rent examples;
- relevant taxes/fees;
- Treasury/fiscal health at appropriate visibility;
- technology/R&D strength;
- arrears/distress;
- Communities remain separate.

### Required flows

- `OPEN`, `APPROVAL`, `INVITE_ONLY`;
- review joining consequences;
- pending application/invite state;
- proper founding wizard/quote.

### Remove

- invented/default policy/tax values;
- ambiguous “Local Tax”;
- cross-Corporation fallback data;
- generic Organization ambiguity for Corporation affiliation.

---

## Society → Territories

### V5 launch recommendation
Remove from primary navigation or repurpose as a read-only global land/capacity
view only if it provides real comparative value.

Reason: standardized Territory units are pooled Corporation physical capacity;
Houses/buildings do not select Territory #1/#2/#3.

Do not keep a page merely to list identical Territory records.

---

## Society → Communities

Keep the current conceptual model:

- voluntary;
- many memberships;
- cross-Corporation social/professional associations;
- no sovereign land/tax system.

Fix membership/pending/open semantics and make `Your Communities` first-class.

---

## Society → Governance

### V5 governance scopes

```text
EARTH
CORPORATION
```

Territory is not a third government scope.

### Add

- progressive-policy proposals;
- EARTH base capacity-rate proposals;
- Corporation House base-rate proposals;
- server impact previews;
- action-needed first;
- correct turnout/quorum/decisive-vote semantics.

### Remove/change

- Territory-government assumptions;
- client-selected first governance rule;
- invented proposal consequences;
- vote buttons before full review.

---

# Economy

## Economy → Buildings

### V5 purpose
Manage scarce-capacity productive assets.

### Every construction/upgrade preview must show

- footprint;
- current House capacity usage;
- resulting usage;
- current capacity rent;
- resulting capacity rent;
- incremental daily land/capacity cost;
- canonical production/operating changes.

### Page target

- Portfolio Summary;
- Needs Attention;
- Private / Civic/Public;
- My Buildings / Build Catalog;
- net/day first;
- server-authoritative quotes.

### Remove

- client fallback economics;
- stale City terminology;
- fake success after cancelled actions;
- synthetic institution IDs.

---

## Economy → Market

Keep global Market.

V5 changes are mostly authority/clarity:

- Last Clearing Price terminology;
- server next-clearing schedule;
- Available/Reserved balances;
- one canonical order ticket;
- server fee/escrow preview;
- recent fills/trades;
- cross-links from shortages in Buildings/Daily Briefing.

---

## Economy → Technology

### V5 purpose
Improve productivity/capability so large actors can justify progressively more
expensive capacity.

### Keep

- Building Blueprints/Tiers;
- Corporation Technologies;
- R&D progress/history;
- governance for public/civic research where applicable.

### Required

- canonical catalog DTO;
- no Flutter tier formulas/fallback catalog;
- server research quote/effects/duration;
- correct Corporation R&D funding;
- Research → Unlock → Deploy.

### Optional later

IP & Licenses tab after core R&D is stable.

---

# World

## World → Constitution

Update only through the constitutional V5 amendment phase. Do not silently make
Territory a government again.

The player-facing Constitution should clearly communicate:

- EARTH global authority;
- Corporation local authority;
- House private continuity;
- Territory physical capacity role;
- lawful progressive policy/governance.

---

## World → Conditions

Keep as global/world condition system. Conditions may affect economics but must
not create a hidden third Territory government.

---

## World → Initiatives

Good destination for EARTH-funded global programs. V5 EARTH Treasury constraints
should determine whether initiatives can be funded/started.

---

## World → Rankings / Memorial

No core V5 land changes required. Any wealth/ranking calculation must remain
server-authoritative and not treat Territory container count itself as private
wealth.

---

# Navigation target summary

A likely V5 navigation direction:

```text
COMMAND
  Overview
  Daily Briefing
  News

HOUSE
  House
  Human/Citizen
  Finance
  Automation

SOCIETY
  My Corporation
  Corporations
  Communities
  Governance

ECONOMY
  Buildings
  Market
  Technology

WORLD
  Constitution
  Conditions
  Initiatives
  Rankings
  Memorial
```

Exact labels remain a product decision, but **Territories should not remain a
primary management page if there is no player decision attached to specific
Territory units**.

---

# Shared V5 UI requirements

1. No fabricated fallback economics.
2. Unknown data is shown as unknown/unavailable, never as plausible defaults.
3. Consequential actions use Review/Quote/Confirm.
4. Server returns eligibility/blockers.
5. Progressive charges show total and incremental impact.
6. Governance proposals show current/proposed fiscal effects.
7. IDs are secondary/debug details, not primary labels.
8. Technical “architecture/server-authoritative/idempotent” wording is removed
   from player UI.
9. Use consistent CREDIT/capacity/resource terminology.
10. Responsive behavior follows `AI_DEVELOPMENT_INSTRUCTIONS.md` and
    `FLUTTER_ARCHITECTURE.md`.
