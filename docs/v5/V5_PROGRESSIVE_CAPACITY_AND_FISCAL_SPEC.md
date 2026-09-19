# EARTH Gameplay V5 — Progressive Capacity and Fiscal Specification

Status: **CURRENT-CANONICAL V5 GAMEPLAY**  
Version: 5.0-design

## 1. Purpose

V5 standardizes all progressive pricing/tax behavior around one reusable
**marginal bracket engine**. This document defines its semantics and its first two
required gameplay uses:

1. EARTH charging Corporations for occupied physical capacity;
2. Corporations charging Houses for residential + productive capacity.

The same engine may later be used for progressive taxes. No other progressive
algorithm should be introduced without an ADR.

Balance numbers in examples are illustrative only.

---

# 2. Core rule: marginal brackets

A progressive policy consists of:

```text
base rate
+ ordered quantity brackets
+ a marginal multiplier or rate for each bracket
```

Only the portion of quantity inside a bracket uses that bracket's marginal rate.
Crossing a boundary **never reprices earlier usage**.

Example:

| Range | Marginal multiplier |
| --- | ---: |
| 0–1 | 1.00x |
| 1–2 | 1.20x |
| 2–4 | 1.50x |
| 4–8 | 2.00x |

For quantity `5.0` and base rate `B`:

```text
first 1.0   × B × 1.00
next 1.0    × B × 1.20
next 2.0    × B × 1.50
next 1.0    × B × 2.00
```

This avoids discontinuous cost cliffs.

---

# 3. Why V5 rejects highest-bracket repricing

Rejected model:

```text
if quantity enters bracket N,
apply bracket N price to ALL quantity
```

That would make one additional capacity unit potentially increase the total bill
by a huge amount and encourage threshold gaming.

V5 requires:

```text
marginal cost of added quantity >= 0
previously priced quantity remains unchanged
```

---

# 4. One universal engine

The canonical calculation abstraction should support at least:

```text
PolicySchedule
- code
- base unit semantics
- brackets[]
- effective_from_game_day
- effective_to_game_day
- version
- authority
- status
```

Each bracket should contain exact numeric boundaries and one of the supported
marginal charge forms. V5 launch should prefer one simple form for capacity:

```text
marginal_multiplier
```

Progressive taxes may use direct percentage/rate values while retaining the same
marginal allocation algorithm.

The engine must be deterministic and independent of HTTP/Flutter/time/database
I/O. Rule selection happens before invocation.

---

# 5. Validation invariants

A schedule is invalid unless all of the following hold:

1. brackets are ordered and non-overlapping;
2. the first bracket begins at zero;
3. no gap exists between adjacent brackets;
4. the final bracket is open-ended or explicitly reaches the configured maximum;
5. all multipliers/rates are non-negative;
6. progressive capacity multipliers are monotonic non-decreasing;
7. V5 default progressive policies should be strictly increasing after the first
   bracket unless a constitutional rule explicitly allows equal ranges;
8. effective dates do not retroactively change settled game days;
9. version identifiers are immutable after activation;
10. authoritative calculations never use JavaScript/Dart floating-point money.

Server/database validation must reject a proposal/rule that would create a lower
marginal capacity price in a higher bracket.

---

# 6. Precision and units

V5 must explicitly distinguish:

- physical capacity units;
- standard Territory capacity units;
- normalized Territory-equivalent quantity;
- CREDIT smallest units;
- resource fixed-point units.

Recommended authority rule:

- store physical capacity as integers;
- store CREDIT in canonical integer smallest units;
- represent normalized Territory-equivalent calculations using exact PostgreSQL
  numeric/rational-safe arithmetic or avoid division in settlement by converting
  bracket boundaries into physical-capacity units.

Preferred implementation simplification:

> Define Corporation progressive brackets directly in **physical occupied
> capacity units derived from standard Territory capacity**, so settlement does
> not require authoritative floating-point Territory-equivalent values.

For UI, the server may additionally return friendly equivalents such as `2.52
Territories`.

---

# 7. EARTH → Corporation capacity charge

## 7.1 Occupied Corporation capacity

Canonical billable usage:

```text
corporation_occupied_capacity =
  count(active affiliated Houses requiring residence)
  + sum(billable private building footprints)
  + sum(billable public/institutional footprints)
```

Exact inclusion rules must be versioned. Destroyed/released capacity is not
billable after its authoritative release becomes effective.

## 7.2 Standard Territory unit

EARTH defines:

```text
standard_territory_capacity_units
```

This determines how many standardized Territory container records are needed:

```text
required_territory_count =
ceil(occupied_capacity / standard_territory_capacity_units)
```

This count is **not the bill**. It is the physical-container/read-model count.

## 7.3 Bill

Conceptually:

```text
EARTH_CAPACITY_CHARGE =
MarginalProgressiveCharge(
  occupied_capacity,
  earth_base_capacity_rate,
  earth_corporation_capacity_schedule
)
```

EARTH governance owns both the base EARTH rate and global schedule, subject to
constitutional bounds/effective-date rules.

## 7.4 Why charge occupancy rather than whole containers

If a Corporation moves from capacity `500` to `501`, automatic activation of a
second standardized Territory container must not cause a whole additional
Territory's fixed rent. Billing actual usage keeps the cost smooth while the
container count remains useful for physical capacity/read-model representation.

---

# 8. Corporation → House capacity charge

## 8.1 House usage

Canonical billable quantity:

```text
house_capacity_usage =
1 residential unit
+ sum(billable private building footprints)
```

Later policy may include other private assets only through an explicit versioned
rule.

## 8.2 House charge

```text
HOUSE_CAPACITY_CHARGE =
MarginalProgressiveCharge(
  house_capacity_usage,
  corporation_house_base_rate,
  earth_house_capacity_schedule
)
```

EARTH controls the bracket shape; Corporation governance controls the base rate.

## 8.3 Residential unit

V5 launch treats the residential unit as the first/cheapest unit of the same
progressive schedule. This avoids a second pricing algorithm.

If balancing later requires a special protected residential discount, that must
be an explicit versioned rule and should still reuse the same charge engine
rather than client special cases.

---

# 9. Example calculations

Illustrative only.

Suppose House schedule:

| Usage units | Multiplier |
| --- | ---: |
| first 1 | 1.00x |
| next 1 | 1.20x |
| next 2 | 1.50x |
| next 4 | 2.00x |
| next 8 | 2.75x |
| above 16 | 3.50x |

Corporation base House rate = `2 C / capacity unit / day`.

House uses 8 capacity units:

```text
1 × 2 × 1.00 = 2.00
1 × 2 × 1.20 = 2.40
2 × 2 × 1.50 = 6.00
4 × 2 × 2.00 = 16.00
TOTAL = 26.40 C/day
```

The server should return both total and marginal effects. The Flutter UI should
not reproduce the arithmetic.

---

# 10. Incremental quote contract

Every command changing occupied House capacity should receive a canonical quote
or preview.

Minimum response semantics:

```text
currentUsage
usageDelta
afterUsage
currentChargeUnits
afterChargeUnits
incrementalChargeUnits
currentBracket
resultingBracket
rulesVersion
baseRateVersion
canExecute
blockers[]
```

For building construction, also include the full building economic preview.

For Corporation-affecting commands (membership join/leave, public construction,
liquidation), expose Corporation incremental EARTH charge where useful for
authorized governance/admin views.

---

# 11. Policy governance

## 11.1 EARTH progressive policy proposal

Special proposal type should support changing authorized fields such as:

- EARTH base Territory/capacity rate;
- House progressive schedule;
- Corporation progressive schedule;
- standard Territory capacity size where allowed.

The server must provide a deterministic impact preview.

Useful preview segments:

```text
Current vs proposed EARTH daily revenue
Median House effect
Small / medium / large House examples
Small / medium / large Corporation examples
Largest affected Corporation(s) aggregate
EARTH Treasury projection
Effective game day
```

The UI must distinguish illustrative representative examples from exact affected
individual values where privacy/performance requires aggregation.

## 11.2 Corporation base-rate proposal

Corporation proposal may change only the base House capacity rate (plus whatever
other independent fiscal rules are authorized).

Preview should include:

```text
current/proposed base rate
current/proposed House capacity-rent revenue
EARTH capacity expense
current/proposed land margin
representative House-size impacts
Treasury impact
new effective game day
```

---

# 12. Effective dates and rule stability

Progressive policy is foundational and must not oscillate every few game days.

Recommended governance constraint for V5 launch:

- changes become effective only at a clear future period boundary, preferably a
  game-year boundary or other stable configured fiscal period;
- active settled days are never recalculated;
- proposals show effective date explicitly;
- policy versions are immutable once effective;
- settlement records the applied rule version.

Exact constitutional cadence belongs in versioned rules/Constitution updates.

---

# 13. Change bounds

Players should be allowed to make economically poor policy choices, but rule
mutation must be protected from accidental/corrupt values.

Server-side policy constraints should define bounded ranges for:

- base rates;
- multipliers;
- bracket boundaries;
- maximum single amendment change where constitutionally desired.

These are safety/contract constraints, not automatic fiscal optimization.

The game should permit a low EARTH rate that underfunds discretionary programs
if governance lawfully chooses it.

---

# 14. Progressive taxes

When V5/current tax design requires progression, use the same marginal engine.

Example:

| Daily taxable amount | Marginal tax rate |
| --- | ---: |
| 0–1,000 C | 0% |
| 1,000–5,000 C | 5% |
| 5,000–20,000 C | 10% |
| >20,000 C | 15% |

Only income inside each bracket receives that marginal rate.

Flat tax is represented by one open-ended bracket.

Do not maintain a separate progressive-tax algorithm and progressive-capacity
algorithm.

---

# 15. Settlement accounting

Each daily charge must be an explicit authoritative economic transaction.

## House capacity charge

```text
House CREDIT account
  → Corporation designated revenue/Treasury account
```

Transaction metadata should identify:

- House;
- Corporation;
- game day;
- occupied capacity;
- base-rate version;
- progressive schedule version;
- assessed amount;
- amount paid;
- arrears created/settled;
- correlation ID.

## Corporation EARTH capacity charge

```text
Corporation Treasury/designated account
  → EARTH Treasury/designated land revenue account
```

Same audit semantics apply.

Assessment and payment may be represented separately if the obligations system
requires it, but no hidden field decrement is allowed.

---

# 16. Partial payment and arrears

When available CREDIT is insufficient:

- do not make normal account balances negative;
- calculate lawful assessment;
- transfer whatever the resolution/priority rules allow;
- record remaining unpaid amount as an obligation/arrears;
- transition delinquency state according to the active rules;
- preserve full history.

The billing engine calculates assessment. The insolvency/obligation engine owns
collection priority and resolution state.

---

# 17. Capacity release

Capacity billability stops only when the authoritative capacity right/asset state
changes.

Examples:

- building destroyed/liquidated and footprint released;
- building permanently surrendered where rules define it;
- House affiliation lawfully ends and residential capacity is released after
  applicable transition rules;
- Corporation resolution changes control/state.

Simply logging out or being inactive does not reduce the bill.

---

# 18. Required tests

At minimum, the progressive engine and capacity billing require tests for:

- exact bracket boundaries;
- quantity one unit below/at/above every boundary;
- fractional-normalized display vs integer authoritative units;
- zero usage;
- very large usage;
- monotonic total charge;
- monotonic marginal charge;
- no repricing of lower brackets;
- flat one-bracket schedule;
- invalid overlapping/gapped brackets;
- invalid regressive multipliers;
- version/effective-date selection;
- replay/idempotency;
- insufficient funds/arrears;
- House join/leave capacity change;
- construction/demolition capacity change;
- automatic Territory-container count around exact capacity boundaries;
- Corporation public/private capacity inclusion rules;
- proposal preview matching eventual settlement under the same rule version;
- no JavaScript/Dart floating-point authoritative money divergence.

Property-based tests are strongly recommended for monotonicity and bracket
allocation.

---

# 19. Required UI behavior

Player-facing screens should show understandable results, not formula syntax.

Examples:

```text
Capacity used                8
Current rent             26.40 C/day
Next building footprint      +3
New capacity                11
New rent                  36.90 C/day
Increase                  10.50 C/day
```

Optional details can show bracket breakdown:

```text
First unit              1.00×
Second unit             1.20×
Units 3–4               1.50×
Units 5–8               2.00×
...
```

Governance pages should expose full policy details/impact previews.

---

# 20. Anti-patterns prohibited by V5

Do not:

- use an exponential per-slot formula in one feature and brackets in another;
- reprice all usage using the highest reached bracket;
- calculate authoritative rent/tax in Flutter;
- hard-code production bracket schedules in widgets;
- use different progression rules per Corporation;
- let a Corporation set a regressive marginal schedule;
- retroactively apply a newly passed schedule;
- silently cap House/Corporation size instead of charging lawful progressive
  marginal cost;
- make a new standardized Territory container itself produce automatic revenue.
