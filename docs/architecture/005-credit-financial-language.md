# ADR 005: CREDIT as the Universal Financial Language

- Status: Accepted
- Date: 2026-09-14
- Scope: Financial vocabulary, pricing, commitments, obligations, payments, and institutional finance
- Depends on: ADR 002, ADR 003, ADR 004

## Decision

`CREDIT` is EARTH's sole unit of account and universal financial language.

Every financial amount—price, balance, budget, tax, wage, fee, debt,
collateral, reservation, payment, and settlement—must be expressed in
`CREDIT` units. No mechanic may introduce a secondary currency, local money,
barter balance, or institution-specific financial unit.

Physical resources remain a separate asset class. `MATERIAL`, `COMPONENTS`,
`ENERGY`, `COMPUTE`, and `FOOD` are not currencies and cannot be used as
implicit financial accounts.

## Core vocabulary

| Concept | Meaning | Financial effect |
| --- | --- | --- |
| **Unit of account** | The denomination used to state economic value. | Always `CREDIT`. |
| **Price** | A quoted amount of CREDIT for one unit or one defined action. | A valuation or market signal; it does not move funds. |
| **Payment** | A completed transfer of CREDIT that discharges an obligation. | Moves CREDIT between authorized accounts. |
| **Transfer** | A ledger movement of an existing asset between accounts. | Does not create or destroy CREDIT. |
| **Authorization** | Permission for an actor or system to initiate an action. | Creates no financial claim by itself. |
| **Commitment** | An authorized reservation or promise to spend CREDIT later. | Reduces available budget or buying capacity according to its rule. |
| **Obligation** | A recorded amount owed by an economic principal. | Creates a payable claim, not a completed payment. |
| **Settlement** | The deterministic process that evaluates commitments and obligations. | May create payment attempts, arrears, or explicit retirement/issuance events. |
| **Actor** | The Human or SYSTEM process that performs an action. | Is not automatically the payer or owner. |
| **Payer** | The economic principal whose CREDIT account is debited. | Must be authorized and solvent for the payment. |
| **Beneficiary** | The economic principal whose account receives CREDIT. | Must be an authorized recipient. |

These roles must not be collapsed into one generic `entityType` or inferred
from a UI label:

```text
authority ≠ actor ≠ payer ≠ economic owner ≠ beneficiary ≠ location ≠ state holder
```

## CREDIT and physical resources

`CREDIT` and physical resources have different meanings and ledger rules.

| Asset class | Examples | Can be a price? | Can be paid as money? | Can be produced/consumed? |
| --- | --- | ---: | ---: | ---: |
| Financial | `CREDIT` | Yes | Yes | Issued/retired only by monetary authority |
| Physical | `MATERIAL`, `COMPONENTS`, `ENERGY`, `COMPUTE`, `FOOD` | Yes, quoted in CREDIT | No, unless a future ADR explicitly defines a conversion | Yes, through resource production/consumption |

A price is expressed in CREDIT even when it refers to a physical resource.
A resource transfer is not a payment. A payment is not resource production.
The ledger must record both legs separately when a market exchange contains
one of each.

There is no barter. A mechanic that exchanges a resource for another resource
must route the exchange through an explicit CREDIT price and two auditable
asset transfers, or receive a new ADR before implementation.

## Internal and external transfers

An **internal transfer** moves CREDIT between accounts under the same
economic principal or within one authorized institution's accounts. Examples:

- House wallet to House market escrow;
- Corporation treasury to Corporation operations;
- EARTH treasury to an EARTH program account.

An internal transfer changes account purpose or reservation state but does not
change ownership or total CREDIT supply.

An **external transfer** moves CREDIT between distinct economic principals.
Examples:

- House payment to another House through the market;
- House tax payment to Corporation or EARTH;
- Corporation infrastructure payment to a House supplier;
- Bank loan disbursement to a House.

External transfers require an authorization source and a stated reason. They
must balance CREDIT independently from any physical-resource movement.

## Transaction taxonomy

Financial code must use explicit transaction semantics:

| Transaction kind | Purpose | Supply effect |
| --- | --- | ---: |
| `ASSET_TRANSFER` | Move existing CREDIT or a physical asset between accounts. | None |
| `CREDIT_ISSUANCE` | Create CREDIT under an authorized monetary rule. | Increases supply |
| `CREDIT_RETIREMENT` | Destroy CREDIT under an authorized monetary rule. | Decreases supply |
| `RESOURCE_PRODUCTION` | Create a physical resource through an authorized producer. | Does not affect CREDIT supply |
| `RESOURCE_CONSUMPTION` | Consume a physical resource through an authorized sink. | Does not affect CREDIT supply |

Market payment, tax payment, construction payment, operating expense, loan
disbursement, and debt repayment are CREDIT transfers or explicit issuance/
retirement events. They must not use a generic resource mutation path.

Every transaction must identify, as applicable:

- policy and decision authority;
- actor;
- payer and beneficiary;
- economic owner;
- location;
- authorization source;
- commitment or obligation being settled;
- settlement phase and game day;
- correlation/idempotency key.

The ledger validates CREDIT entries per asset and per account. Numeric values
from different asset classes are never netted together.

## Permitted institutional uses

| Principal | Permitted CREDIT uses |
| --- | --- |
| **House** | Wallet, construction, operation, taxes, market purchases, wages, fees, savings, and other authorized private activity. |
| **Corporation** | Treasury, operating budget, reserve, public infrastructure, local programs, taxes, and authorized payments. |
| **EARTH** | Treasury, global programs, constitutional transfers, monetary policy, and civilization-wide obligations. |
| **Global Bank** | CREDIT issuance, lending, deposits, reserves, interest, liquidity operations, and authorized settlement. |
| **SYSTEM** | Technical clearing, issuance, retirement, production, consumption, and escrow machinery only; never gameplay ownership. |
| **Territory, Human, Building** | No economic account and no independent CREDIT balance. |

Corporations and EARTH may fund or purchase physical goods, but they do not
become physical-resource owners merely because they paid for them. Ownership,
payer, and location remain separate fields.

## Forbidden financial designs

The following are prohibited without a superseding ADR:

- secondary currencies or local Corporation money;
- barter balances or resource-denominated wallets;
- treating a price quote as a payment;
- marking an obligation paid without a ledger transfer;
- automatic CREDIT revenue from a building without a payer or economic event;
- hidden CREDIT creation in construction, operation, research, or market code;
- using physical resources to balance a CREDIT transaction;
- treating authorization, commitment, obligation, and payment as synonyms;
- using a Human, Territory, or Building as a financial principal;
- using numeric account types or legacy balance fields in active code.

## Consequences

This ADR gives all future mechanics one financial grammar:

```text
price       = CREDIT quote
commitment  = authorized promise to spend CREDIT
obligation  = recorded CREDIT owed
payment     = completed CREDIT transfer
resource    = physical asset, never currency
```

The model makes taxes, budgets, markets, construction, banking, research,
and public infrastructure interoperable without inventing new money. It also
keeps physical production auditable: resource flows may react to CREDIT
prices, but no resource producer silently mints CREDIT.

Any future mechanic that requires a second unit of account, barter, or a new
financial asset must first amend this ADR and update the account-capability and
transaction-integrity policies.
