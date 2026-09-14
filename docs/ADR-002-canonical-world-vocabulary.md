# ADR-002: Canonical world vocabulary

- Status: Accepted
- Date: 2026-09-14
- Owners: EARTH product and engineering
- Scope: World model, domain language, data model, API contracts, UI copy, and
  future specifications
- Supersedes: ambiguous or competing uses of these terms in design material

## Decision summary

EARTH freezes the following canonical vocabulary:

| Term | Canonical meaning |
|---|---|
| **Corporation** | A local polity: the bounded civic, legal, and institutional authority that governs a local society. |
| **Territory** | Geography: a bounded physical area, including its locations, boundaries, and spatial relationships. |
| **House** | A persistent private owner: the continuing private economic principal whose property and obligations survive changes of representative. |
| **Human** | A representative: a mortal person who currently acts for a House and may hold personal offices, standing, and biography. |
| **EARTH** | The global authority: the world-level authority that defines and enforces the global framework, shared rules, and cross-polity order. |

These meanings are normative. Future specifications, code, database names,
API fields, events, tests, and user-facing text must use these terms according
to the definitions above unless an ADR explicitly changes this decision.

## Context

EARTH contains several related but non-identical layers: a global rule system,
local civic organization, physical geography, persistent private ownership,
and mortal representation. If the same word is used for more than one layer,
authority, ownership, geography, and identity become difficult to reason about.

The existing House/Human continuity model already establishes that a House
survives the death or replacement of its Human. This ADR makes that distinction
part of the wider world vocabulary and separates it from Corporation, Territory,
and EARTH.

## Boundary rules

### Corporation is not Territory

A Corporation is a governing institution or polity. A Territory is the physical
space to which geography and jurisdiction may refer. A Corporation may govern,
administer, or have jurisdiction over Territory, but the two are not
interchangeable. A change in institutional control does not erase the
underlying geography.

### Corporation is not House

A Corporation is local public or civic authority. A House is a private,
persistent owner. A House may participate in, own interests within, or be
represented before a Corporation, but it is not itself the Corporation.

### House is not Human

A House is the persistent owner and continuity boundary. A Human is its current
mortal representative. Human succession changes representation; it does not,
by itself, transfer or dissolve House property, contracts, debts, affiliations,
or economic history.

### EARTH is not a local Corporation

EARTH is the global authority and must not be modeled as merely another local
polity. Local Corporations operate within the global framework established by
EARTH. Global authority, local jurisdiction, and private ownership remain
separate concepts even when a rule or institution connects them.

### Territory is not ownership

Territory describes place and spatial extent. It does not, by itself, identify
the private owner, the governing Corporation, or the Human currently acting in
that place.

## Required language

Use the following distinctions in future work:

- “Corporation authority” for local civic or institutional power.
- “Territory” or “territorial boundary” for geographic scope.
- “House ownership” or “House property” for persistent private assets and
  obligations.
- “Human representative” for the current mortal actor.
- “EARTH authority” for global rules, institutions, and cross-polity order.

Avoid using “corporation” as a synonym for a House, “territory” as a synonym
for ownership, or “human” as a synonym for the persistent player identity.

## Consequences

- Domain models must keep the five concepts distinct even when they are linked
  by relationships.
- Ownership and succession rules attach to House unless a rule explicitly
  concerns a Human's personal status or office.
- Geographic queries and boundaries attach to Territory.
- Local civic governance attaches to Corporation.
- Global governance and cross-polity rules attach to EARTH.
- New schemas and APIs should prefer explicit names such as `houseId`,
  `humanId`, `corporationId`, and `territoryId`; overloaded identifiers should
  not be introduced.
- This ADR is a vocabulary freeze only. It does not by itself create database
  migrations, endpoints, gameplay mechanics, or implementation changes.

## Compliance requirement

Before implementation begins for a later phase, the affected specification,
data model, API contract, and tests must be checked for terminology that
violates this ADR. A terminology conflict is a design issue to resolve before
code is merged, not a local naming preference.

