# V5 Constitution & Governance Kernel

This document records the implemented kernel slice. It does not declare the
full V5 cutover complete.

## Current implementation

- `constitutional_rule_definitions_v5` is the typed registry for amendable
  rules, including authority and amendment class.
- `constitutional_rule_versions_v5` stores immutable, effective-dated values
  with proposal provenance.
- `constitutional_change_sets_v5` stores atomic multi-rule amendment payloads.
- `resolved_constitution_snapshots_v5` materializes one Earth snapshot and one
  snapshot per active Corporation at the start of each settlement day.
- V5 capacity settlement and quotes prefer resolved Constitution values and use
  the existing V5 policy tables only as a compatibility fallback.
- V5 governance freezes electorate and voting-rule snapshots, counts abstention
  toward quorum, and marks base-version conflicts as `STALE`.
- Direct player-facing Charter, voting-setting, admission-policy, and tax-
  charter mutations are retired; constitutional changes use proposals.
- `POST /api/governance/v5/constitution/preview` provides a JSON-safe,
  side-effect-free impact view for typed amendments. It resolves the current
  Constitution first and restores the Earth value when a Corporation clears an
  Earth-default override.
- The canonical read model exposes active rule definitions and future
  `scheduledChanges`, so UI and operator tooling can render the same
  effective-dated values used by settlement.

## Authority semantics

`EARTH_LOCKED` values cannot be changed by a Corporation. An
`EARTH_DEFAULT_CORPORATION_OVERRIDE` value falls back to EARTH when no local
version exists. `CORPORATION_LOCAL` values are scoped to one Corporation.
Independent Houses therefore resolve directly against the Earth snapshot and do
not require a synthetic Corporation.

## Remaining cutover work

The legacy V4 proposal store, legacy charter data, and tax rule tables remain
readable migration bridges. They must not become new gameplay authorities. The
readiness gate now verifies Earth and Corporation Constitution snapshots for
the assessed day and the presence of the typed definition registry. Remaining
cutover work is to dual-record and shadow-compare all migrated tax rules,
complete the unified action-handler migration, finish the Constitution UI
history/progressive renderers, and retire the legacy stores after production
verification gates pass.
