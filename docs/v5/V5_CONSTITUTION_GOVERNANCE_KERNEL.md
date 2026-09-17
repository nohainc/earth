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

## Authority semantics

`EARTH_LOCKED` values cannot be changed by a Corporation. An
`EARTH_DEFAULT_CORPORATION_OVERRIDE` value falls back to EARTH when no local
version exists. `CORPORATION_LOCAL` values are scoped to one Corporation.
Independent Houses therefore resolve directly against the Earth snapshot and do
not require a synthetic Corporation.

## Remaining cutover work

The legacy V4 proposal store, legacy charter data, and tax rule tables remain
readable migration bridges. They must not become new gameplay authorities. The
remaining cutover work is to dual-record and shadow-compare all migrated tax
rules, complete the unified action-handler migration, update the Constitution
UI/history read models, and retire the legacy stores after the production
verification gates pass.
