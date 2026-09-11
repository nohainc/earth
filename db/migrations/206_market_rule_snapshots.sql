-- Market V2 Plan 14: freeze the rules that govern accepted orders and batches.

ALTER TABLE market_orders
  ADD COLUMN IF NOT EXISTS rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE market_batches
  ADD COLUMN IF NOT EXISTS rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB;

UPDATE market_orders
SET rules_snapshot = jsonb_build_object(
  'rulesVersion', rules_version,
  'buyerFeeBps', buyer_fee_bps,
  'sellerFeeBps', seller_fee_bps
)
WHERE rules_snapshot = '{}'::JSONB;

UPDATE market_batches
SET rules_snapshot = jsonb_build_object('rulesVersion', rules_version)
WHERE rules_snapshot = '{}'::JSONB;

CREATE OR REPLACE FUNCTION earth_guard_market_order_rules()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.rules_version IS DISTINCT FROM NEW.rules_version
     OR OLD.buyer_fee_bps IS DISTINCT FROM NEW.buyer_fee_bps
     OR OLD.seller_fee_bps IS DISTINCT FROM NEW.seller_fee_bps
     OR OLD.rules_snapshot IS DISTINCT FROM NEW.rules_snapshot THEN
    RAISE EXCEPTION 'market order rules are immutable after acceptance';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS market_orders_rules_immutable ON market_orders;
CREATE TRIGGER market_orders_rules_immutable
BEFORE UPDATE OF rules_version, buyer_fee_bps, seller_fee_bps, rules_snapshot ON market_orders
FOR EACH ROW EXECUTE FUNCTION earth_guard_market_order_rules();

CREATE OR REPLACE FUNCTION earth_guard_market_batch_rules()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.rules_version IS DISTINCT FROM NEW.rules_version
     OR OLD.rules_snapshot IS DISTINCT FROM NEW.rules_snapshot THEN
    RAISE EXCEPTION 'market batch rules are immutable after creation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS market_batches_rules_immutable ON market_batches;
CREATE TRIGGER market_batches_rules_immutable
BEFORE UPDATE OF rules_version, rules_snapshot ON market_batches
FOR EACH ROW EXECUTE FUNCTION earth_guard_market_batch_rules();
