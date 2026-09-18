# EARTH V5 — Authoritative Clock & Settlement Architecture

## 1. Core Principles & Decoupling

EARTH separates **World Time** from **Daily Settlement**:

```text
WORLD TIME (Continuous, Wall-Clock Derived)
    │
    │  CURRENT_TIMESTAMP - world_state.genesis_at
    ▼
Authoritative Game Clock
    ├── currentGameDay = floor(totalGameMinutes / 1440) + 1
    ├── currentGameMinute = totalGameMinutes % 1440
    └── absoluteGameMinute = totalGameMinutes

SETTLEMENT (Contiguous Watermark Cursor)
    │
    │  daily_settlement_control.settled_through_game_day
    ▼
Settlement Catch-Up Engine
    ├── lastClosedGameDay = currentGameDay - 1
    ├── backlogDays = max(0, lastClosedGameDay - settledThroughGameDay)
    └── status: CURRENT | CATCHING_UP | PAUSED
```

### Invariants:
1. **Time Invariant**: `1 real second = 1 game minute`. `1,440 game minutes = 1 game day = 24 real minutes`.
2. **Genesis Epoch**: `world_state.genesis_at` is set once at world creation and is guarded by trigger `trg_world_genesis_immutability`. World time cannot stop, pause, skip, or restart.
3. **Settlement Invariant**: The current open game day is never closed or settled (`lastClosedGameDay = currentGameDay - 1`).
4. **Zero Skipped Days**: Settlement progresses strictly monotonically and contiguously (`settled_through_game_day = settled_through_game_day + 1`).
5. **Economic Barrier**: Actions that require settled balances and inventory (e.g., market orders, construction, technology research) check `assertEconomyCaughtUp` and fail fast with `409 Conflict` (`WORLD_SETTLEMENT_CATCHING_UP`) if settlement is behind (`settledThroughGameDay < lastClosedGameDay`).

## 2. PostgreSQL Implementation

- **`earth_get_current_game_time()`**: STABLE function returning `(game_day, game_minute, total_game_minutes, genesis_at, server_now, elapsed_real_seconds, real_seconds_per_game_minute)`.
- **`earth_game_day_from_total_minutes(total_minutes)`**: IMMUTABLE function returning `floor(total_minutes / 1440) + 1`.
- **`earth_absolute_game_minute(game_day, game_minute)`**: IMMUTABLE function returning `(game_day - 1) * 1440 + game_minute`.
- **`earth_advance_settlement_cursor(game_day)`**: Atomic cursor increment on `daily_settlement_control`. Requires row lock and validates `game_day = settled_through_game_day + 1` with `daily_settlement_runs.status = 'completed'`.

## 3. Backend & Client Coordination

- **Backend**: Calls `readAuthoritativeGameTime(repository)` from `cloudflare/src/world-clock-postgres.ts`. All scheduled ticks process eligible closed days up to `lastClosedGameDay` without manipulating clock state.
- **Client**: Anchors HUD time to `totalGameMinutes` received from `/api/world` snapshot and advances smoothly via local monotonic timer. Never executes or triggers settlement.
