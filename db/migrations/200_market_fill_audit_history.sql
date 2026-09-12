-- Market V2 Plan 8: complete bidirectional fill/audit history.
ALTER TABLE market_fills
  ADD COLUMN IF NOT EXISTS buyer_economic_id BIGINT,
  ADD COLUMN IF NOT EXISTS seller_economic_id BIGINT,
  ADD COLUMN IF NOT EXISTS gross_quote_units BIGINT,
  ADD COLUMN IF NOT EXISTS buyer_fee_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seller_fee_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS economic_transaction_id BIGINT,
  ADD COLUMN IF NOT EXISTS sequence_no BIGINT,
  ADD COLUMN IF NOT EXISTS game_day BIGINT,
  ADD COLUMN IF NOT EXISTS game_minute INTEGER;

WITH numbered AS (
  SELECT f.id, f.buy_order_id, f.sell_order_id, f.batch_id, f.instrument_id,
         ROW_NUMBER() OVER (PARTITION BY f.batch_id, f.instrument_id ORDER BY f.created_at, f.id)::BIGINT AS fill_sequence
    FROM market_fills f
)
UPDATE market_fills f
SET buyer_economic_id = buyer.economic_id,
    seller_economic_id = seller.economic_id,
    gross_quote_units = COALESCE(f.gross_quote_units, f.quote_units),
    economic_transaction_id = COALESCE(f.economic_transaction_id, batch_instrument.economic_transaction_id),
    sequence_no = COALESCE(f.sequence_no, numbered.fill_sequence),
    game_day = COALESCE(f.game_day, FLOOR(batch.start_total_game_minute / 1440)::BIGINT + 1),
    game_minute = COALESCE(f.game_minute, (batch.start_total_game_minute % 1440)::INTEGER)
FROM numbered
JOIN market_orders buy_order ON buy_order.id = numbered.buy_order_id
JOIN owner_registry buyer ON buyer.id = buy_order.human_id
JOIN market_orders sell_order ON sell_order.id = numbered.sell_order_id
JOIN owner_registry seller ON seller.id = sell_order.human_id
JOIN market_batches batch ON batch.id = numbered.batch_id
JOIN market_batch_instruments batch_instrument ON batch_instrument.batch_id = numbered.batch_id AND batch_instrument.instrument_id = numbered.instrument_id
WHERE numbered.id = f.id;

ALTER TABLE market_fills
  ALTER COLUMN buyer_economic_id SET NOT NULL,
  ALTER COLUMN seller_economic_id SET NOT NULL,
  ALTER COLUMN gross_quote_units SET NOT NULL,
  ALTER COLUMN economic_transaction_id SET NOT NULL,
  ALTER COLUMN sequence_no SET NOT NULL,
  ALTER COLUMN game_day SET NOT NULL,
  ALTER COLUMN game_minute SET NOT NULL;

ALTER TABLE market_fills
  ADD CONSTRAINT market_fills_audit_coordinates_ck CHECK (sequence_no > 0 AND game_minute BETWEEN 0 AND 1439),
  ADD CONSTRAINT market_fills_owner_fk FOREIGN KEY (buyer_economic_id) REFERENCES owner_registry(economic_id),
  ADD CONSTRAINT market_fills_seller_fk FOREIGN KEY (seller_economic_id) REFERENCES owner_registry(economic_id),
  ADD CONSTRAINT market_fills_transaction_fk FOREIGN KEY (economic_transaction_id) REFERENCES economic_transactions(id);

CREATE INDEX IF NOT EXISTS market_fills_transaction_idx ON market_fills(economic_transaction_id);
CREATE INDEX IF NOT EXISTS market_fills_buyer_idx ON market_fills(buyer_economic_id, game_day);
CREATE INDEX IF NOT EXISTS market_fills_seller_idx ON market_fills(seller_economic_id, game_day);
