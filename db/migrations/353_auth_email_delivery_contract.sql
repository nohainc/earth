-- Auth email delivery contract: provider delivery and audit persistence are
-- separate outcomes, while correlation IDs remain idempotent.

ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS account_id TEXT REFERENCES auth_accounts(id);
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS correlation_id TEXT;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS provider TEXT;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE auth_email_deliveries ADD COLUMN IF NOT EXISTS recipient_masked TEXT;

-- Reconcile the original schema shape before enforcing the V2 contract. These
-- updates make the migration safe for databases that were created from
-- schema.sql before the observability migration existed.
DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'auth_email_deliveries'
       AND column_name = 'correlation_key'
  ) THEN
    EXECUTE $sql$UPDATE auth_email_deliveries
                 SET correlation_id = COALESCE(correlation_id, correlation_key, 'legacy-email:' || id::text)
               WHERE correlation_id IS NULL$sql$;
  ELSE
    UPDATE auth_email_deliveries
       SET correlation_id = 'legacy-email:' || id::text
     WHERE correlation_id IS NULL;
  END IF;
END $migration$;

DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'auth_email_deliveries'
       AND column_name = 'delivery_status'
  ) THEN
    EXECUTE $sql$UPDATE auth_email_deliveries
                 SET status = CASE delivery_status
                   WHEN 'delivered' THEN 'accepted'
                   WHEN 'failed' THEN 'failed'
                   ELSE 'failed'
                 END
               WHERE status IS NULL AND delivery_status IS NOT NULL$sql$;
  END IF;
END $migration$;

UPDATE auth_email_deliveries
   SET status = 'failed'
 WHERE status IS NULL;

UPDATE auth_email_deliveries
   SET recipient_masked = '[legacy-redacted]'
 WHERE recipient_masked IS NULL;

UPDATE auth_email_deliveries
   SET provider = 'legacy'
 WHERE provider IS NULL;

UPDATE auth_email_deliveries d
   SET account_id = a.id
  FROM auth_accounts a JOIN humans h ON h.house_id = a.house_id
 WHERE d.account_id IS NULL AND d.human_id = h.id;

UPDATE auth_email_deliveries
   SET accepted_at = COALESCE(accepted_at, created_at)
 WHERE status = 'accepted' AND accepted_at IS NULL;
UPDATE auth_email_deliveries
   SET failed_at = COALESCE(failed_at, created_at)
 WHERE status = 'failed' AND failed_at IS NULL;

ALTER TABLE auth_email_deliveries DROP COLUMN IF EXISTS recipient_email;
ALTER TABLE auth_email_deliveries DROP COLUMN IF EXISTS delivery_status;
ALTER TABLE auth_email_deliveries DROP COLUMN IF EXISTS correlation_key;
ALTER TABLE auth_email_deliveries DROP COLUMN IF EXISTS delivery_metadata;
ALTER TABLE auth_email_deliveries ALTER COLUMN recipient_masked SET NOT NULL;
ALTER TABLE auth_email_deliveries ALTER COLUMN correlation_id SET NOT NULL;
ALTER TABLE auth_email_deliveries ALTER COLUMN status SET DEFAULT 'accepted';
ALTER TABLE auth_email_deliveries DROP CONSTRAINT IF EXISTS auth_email_deliveries_status_ck;
ALTER TABLE auth_email_deliveries ADD CONSTRAINT auth_email_deliveries_status_ck CHECK (status IN ('accepted', 'failed'));
CREATE UNIQUE INDEX IF NOT EXISTS auth_email_deliveries_correlation_uq ON auth_email_deliveries(correlation_id);
CREATE INDEX IF NOT EXISTS auth_email_deliveries_account_idx ON auth_email_deliveries(account_id, created_at DESC);
