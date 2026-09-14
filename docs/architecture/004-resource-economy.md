# ADR 004: Five-Resource Production and Consumption Economy

- Status: Accepted
- Date: 2026-09-14
- Scope: Resource semantics and daily physical-economy rules
- Depends on: ADR 002, ADR 003

## Decision

EARTH uses five physical resources:

| Resource | Meaning | Typical sources | Typical uses |
| --- | --- | --- | --- |
| `MATERIAL` | Bulk physical matter used to make and maintain physical assets. | Extraction, recycling, private production. | Private construction, maintenance, manufacturing. |
| `COMPONENTS` | Manufactured intermediate parts and assemblies. | House production buildings and processing chains. | Buildings, machines, advanced production. |
| `ENERGY` | Usable energy available to operate physical systems. | Generation and conversion buildings. | Buildings, production, computation, maintenance. |
| `COMPUTE` | Usable computation capacity, represented as a tradable physical resource. | Compute infrastructure. | Research, control, production, services. |
| `FOOD` | Consumable biological sustenance for Humans. | Agricultural and food-production buildings. | Human daily maintenance and the food market. |

`CREDIT` is money and is not one of the five physical resources. It pays for construction, operation, taxes, infrastructure, and market settlement; it does not substitute for a missing physical input unless a mechanic explicitly defines a conversion.

## Ownership and authority

Houses are the only player economic principals that may hold physical-resource inventories. A House may hold `CREDIT` and all five physical resources.

Corporations, EARTH, and Banks may hold and transfer `CREDIT` according to their account policies, but they do not receive physical-resource inventories. Territory, Human, and Building are never economic principals and cannot own accounts.

Public infrastructure is Corporation-funded and located in Territory. Its service and capacity effects are public state; they are not a Corporation resource inventory. Private productive buildings are House-owned and operate against House inventories.

The following distinctions remain mandatory:

```text
authority ≠ actor ≠ payer ≠ economic owner ≠ location ≠ state holder
```

## Source and sink roles

Every physical-resource change is one of these explicit events:

1. `RESOURCE_PRODUCTION`: a production authority creates resource units in a House inventory and records the corresponding system issuance entry.
2. `RESOURCE_CONSUMPTION`: a consumption authority removes resource units from a House inventory and records the corresponding system retirement entry.
3. `ASSET_TRANSFER`: existing units move between compatible accounts, normally between House inventories, House wallets, market custody, or a designated system account.

Production and consumption are not ordinary transfers and must not be represented as a transfer to a hidden institutional wallet. Their transaction kind, source type, authority, asset, and signed entries must make the creation or destruction explicit.

The ledger must validate asset/account compatibility and balance entries independently for every asset. A transaction that balances `CREDIT` cannot compensate for an imbalance in `FOOD`, `ENERGY`, or another resource.

## Operational dependency graph

Physical operation follows this dependency direction:

```text
House opening inventories
          │
          ├── required physical inputs ──▶ private building operation
          │                                  │
          │                                  └── output resources → House inventory
          │
          └── FOOD allocation ────────────▶ Human daily maintenance

Corporation CREDIT ──▶ public infrastructure operation
                              │
                              └── Territory service/capacity projection
```

Public infrastructure may improve Territory services and capacity, but it does not create a Corporation-owned commodity inventory. Its operating cost is `CREDIT` unless a future ADR explicitly introduces another public-resource rule.

## Construction versus operation

Construction and operation are separate economic events.

### Construction

Construction creates or upgrades a Building. It consumes the construction inputs declared by the building catalog and charges the appropriate payer:

- private building: House `CREDIT` and House physical resources;
- public infrastructure: Corporation `CREDIT` and no persistent Corporation physical-resource inventory.

Construction inputs are paid once for the construction event. They do not become an implicit daily operating requirement unless the catalog separately declares them as operating inputs.

### Operation

Operation is the daily attempt to produce outputs or deliver building effects. It uses the opening inventory snapshot for that settlement day, consumes declared inputs, and produces declared outputs only when the operation is actually utilized.

Construction cost, operating expense, service capacity, and resource production are separate catalog concepts. A public definition cannot smuggle physical-resource production or a persistent physical-resource input into its service/capacity effects.

## Daily settlement rules

### Opening-inventory rule

Each House building settlement begins with the House’s resource inventories as they exist at the opening of the game day. That snapshot is the authoritative input boundary for the day.

Inputs consumed during the day reduce the available opening inventory. Outputs created during the day become available for later settlement according to the scheduler’s deterministic ordering; they are not retroactively available to an earlier operation in the same phase.

An operation cannot spend units that were not available at its opening boundary. Failed or partially funded operations must record their result explicitly and must not create output without the corresponding input and authority checks.

### Proportional-utilization rule

When a House lacks one or more required physical inputs, operation runs at the maximum feasible proportion rather than producing at full capacity.

For an operation with required input `r_i` and available opening inventory `a_i`, its utilization is:

```text
u = min(1, a_i / r_i) for every required input r_i > 0
```

The settlement consumes `u × r_i` of each required input and produces `u × output_i` of each output. Values are rounded using one deterministic, documented unit-rounding rule; rounding must not create units from zero input or cause a negative inventory.

If the catalog declares no physical input, utilization is `1` unless a separate authority, capacity, or CREDIT rule prevents operation. A building with zero feasible utilization produces no physical output.

The proportional rule applies to private productive buildings. Public infrastructure uses its Corporation `CREDIT` operating budget and produces service/capacity effects, not commodity-resource output.

## Market relationship

The market is a transfer and custody mechanism, not a production mechanism.

- Normal physical-resource market orders are House-only.
- A market order moves existing House-held units into `MARKET_ESCROW` custody and releases them to the buyer or back to the House when the order is filled, cancelled, or expires.
- Market escrow does not create or destroy resources.
- Corporations, EARTH, Banks, Territories, Humans, and Buildings cannot submit normal physical-resource orders or hold normal physical-resource market inventory.
- `CREDIT` settlement and physical-resource custody are separate asset flows and must be ledger-auditable independently.

Market eligibility is determined by the resource’s catalog and account policy. A resource may be produced by a House building and still be ineligible for a particular market action; production, ownership, and market eligibility are separate decisions.

## FOOD and Human maintenance

`FOOD` is the physical resource required for Human daily maintenance. FOOD maintenance is a House economic obligation because the Human is represented by, and economically attached to, a House; a Human does not own the inventory or become an economic principal.

Daily maintenance consumes FOOD from the House inventory according to the authoritative maintenance rule for the Human and game day. The maintenance result must distinguish:

- FOOD required;
- FOOD available at the opening boundary;
- FOOD consumed;
- any shortfall or unpaid consequence;
- the resulting Human condition/state.

FOOD may be produced by House-controlled private production and exchanged through the House-only resource market. Public infrastructure can affect service or capacity relevant to maintenance, but it does not own or distribute a Corporation FOOD inventory under this ADR.

## Forbidden interpretations

The following interpretations are invalid:

- Corporation resource inventories as a shortcut for public infrastructure operation.
- EARTH, Bank, Territory, Human, or Building resource accounts.
- Public buildings producing commodity resources through service/capacity definitions.
- Treating production or consumption as an ordinary asset transfer.
- Using closing inventory as the input boundary for the same day’s settlement.
- Full-capacity output when a required input is only partially available.
- Using `CREDIT` balances to conceal missing physical inputs.
- Allowing normal resource market participation by an institution or actor other than a House.

## Consequences

This ADR gives later building and Generation work a fixed contract:

- Houses operate the physical economy and hold its resources.
- Corporations fund public infrastructure with `CREDIT` and receive public service/capacity effects.
- EARTH governs global rules and programs.
- The Global Bank finances `CREDIT`.
- Territories contain buildings and projections but do not own economic accounts.
- Buildings execute catalog-defined production, consumption, and service effects.
- The ledger can explain every resource unit produced, consumed, or transferred per game day.

Any future mechanic that changes these rules requires a new ADR or an explicit amendment to this one.
