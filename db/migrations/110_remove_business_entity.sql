-- Flatten the former Business entity into direct Human ownership.
-- This is intentionally a one-way migration. It must run before the
-- application version that no longer knows about Business records.

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.businesses') IS NULL THEN
    RETURN;
  END IF;

  -- A Business share held by somebody other than its registered owner cannot
  -- be represented after Business removal without an explicit settlement.
  -- Stop rather than silently deleting another Human's economic claim.
  IF EXISTS (
    SELECT 1
    FROM business_shares s
    JOIN businesses b ON b.id = s.business_id
    WHERE s.holder_id <> b.owner_id
  ) THEN
    RAISE EXCEPTION
      'Business removal requires settlement of externally held shares before migration';
  END IF;
END $$;

-- Buildings already have the canonical Human owner. Remove only the redundant
-- business attribution so private building ownership and settlement remain.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'buildings'
      AND column_name = 'business_id'
  ) THEN
    EXECUTE 'UPDATE buildings SET business_id = NULL WHERE business_id IS NOT NULL';
  END IF;
END $$;

-- Contracts remain Human-to-Human. Their optional Business attribution is
-- removed, while the contract itself and its financial history remain.
ALTER TABLE IF EXISTS negotiated_contracts
  DROP COLUMN IF EXISTS proposer_business_id,
  DROP COLUMN IF EXISTS counterparty_business_id;

ALTER TABLE IF EXISTS technology_licenses
  DROP COLUMN IF EXISTS licensee_business_id;

CREATE TABLE IF NOT EXISTS human_technology_subscriptions (
  human_id TEXT NOT NULL REFERENCES humans(id),
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  technology_key TEXT NOT NULL,
  subscription_cost_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  subscribed_game_day BIGINT,
  unsubscribed_game_day BIGINT,
  last_billed_game_day BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (human_id, technology_key)
);

DO $$
BEGIN
  IF to_regclass('public.business_technology_subscriptions') IS NOT NULL THEN
    INSERT INTO human_technology_subscriptions
      (human_id, corporation_id, technology_key, subscription_cost_credits,
       status, subscribed_game_day, unsubscribed_game_day, last_billed_game_day,
       updated_at)
    SELECT b.owner_id, s.corporation_id, s.technology_key,
           s.subscription_cost_credits, s.status, s.subscribed_game_day,
           s.unsubscribed_game_day, s.last_billed_game_day, s.updated_at
    FROM business_technology_subscriptions s
    JOIN businesses b ON b.id = s.business_id
    ON CONFLICT (human_id, technology_key) DO UPDATE
      SET status = EXCLUDED.status,
          last_billed_game_day = EXCLUDED.last_billed_game_day,
          updated_at = EXCLUDED.updated_at;
  END IF;
END $$;

-- Business-specific research adoption is replaced by direct Human adoption.
CREATE TABLE IF NOT EXISTS human_technology_adoptions (
  human_id TEXT NOT NULL REFERENCES humans(id),
  technology_id TEXT NOT NULL REFERENCES technologies(id),
  adopted_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','superseded','revoked')),
  PRIMARY KEY (human_id, technology_id)
);

DO $$
BEGIN
  IF to_regclass('public.business_technology_adoptions') IS NOT NULL THEN
    INSERT INTO human_technology_adoptions (human_id, technology_id, adopted_game_day, status)
    SELECT b.owner_id, a.technology_id, a.adopted_game_day, a.status
    FROM business_technology_adoptions a
    JOIN businesses b ON b.id = a.business_id
    ON CONFLICT (human_id, technology_id) DO UPDATE
      SET adopted_game_day = GREATEST(
        human_technology_adoptions.adopted_game_day,
        EXCLUDED.adopted_game_day
      ),
      status = EXCLUDED.status;
  END IF;
END $$;

-- Remove Business financial state and institutional registry rows.
DELETE FROM financial_states WHERE institution_kind = 'BUSINESS';
DELETE FROM bankruptcy_events WHERE institution_kind = 'BUSINESS';
DELETE FROM institutions WHERE kind = 'BUSINESS';

-- Clear the foreign key before removing the referenced Business table.
ALTER TABLE buildings DROP COLUMN IF EXISTS business_id;

DROP TABLE IF EXISTS merger_contracts;
DROP TABLE IF EXISTS business_technology_subscriptions;
DROP TABLE IF EXISTS business_technology_adoptions;
DROP TABLE IF EXISTS business_tax_allocation_rules;
DROP TABLE IF EXISTS business_employees;
DROP TABLE IF EXISTS business_management;
DROP TABLE IF EXISTS business_constitutions;
DROP TABLE IF EXISTS business_financials;
DROP TABLE IF EXISTS business_shares;
DROP TABLE IF EXISTS businesses;

ALTER TABLE financial_states
  DROP CONSTRAINT IF EXISTS financial_states_institution_kind_check;
ALTER TABLE financial_states
  ADD CONSTRAINT financial_states_institution_kind_check
  CHECK (institution_kind IN ('CITY','CORPORATION'));

ALTER TABLE bankruptcy_events
  DROP CONSTRAINT IF EXISTS bankruptcy_events_institution_kind_check;
ALTER TABLE bankruptcy_events
  ADD CONSTRAINT bankruptcy_events_institution_kind_check
  CHECK (institution_kind IN ('CITY','CORPORATION'));

COMMIT;
