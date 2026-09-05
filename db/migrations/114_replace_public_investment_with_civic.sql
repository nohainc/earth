-- Replace physical public-investment buildings with ordinary city-owned civic buildings.
-- The migration is intentionally forward-only: existing share principal is refunded
-- through the financial ledger before the obsolete share table is removed.

BEGIN;

DO $$
DECLARE
  holding RECORD;
  investor_account TEXT;
  city_account TEXT;
  refund NUMERIC(20,2);
  game_day_value BIGINT;
BEGIN
  SELECT game_day INTO game_day_value FROM world_state WHERE id = 'WORLD' FOR UPDATE;

  IF to_regclass('public.building_investment_shares') IS NOT NULL THEN
    FOR holding IN
      SELECT s.building_id, s.investor_id, s.invested_credits, b.city_id
      FROM building_investment_shares s
      JOIN buildings b ON b.id = s.building_id
      WHERE b.ownership_class = 'public_investment'
      FOR UPDATE OF s, b
    LOOP
      refund := GREATEST(0, COALESCE(holding.invested_credits, 0));
      IF refund = 0 THEN CONTINUE; END IF;

      SELECT account_id INTO investor_account
      FROM account_balances
      WHERE owner_id = holding.investor_id AND currency = 'CREDIT'
      ORDER BY account_id
      LIMIT 1
      FOR UPDATE;
      IF investor_account IS NULL THEN
        RAISE EXCEPTION 'Cannot refund public investment: missing investor account %', holding.investor_id;
      END IF;

      city_account := 'account-city-' || holding.city_id;
      IF NOT EXISTS (SELECT 1 FROM account_balances WHERE account_id = city_account AND currency = 'CREDIT') THEN
        RAISE EXCEPTION 'Cannot refund public investment: missing city account %', city_account;
      END IF;
      IF (SELECT balance FROM account_balances WHERE account_id = city_account AND currency = 'CREDIT' FOR UPDATE) < refund THEN
        RAISE EXCEPTION 'Cannot refund public investment: city account % cannot cover % Credits', city_account, refund;
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM ledger_entries
        WHERE correlation_id = 'MIGRATION-114-REFUND-' || holding.building_id || '-' || holding.investor_id
      ) THEN
        UPDATE account_balances SET balance = balance - refund WHERE account_id = city_account;
        UPDATE account_balances SET balance = balance + refund WHERE account_id = investor_account;
        INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id)
        VALUES (gen_random_uuid(), COALESCE(game_day_value, 1), city_account, investor_account, refund, 'CREDIT',
                'public_investment_migration_refund', holding.building_id, 'migration-114',
                'MIGRATION-114-REFUND-' || holding.building_id || '-' || holding.investor_id);
      END IF;
    END LOOP;
  END IF;
END $$;

DROP TRIGGER IF EXISTS building_catalog_original_immutable ON building_catalog;

UPDATE building_catalog
SET ownership_class = 'civic', updated_at = CURRENT_TIMESTAMP
WHERE ownership_class = 'public_investment';

ALTER TABLE buildings ALTER COLUMN owner_id DROP NOT NULL;

UPDATE buildings
SET ownership_class = 'civic', owner_id = NULL, updated_at = CURRENT_TIMESTAMP
WHERE ownership_class = 'public_investment';

ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_ownership_class_check;
ALTER TABLE buildings ADD CONSTRAINT buildings_ownership_class_check
  CHECK (ownership_class IN ('private','civic'));
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_ownership_scope_check;
ALTER TABLE buildings ADD CONSTRAINT buildings_ownership_scope_check
  CHECK (
    (ownership_class = 'private' AND owner_id IS NOT NULL)
    OR (ownership_class = 'civic' AND city_id IS NOT NULL)
  );

DROP TABLE IF EXISTS building_investment_shares;

ALTER TABLE building_catalog DROP COLUMN IF EXISTS dividend_share_percent;

CREATE TRIGGER building_catalog_original_immutable BEFORE UPDATE ON building_catalog
FOR EACH ROW EXECUTE FUNCTION earth_prevent_original_catalog_mutation();

COMMIT;
