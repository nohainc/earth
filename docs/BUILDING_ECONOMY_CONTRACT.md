# Building Economy Contract

Status: CANONICAL. This is the consistency contract for Building V2. A
building converts allocated resources and operating CREDIT into physical
output, service capacity, or both. It never creates CREDIT merely because it
is active.

Buildings do not deteriorate through normal operation. Routine maintenance is
included in ordinary operating expenses. Unsatisfied operating requirements
make a building inactive for that day; they do not create damage or a repair
obligation.

## Common settlement contract

| Concern | Authoritative rule |
|---|---|
| Inputs | `upkeep_energy`, `upkeep_food`, `upkeep_materials`, `upkeep_components`, `upkeep_compute` |
| Operating cost | `daily_operating_credits`; this includes ordinary maintenance expense |
| Physical outputs | One of MATERIAL, COMPONENTS, ENERGY, COMPUTE, or FOOD, posted to the owner inventory |
| Services | Catalog service capacity is consumed by resident/city demand; private service payments are customer-funded |
| Owner | Private buildings use the House economic owner; civic buildings use the City economic owner |
| Technology | Corporation access is resolved through the technology modifier cache and applied to inputs/output/capacity |
| Tiers | T1–T5 are predefined catalog rows; research unlocks a row and does not generate new economics |
| Timing | Eligible active buildings settle once per completed game day, after license/access resolution and before downstream city dynamics |
| Shortage | If any required input or operating CREDIT is unavailable, that building is inactive and produces no physical output or service capacity for that day |
| Accounting | Resource debits, physical credits, and explicit operating expenses are posted through the Economy V2 settlement batch |

## Catalog loop map

| Building type | Economic output / capacity | Consumer or beneficiary |
|---|---|---|
| `restaurant` | Resident dining service capacity | Human customers; operator receives their payments |
| `retail-store` | Resident retail service capacity | Human customers; operator receives their payments |
| `commercial-mall` | High-volume resident/commercial service capacity | Human and institutional demand |
| `fabrication-plant` | COMPONENTS | Manufacturing and construction inventories |
| `chemical-foundry` | MATERIAL | Manufacturing and construction inventories |
| `solar-array-complex` | ENERGY | Owner/city energy demand and inventories |
| `geothermal-grid` | ENERGY and civic utility capacity | City residents and infrastructure |
| `vertical-farm` | FOOD | Human and city food demand |
| `server-farm` | COMPUTE | Research, construction, and compute demand |
| `medical-clinic` | HEALTH service capacity | Human healthcare demand |
| `transit-hyperloop` | CONNECTIVITY/transport capacity | City residents and logistics demand |
| `orbital-spaceport` | Strategic transport/logistics capacity | City and inter-city logistics |
| `transit-terminus` | CONNECTIVITY/transport capacity | City residents and logistics demand |
| `urban-district-module` | HOUSING/civic capacity | City residents |
| `private-estate-plot` | HOUSING capacity | The owning House |

Descriptions and balance values remain in the database `building_catalog` for
settlement. The TypeScript catalog is limited to construction/API typing and
development-time validation until the catalog cutover is complete.

## Deliberate non-goals

Building V2 does not introduce health, internet, education, transport, or other
service tokens as new currencies. Services are capacity/value projections and
their payments are ordinary Economy V2 CREDIT transfers from an explicit payer.
