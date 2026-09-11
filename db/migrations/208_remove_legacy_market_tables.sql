-- Market V2 Plan 17: remove transitional market history and derivative tables.
DROP TABLE IF EXISTS commodity_futures_contracts CASCADE;
DROP TABLE IF EXISTS market_ohlc_snapshots CASCADE;
DROP TABLE IF EXISTS market_trades CASCADE;
