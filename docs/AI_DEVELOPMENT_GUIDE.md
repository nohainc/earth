# EARTH AI Development Guide

This document defines how future AI-assisted development should extend EARTH.
It is a product and architecture guardrail, not a replacement for the API or
database contracts.

## Product north star

EARTH is a persistent life-and-management game. The player is a person who
builds a life, manages staff and machines, operates businesses, earns credits,
joins or influences institutions, and leaves a legacy. Markets, analytics, and
simulation are supporting systems for those decisions.

Every new feature should make at least one of these player responsibilities
more meaningful:

- earn income;
- manage people, machines, or organizations;
- improve a capability through technology;
- choose where and how to live;
- influence a city, corporation, or law;
- create long-term security and legacy.

Features that only add another dashboard, metric, chart, or event feed require
explicit justification and should normally be progressive disclosure.

## Domain ownership

| Domain | Owns | Does not own |
| --- | --- | --- |
| Life | cash, housing, health, family, succession, personal choices | business fleet operations |
| Business | staff, machines, production, customers, contracts, revenue, costs, expansion | research/IP strategy |
| Technology | research, breakthroughs, patents, licenses, capability upgrades | physical machine inventory |
| Society | city services, laws, taxes, corporations, membership, civic influence | private order-book trading |
| Trade | buying inputs, selling output, supply conditions, optional advanced trading | the player's core identity |

## UI rules for AI-generated work

1. Put the decision before the analysis.
2. Use plain player language before domain terminology.
3. Give every major card one clear next action.
4. Keep advanced charts, order books, audit trails, and historical analytics
   behind an expansion, secondary tab, or dedicated advanced view.
5. Never place machine inventory in Technology.
6. Never make the Market the default destination for an income question;
   direct the player to Business first.
7. Show consequences in credits, staff, capacity, quality, reputation, city
   access, or legacy—not only abstract percentages.
8. Preserve responsive layouts and accessible labels.

## Decision model

The preferred loop is:

1. Show the player's current situation.
2. Explain what changed and why it matters.
3. Present one or more decisions.
4. Preview the likely cost and consequence.
5. Submit player intent to the authoritative API.
6. Refresh canonical state and report the result.

The client must not invent settlement, money, ownership, governance, or
research outcomes. PostgreSQL-backed Worker endpoints remain authoritative.

## AI recommendations

AI assistants and recommendations may summarize state, identify risks, rank
opportunities, and explain trade-offs. They must not silently execute economic,
civic, ownership, or lifecycle actions. Recommendations should include:

- the source facts used;
- the affected domain and entity;
- expected upside and downside;
- confidence or uncertainty when applicable;
- an explicit user action to approve or dismiss.

Sensitive actions—payments, transfers, hiring, firing, voting, company
formation, machine acquisition, research funding, and succession—require an
explicit player command and server-side authorization.

## Delivery checklist

Before merging AI-assisted changes, verify:

- the feature belongs to the correct domain owner;
- the primary screen answers a player decision, not merely a reporting need;
- revenue and management paths remain visible;
- market analysis is secondary unless the feature is explicitly advanced trade;
- API commands are idempotent and server-authoritative;
- tests cover authorization, persistence, and the visible decision state;
- the relevant Flutter screen remains usable at narrow and wide widths;
- documentation explains the player value and the consequence model.

