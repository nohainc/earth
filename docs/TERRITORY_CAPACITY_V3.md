# Territory capacity V3

- Status: Canonical
- Projection: `territory_capacity_state`
- Rebuild function: `earth_refresh_territory_capacity(territory_id, game_day)`

## Authority

Territory is the sole geographic scarcity boundary. Active buildings in a
Territory and their catalog effects produce the authoritative projection for:

- House and population capacity;
- private building slots;
- public building slots;
- private and public slots used;
- housing, health, energy, and connectivity capacity; and
- typed service capacity totals.

The projection is rebuildable from `territories`, `buildings`,
`building_catalog`, `building_catalog_effects`, `owner_registry`, and active
House affiliations. It does not require a City row, City governance, or City
treasury.

## Scarcity rules

- District modules are Territory infrastructure and contribute capacity through
  catalog effects.
- House-owned buildings consume private slots.
- Corporation-owned public infrastructure consumes public slots.
- A Human may initiate construction, but the persisted economic owner is the
  House for private blueprints and the Corporation for Territory-infrastructure
  blueprints.
- Building location is `buildings.territory_id`; ownership remains
  `buildings.owner_economic_id`.
- Private construction validates the Territory projection before inserting a
  building and refreshes the projection after the insert.
