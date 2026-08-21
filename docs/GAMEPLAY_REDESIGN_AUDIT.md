# Gameplay Redesign Audit

This checklist tracks the implementation of the management-first redesign.
Status is intentionally evidence-based: **implemented** means visible in the
current client and supported by the current domain data; **partial** means the
direction exists but gameplay or backend support is incomplete.

## Phase 1 — Reframe the game

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Manager-oriented navigation | Implemented | The sidebar uses expandable, single-open categories including Business, Corporation, City, Life & Dynasty, and Technology. |
| Business is a primary destination | Implemented | `Businesses & Operations` is the main management entry. |
| Market is supporting infrastructure | Implemented | Market is renamed `Trade & Supplies`; basic signals are primary, while order books, open orders, macro liquidity, and derivatives are behind advanced disclosure. |
| Command Center prioritizes decisions | Implemented | Executive summary, objectives, decision queue, and management quadrant are rendered as the primary Command Center content; resource flows remain secondary context. |

## Phase 2 — Business and earning loop

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Revenue and profit are visible | Implemented | Business page shows revenue, costs, profit, margin, and taxable base. |
| Production and machines are business-owned | Implemented | Machine inventory and production events render under Business. |
| Staff/workforce gameplay | Implemented | Migration 041 adds employees; the Business page displays workforce capacity and payroll; PostgreSQL-backed hire, train, dismiss, role reassignment, wage changes, and daily payroll/morale settlement actions are wired. |
| Diverse service businesses | Implemented | Registration/catalog includes IT services, consulting, logistics, healthcare, and education; active staffed service businesses now generate server-authoritative daily revenue based on staff skill and morale. |
| Expansion and reinvestment loop | Implemented | Business registration, machine acquisition/upgrades, staffing, training, contracts, share actions, mergers, dividends, and portfolio-derived objectives provide reinvestment decisions. |

## Phase 3 — Technology and organizational development

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Technology owns research and patents | Implemented | Technology page is framed around research, patents, licensing, and capability focus. |
| Machines removed from Technology | Implemented | Machines are rendered in Business only. |
| Technology affects business outcomes | Implemented | Research focus is applied server-side to production wear/output behavior, while the Technology and Business surfaces explain the capability impact. |
| AI is operational and bounded | Implemented | AI panels render under Business and the AI guide requires explicit approval and authoritative commands. |

## Phase 4 — Life, city, corporation, and governance

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Life and legacy are visible domains | Implemented | Life & Legacy and Family & Dynasty are primary navigation areas with persistent lineage, perks, heirlooms, cemetery records, and succession choices. |
| City affects the player and business | Implemented | City service pressure adds operating friction, generates crisis notifications and decisions, and presents voluntary migration opportunities rather than moving residents automatically. |
| Corporation membership is strategic | Implemented | Membership remains optional, city and corporation affiliation stay consistent, and corporation membership provides server-authoritative revenue network benefits. |
| Laws and taxes affect decisions | Implemented | Tax rules are applied by the scheduler and the Public Finance UI now explains their personal, business, property, and resource consequences before action. |
| Shared civic and corporate projects | Implemented | Institution projects are visible to members, accept member contributions, improve city services or corporation resilience on completion, and count toward dynasty objectives. |

## Phase 5 — Advanced economy

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Basic trade supports production | Implemented | Market supports all five commodities and deferred orders. |
| Advanced analytics are secondary | Implemented | Advanced market destinations are hidden from the main sidebar and order-book/analytics content is inside `ADVANCED TRADE TOOLS`. |
| Derivatives are optional | Implemented | Derivatives are reachable through the advanced trade disclosure and are no longer primary navigation. |

## Phase 6 — Continuous world and dynasty play

| Requirement | Status | Evidence / remaining work |
| --- | --- | --- |
| Production world engine is not a separate player mode | Implemented | The persistent PostgreSQL/Worker world clock and scheduled engines are the game loop; scenario simulation remains developer-only verification. |
| Death and continuation | Implemented | A deceased or estate character can continue as a designated heir or create a new adult through Civic Rebirth; lineage, dynasty identity, and equipped heirlooms continue across generations. |
| Player agency over residence | Implemented | City movement is voluntary and corporation entry/movement cannot leave an inconsistent city network. |
| Consequence-driven civic play | Implemented | Power and health crises create world events, notifications, and actionable city decisions. |
| Institution development competition | Implemented | City and corporation rankings use service quality, population, productive businesses, and resilience rather than treasury alone. |

## Cross-cutting requirements

- PostgreSQL remains authoritative for the Worker API and economic outcomes.
- Client recommendations must not silently execute sensitive actions.
- UI should present a decision before supporting analysis.
- Future AI-assisted work follows [`AI_DEVELOPMENT_GUIDE.md`](AI_DEVELOPMENT_GUIDE.md).

## Final verification

- Full Flutter regression suite: 170 tests passed.
- Full Flutter analysis: completed with no compile errors; remaining output is
  pre-existing style/deprecation guidance.
- Worker dry-run: passed with PostgreSQL authority and current bindings.
- Local PostgreSQL remains the manual production-like persistence path; the
  local Node server and scenario runner are compatibility/balance tools only.
- Formatting/static checks: passed.
