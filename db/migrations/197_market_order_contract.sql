-- Market V2 Plan 3: deterministic, instrument-aware order contract.
CREATE SEQUENCE IF NOT EXISTS market_order_sequence;

ALTER TABLE market_orders
  ADD COLUMN IF NOT EXISTS owner_economic_id BIGINT,
  ADD COLUMN IF NOT EXISTS instrument_id TEXT,
  ADD COLUMN IF NOT EXISTS filled_units BIGINT,
  ADD COLUMN IF NOT EXISTS eligible_batch_id BIGINT,
  ADD COLUMN IF NOT EXISTS sequence_no BIGINT,
  ADD COLUMN IF NOT EXISTS escrow_account_id BIGINT,
  ADD COLUMN IF NOT EXISTS reserved_base_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS buyer_fee_bps INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seller_fee_bps INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rules_version TEXT NOT NULL DEFAULT 'market-v2',
  ADD COLUMN IF NOT EXISTS submitted_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS submitted_game_minute INTEGER;

UPDATE market_orders o
SET owner_economic_id = owner.economic_id,
    instrument_id = instrument.id,
    filled_units = o.filled_quantity_units,
    eligible_batch_id = 0,
    sequence_no = nextval('market_order_sequence'),
    submitted_game_day = COALESCE(submitted_game_day, 1),
    submitted_game_minute = COALESCE(submitted_game_minute, 0)
FROM owner_registry owner, market_instruments instrument
WHERE o.owner_economic_id IS NULL
  -- This migration runs before the House cutover adds humans.house_id.
  -- Backfill legacy orders from their original Human owner; the later House
  -- ownership migration reconciles these owners without changing the order.
  AND owner.id = o.human_id
  AND instrument.symbol = 'SPOT-' || UPPER(o.product);

UPDATE market_orders
SET filled_units = filled_quantity_units
WHERE filled_units IS NULL;

UPDATE market_orders
SET sequence_no = nextval('market_order_sequence')
WHERE sequence_no IS NULL;

ALTER TABLE market_orders
  ALTER COLUMN owner_economic_id SET NOT NULL,
  ALTER COLUMN instrument_id SET NOT NULL,
  ALTER COLUMN filled_units SET NOT NULL,
  ALTER COLUMN eligible_batch_id SET NOT NULL,
  ALTER COLUMN sequence_no SET NOT NULL,
  ALTER COLUMN submitted_game_day SET NOT NULL,
  ALTER COLUMN submitted_game_minute SET NOT NULL;

ALTER TABLE market_orders
  ADD CONSTRAINT market_orders_owner_fk FOREIGN KEY (owner_economic_id) REFERENCES owner_registry(economic_id),
  ADD CONSTRAINT market_orders_instrument_fk FOREIGN KEY (instrument_id) REFERENCES market_instruments(id),
  ADD CONSTRAINT market_orders_order_contract_ck CHECK (
    filled_units >= 0 AND eligible_batch_id >= 0 AND sequence_no > 0 AND
    reserved_base_units >= 0 AND buyer_fee_bps BETWEEN 0 AND 500 AND seller_fee_bps BETWEEN 0 AND 500 AND
    submitted_game_minute BETWEEN 0 AND 1439
  );

CREATE INDEX IF NOT EXISTS market_orders_instrument_batch_idx
  ON market_orders(instrument_id, eligible_batch_id, status, limit_price_units, sequence_no);
CREATE INDEX IF NOT EXISTS market_orders_owner_idx ON market_orders(owner_economic_id, status);
