-- Technology & Research V2 Plan 29: patent expiry has an actual access and
-- billing consequence.

CREATE OR REPLACE FUNCTION earth_terminate_technology_license_contracts_on_patent_expiry()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'EXPIRED' AND OLD.status IS DISTINCT FROM 'EXPIRED' THEN
    UPDATE technology_license_contracts
    SET status = 'EXPIRED'
    WHERE patent_id = NEW.id
      AND status IN ('PENDING', 'ACTIVE', 'SUSPENDED');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_patent_expiry_contract_trigger ON technology_patents;
CREATE TRIGGER technology_patent_expiry_contract_trigger
  AFTER UPDATE OF status ON technology_patents
  FOR EACH ROW EXECUTE FUNCTION earth_terminate_technology_license_contracts_on_patent_expiry();

-- Apply the rule to any already-expired patents on upgrade.
UPDATE technology_license_contracts c
SET status = 'EXPIRED'
FROM technology_patents p
WHERE c.patent_id = p.id
  AND p.status = 'EXPIRED'
  AND c.status IN ('PENDING', 'ACTIVE', 'SUSPENDED');

COMMENT ON FUNCTION earth_finalize_technology_public_domain(BIGINT) IS
  'Expires V2 patents after their exclusive day and makes access free from the following game day.';
