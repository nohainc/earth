ALTER TABLE technology_licenses
  ADD COLUMN IF NOT EXISTS licensee_business_id TEXT REFERENCES businesses(id);

CREATE INDEX IF NOT EXISTS technology_licenses_business_idx
  ON technology_licenses(licensee_business_id, status);
