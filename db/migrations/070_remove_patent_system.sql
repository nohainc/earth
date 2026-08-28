-- Retire patents and licensing. Research remains, and completed research is
-- adopted directly by businesses and buildings.

DELETE FROM ledger_entries
WHERE reason_type IN (
  'patent_grant', 'patent_license_purchase', 'patent_license_renewal',
  'technology_license_fee', 'technology_royalty'
);

DELETE FROM notifications
WHERE notification_type IN ('patent', 'patent_license')
   OR title ILIKE '%patent%'
   OR body ILIKE '%patent%';

DROP TABLE IF EXISTS building_patent_licenses;
DROP TABLE IF EXISTS technology_licenses;
DROP TABLE IF EXISTS corporation_technology_shares;
DROP TABLE IF EXISTS patents;

ALTER TABLE buildings DROP COLUMN IF EXISTS required_patent_id;
ALTER TABLE buildings DROP COLUMN IF EXISTS patent_license_status;

DROP INDEX IF EXISTS idx_bld_patent_lic_licensee;
DROP INDEX IF EXISTS idx_bld_patent_lic_building;
DROP INDEX IF EXISTS idx_bld_patent_lic_city;
DROP INDEX IF EXISTS uq_building_patent_active;
DROP INDEX IF EXISTS uq_city_patent_active;
