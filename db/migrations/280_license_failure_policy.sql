-- Technology & Research V2 Plan 28: failed daily fees suspend access.

ALTER TABLE technology_license_contracts
  ADD COLUMN IF NOT EXISTS suspended_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT;

CREATE OR REPLACE FUNCTION earth_record_technology_license_suspension()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'SUSPENDED' AND (OLD.status IS DISTINCT FROM 'SUSPENDED') THEN
    NEW.suspended_game_day := COALESCE(NEW.suspended_game_day, NEW.paid_through_game_day + 1);
    NEW.suspension_reason := COALESCE(NEW.suspension_reason, 'IP_LICENSE_DAILY_PAYMENT_UNAVAILABLE');
  ELSIF NEW.status = 'ACTIVE' AND OLD.status = 'SUSPENDED' THEN
    NEW.suspended_game_day := NULL;
    NEW.suspension_reason := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_license_suspension_policy_trigger
  ON technology_license_contracts;
CREATE TRIGGER technology_license_suspension_policy_trigger
  BEFORE UPDATE OF status ON technology_license_contracts
  FOR EACH ROW EXECUTE FUNCTION earth_record_technology_license_suspension();

COMMENT ON COLUMN technology_license_contracts.suspension_reason IS
  'Operational suspension reason; unpaid daily fees do not create tax-like arrears.';
COMMENT ON COLUMN technology_license_contracts.upfront_fee_units IS
  'Fixed activation fee; no automatic refund is created by daily payment failure.';
