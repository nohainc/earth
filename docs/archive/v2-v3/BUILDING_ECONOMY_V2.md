# EARTH Building Economy V2

Status: CANONICAL
Authority: `building_catalog`, versioned building rules, Building V2 planner,
and Economy V2 postings

## Core rule

Buildings do not deteriorate through normal operation. Routine maintenance is
included in normal operating expenses. If operating requirements cannot be
satisfied, the building does not operate for that game day; it does not
accumulate damage requiring repairs.

A building converts allocated inputs and operating expenses into physical
output or service capacity. It never creates CREDIT merely because it is
active. Customer-funded revenue is a transfer from an actual payer; public
service revenue has an explicit public payer.

## Daily settlement

Building settlement is calculated by economic-owner shard and does not mutate
balances during planning:

1. Select eligible buildings and resolve the catalog/rule version for the day.
2. Snapshot owner inputs and allocate shared resources deterministically.
3. Calculate utilization, physical consumption, and physical production.
4. Calculate service capacity and match customer or public demand.
5. Calculate explicit operating expenses, including routine maintenance.
6. Compile and validate Economy V2 effects and conservation totals.
7. Atomically post the settlement batch.
8. Update building operational state and write the audit journal set-wise.

Shortages are resolved before netting. A failed requirement makes the building
inactive for that settlement period and leaves its persistent asset intact.

## Operational states

Buildings are `ACTIVE` when they can operate, and `INACTIVE` when requirements
are unavailable. Inactive buildings remain eligible for the next settlement.
There is no condition, wear, damage, repair queue, repair resource, or repair
transaction in Building V2.

## Economic contract

| Concern | Authority |
|---|---|
| Inputs | Versioned `building_catalog` requirements |
| Operating cost | Versioned operating expense, including routine maintenance |
| Physical output | Economy V2 resource credit to the owner or explicit recipient |
| Services | Capacity matched to aggregate customer/public demand |
| Revenue | Economy V2 transfer from the actual customer or public payer |
| Ownership | House economic owner for private buildings; City/Corporation for institutional assets |
| Technology | Corporation access and modifier cache |
| Tiers | Predefined T1–T5 catalog rows |
| Timing | Once per completed game day, after access resolution |

## Audit boundary

`building_settlement_journals` explain the inputs, allocation, utilization,
output, service delivery, expense, resulting state, economic batch, and
correlation ID. They are read/audit projections, not balance authorities.

Generic daily profiles are non-building economics. No building-origin effect
may be posted by both systems.
