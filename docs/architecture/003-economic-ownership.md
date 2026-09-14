# ADR-003: Economic ownership and account capabilities

- Status: Accepted
- Date: 2026-09-14
- Scope: Economic principals, account purposes, asset ownership, resource
  production and consumption, public infrastructure, and resource markets
- Depends on: [Subsidiarity and responsibilities](002-subsidiarity-and-responsibilities.md)

## Decision

EARTH uses one economic ownership model:

> Houses own the physical economy. Institutions operate primarily with CREDIT.

The supported economic principals are exactly:

| Principal | CREDIT | Resources | Resource market | Buildings |
|---|---:|---:|---:|---|
| **House** | Yes | Yes | Yes | Private buildings |
| **Corporation** | Yes | No | No | Public infrastructure |
| **EARTH UC** | Yes | No | No | Global/public projects only when authorized |
| **Global Bank** | Yes | No | No | Normally none |
| **Territory** | No | No | No | Location only |
| **Human** | No persistent ownership | No | Acts for House | Does not own House economic state |
| **Building** | No independent wallet | No independent ownership | No | The asset itself |
| **SYSTEM** | Technical only | Technical only | Clearing/issuance only | None |

This ADR is the authoritative answer to questions such as:

> Can a Corporation own FOOD?

**No.** A Corporation may fund or operate public infrastructure, but normal
resource balances belong to Houses. A Corporation's economic accounts are
financial accounts denominated in CREDIT.

## Asset classes

The unified asset system contains:

- `CREDIT`: universal financial purchasing power.
- `MATERIAL`: physical production resource.
- `COMPONENTS`: physical production resource.
- `ENERGY`: physical production resource.
- `COMPUTE`: physical production resource.
- `FOOD`: physical production resource.

Resources represent physical goods. They are produced, consumed, stored,
transferred, bought, and sold as resource units. CREDIT represents financial
value and is not a substitute for a resource inventory.

## Account purposes

Account type describes purpose. Asset type describes contents. Owner capability
determines whether the combination is legal.

The canonical account purposes are:

| Account purpose | Allowed contents | Allowed principals | Meaning |
|---|---|---|---|
| `WALLET` | CREDIT | House | House liquid financial balance |
| `INVENTORY` | Resources | House | House physical goods used for production, consumption, construction, or trade |
| `MARKET_ESCROW` | CREDIT or resources | House | House assets reserved for an open market order |
| `TREASURY` | CREDIT | Corporation, EARTH | Public financial budget |
| `OPERATIONS` | CREDIT | Corporation, EARTH, Global Bank | Operating financial balance |
| `RESERVE` | CREDIT | Corporation, EARTH, Global Bank | Financial reserve |
| `SYSTEM_ACCOUNT` | Any asset where technically required | SYSTEM | Accounting, issuance, retirement, production, consumption, or clearing machinery; never gameplay ownership |

`MARKET_ESCROW` replaces the ambiguous legacy concept of a CREDIT-only
`ESCROW`. Market escrow may contain either the CREDIT reserved for a buy order
or the resource reserved for a sell order. It is a reservation purpose, not a
new economic principal.

## Capability policy

The authoritative capability matrix is:

| Owner type | `WALLET` | `INVENTORY` | `MARKET_ESCROW` | `TREASURY` | `OPERATIONS` | `RESERVE` | `SYSTEM_ACCOUNT` |
|---|---:|---:|---:|---:|---:|---:|---:|
| House | CREDIT | Resources | CREDIT or resources | No | No | No | No |
| Corporation | No | No | No | CREDIT | CREDIT | CREDIT | No |
| EARTH | No | No | No | CREDIT | CREDIT | CREDIT | No |
| Bank | No | No | No | No | CREDIT | CREDIT | No |
| SYSTEM | No | Technical only | Technical only | No | No | No | Any required asset |

Future schema work must enforce this matrix at the database boundary through
an account capability policy. Application provisioning alone is insufficient.
The following combinations are forbidden even if a future service attempts to
insert them:

- Corporation + resource + `INVENTORY`.
- EARTH + resource + `INVENTORY`.
- Bank + resource + `INVENTORY`.
- Corporation, EARTH, or Bank + `MARKET_ESCROW`.
- Territory, Human, or Building as an economic principal.
- Human as the persistent owner of House economic state.
- Building as an independent wallet, inventory, or owner registry principal.

## Public infrastructure

Public infrastructure is a Corporation-owned economic asset located in a
Territory:

- construction is paid from the Corporation's CREDIT treasury;
- the building's `owner_economic_id` resolves to the Corporation;
- `territory_id` records location independently from ownership;
- infrastructure may consume resources through the Corporation's authorized
  operating process, but the Corporation does not acquire a normal resource
  inventory;
- public capacity and service output are projected into Territory state;
- public infrastructure does not make Territory an owner or institution.

Private productive assets are primarily House-owned. A House pays from its
CREDIT wallet and supplies or receives resources through its inventory.

## Resource production and consumption

Resources are physical ledger facts, not an unexplained infinite warehouse.

- `RESOURCE_PRODUCTION`: a building or authorized process creates resource
  units for the House inventory, with the producing asset recorded.
- `RESOURCE_CONSUMPTION`: a building or authorized process removes resource
  units from the consuming House inventory, with the consuming operation
  recorded.
- `TRANSFER`: each asset's net movement is zero.
- `EXCHANGE`: each asset balances independently across counterparties.
- `ISSUANCE` and `RETIREMENT`: explicit exceptional operations for assets that
  are created or destroyed by an authorized system rule.

Transaction validation must group deltas by `asset_id`. CREDIT and ENERGY must
never be balanced by adding their numeric quantities together. Where a posting
contains both an account and an asset identifier, the account's canonical asset
must be validated or derived rather than trusted independently.

Technical SYSTEM accounts may support accounting operations during the
transition, but they are not player-visible ownership and must not become a
second resource authority. Future cleanup should distinguish monetary issuance
and retirement from resource production and consumption.

## Resource-market eligibility

Normal resource spot-market orders are House-only:

- a House may buy or sell resources;
- a Corporation may not speculate in resources;
- EARTH may not speculate in resources;
- the Global Bank may not trade resources;
- SYSTEM may clear and settle orders but is not a gameplay trader.

Market orders must resolve their economic owner through the persistent House,
not directly through the Human representative. Market reservations use
`MARKET_ESCROW` and a dedicated reservation record; they must not create a
disposable economic account for every order.

## Forbidden account combinations

The following rules are normative and must be preserved by future migrations,
services, fixtures, and tests:

1. `owner_type` is limited to `EARTH`, `CORPORATION`, `HOUSE`, `BANK`, and
   `SYSTEM`.
2. Only Houses may hold normal resource inventory.
3. Only Houses may place normal resource spot-market orders.
4. Institutions may hold CREDIT accounts for their defined public purposes,
   never normal resource inventories.
5. Territory, Human, and Building are never economic principals.
6. A Human acts for a House; Human succession does not transfer House economic
   ownership.
7. A Building has an owner and a location but no independent economic wallet.
8. Account-purpose policy must reject unsupported owner/asset combinations at
   the database boundary.

## Implementation boundary

This is an ownership freeze, not the implementation phase for all economic
changes. It does not yet require:

- an immediate account-policy table and trigger;
- a complete transaction-engine rewrite;
- market escrow migration;
- SYSTEM resource-account cleanup;
- resource-market service refactoring.

Those changes must implement this ADR when their corresponding mechanics are
next redesigned. No later mechanic may redefine ownership locally.
