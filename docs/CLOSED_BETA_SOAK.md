# Closed-Beta Soak & Economic Calibration

This harness runs an accelerated, deterministic simulation for balancing before beta. It is a calibration tool, not a replacement for the PostgreSQL scheduler or production settlement.

## Run

```bash
npm run soak:closed-beta
```

Useful controls:

```bash
EARTH_SOAK_SEED=20260911 \
EARTH_SOAK_DAYS=365 \
EARTH_SOAK_HOUSES=10000 \
EARTH_SOAK_ACCELERATION=24 \
EARTH_SOAK_OUTPUT=artifacts/closed-beta-soak.json \
npm run soak:closed-beta
```

The same seed and configuration produce the same report. `EARTH_SOAK_ACCELERATION` changes simulation pressure only; it never changes the production game clock.

## Reported signals

Each simulated day records:

- CREDIT supply, issuance/retirement, taxes, sales, expenses, and purchases;
- resource totals and market prices;
- median/p95 wealth, Gini coefficient, and top-10% wealth share;
- building profitability;
- city treasury stress and corporate treasury concentration;
- research completion/progress;
- average Food/Energy need satisfaction.

The report warns about rising wealth concentration, excessive corporate concentration, low need satisfaction, and stressed city treasuries. These are calibration signals for reviewing positive-feedback loops such as corporate wealth → technology → output → wealth.

## Review cadence

Run the soak at several scales and seeds, compare reports across rule versions, and archive the input configuration with each result. Treat warnings as balance-review prompts, not automatic balance changes. Before closed beta, repeat representative scenarios against the real PostgreSQL settlement path and reconcile the resulting ledgers.
