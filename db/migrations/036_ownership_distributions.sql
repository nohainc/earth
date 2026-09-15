-- EARTH ACTIVE MIGRATION: proportional ownership distribution payments

CREATE TABLE IF NOT EXISTS ownership_distribution_payments (
  id TEXT PRIMARY KEY,
  distribution_id TEXT NOT NULL REFERENCES ownership_distributions(id),
  holder_type TEXT NOT NULL CHECK (holder_type IN ('HOUSE','ORGANIZATION')),
  holder_id TEXT NOT NULL,
  ownership_units BIGINT NOT NULL CHECK (ownership_units > 0),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  economic_transaction_id BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS ownership_distribution_payments_holder_idx
  ON ownership_distribution_payments (holder_type, holder_id, id);
