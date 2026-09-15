# EARTH Death & House Continuity V2

> The player is the House; the Human is the current mortal representative. Death changes who represents the House, not who owns the player's persistent economic world.

## Identity boundary

- `House` is the persistent authenticated and economic principal.
- `Human` is a mortal generation with personal standing, life state, offices, ballots, and historical biography.
- Every active House has exactly one active current Human.
- Succession creates a new Human in the same House; it never nominates another active player's Human.

## Continuity rules

House-owned balances, resources, buildings, market orders, escrow, bank contracts, tax obligations, corporation affiliations, technology access, perks, and heirlooms survive succession unchanged. Personal offices and equipment assignments end with the deceased Human. Ballots remain historical and House-unique.

Mortality and succession are deterministic and idempotent using `death:{humanId}:{gameDay}` and `succession:{houseId}:{generation}`. The scheduler can replay a day without creating duplicate heirs, lineage records, or notifications.

## Cutover status

The House-based path is authoritative. Cross-Human succession endpoints are retired, legacy succession columns are removed by migration 314, and annual lifecycle execution uses `processHouseMortality`. The remaining legacy handler definitions are compatibility dead code and are scheduled for deletion before production cutover.
