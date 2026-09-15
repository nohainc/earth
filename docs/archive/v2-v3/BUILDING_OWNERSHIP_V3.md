# Building ownership and location V3

- Status: Canonical

## Model

`buildings.territory_id` is the only geographic location of a building.
`buildings.owner_economic_id` is the independent economic owner and resolves
through `owner_registry`.

Private blueprints are owned by a House and consume the Territory's private
slots. Territory-infrastructure blueprints are owned by the Corporation and
consume public slots. The Human who submits the transaction is the actor, not
the building owner.

No building operation in the canonical Territory construction path accepts or
persists a City identifier.
