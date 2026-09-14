# Governance V3

- Status: Canonical

EARTH and Corporation are the only political arenas. Territory is geography,
not a third polity. It may be the target of a proposal action, but it has no
independent electorate, treasury, tax scope, or governance roles.

The shared proposal infrastructure stores the political arena in
`proposals.institution_id` and an optional geographic target in
`target_type = 'TERRITORY'` plus `target_id`. Corporation proposals may target
only Territories owned by that Corporation; EARTH proposals may target any
active Territory.

Electorate and eligibility are therefore resolved only from EARTH authority or
Corporation membership. City electorates and City-specific roles are not part
of the V3 contract.
