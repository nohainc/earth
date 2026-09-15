# Corporation public infrastructure V3

- Status: Canonical

Corporations are responsible for local public capacity and service quality.
Public infrastructure is built inside a Corporation's Territory and is owned
and funded by that Corporation.

## Slot rules

- `building_catalog.ownership_scope = 'PRIVATE'`: the persisted owner must be a
  House, and the building consumes private Territory slots.
- `building_catalog.ownership_scope = 'PUBLIC'`: the persisted owner must be
  the Territory's Corporation, and the building consumes public Territory
  slots.
- Private capacity cannot be used by public infrastructure, and public
  capacity cannot be used by House buildings.
- A Human may submit the action as a Corporation member, but the Human is not
  the public infrastructure owner.

The database ownership trigger enforces these rules. Corporation construction
uses the Corporation treasury, and the Territory capacity projection publishes
the resulting service and slot totals.
