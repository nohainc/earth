-- EARTH ACTIVE MIGRATION: scope market fill sequence numbers by instrument

ALTER TABLE market_fills
  DROP CONSTRAINT IF EXISTS market_fills_batch_id_sequence_no_key;

ALTER TABLE market_fills
  ADD CONSTRAINT market_fills_batch_instrument_sequence_uq
  UNIQUE (batch_id, instrument_id, sequence_no);
