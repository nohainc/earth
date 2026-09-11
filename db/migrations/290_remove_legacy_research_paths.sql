-- Technology & Research V2 Plan 38: remove superseded R&D/IP schemas.
-- The unified corporation_research_projects table and V2 access/patent/license
-- tables are now authoritative. Development data is intentionally disposable.

DROP TABLE IF EXISTS corporation_building_research_projects CASCADE;
DROP TABLE IF EXISTS corporation_technology_projects CASCADE;
DROP TABLE IF EXISTS research_projects CASCADE;
DROP TABLE IF EXISTS technologies CASCADE;

-- These may have been removed by earlier migrations; keep the cleanup
-- idempotent for databases created from intermediate development branches.
DROP TABLE IF EXISTS human_technology_adoptions CASCADE;
DROP TABLE IF EXISTS human_technology_subscriptions CASCADE;
DROP TABLE IF EXISTS corporation_technology_shares CASCADE;
DROP TABLE IF EXISTS business_technology_subscriptions CASCADE;
DROP TABLE IF EXISTS technology_licenses CASCADE;
DROP TABLE IF EXISTS building_patent_licenses CASCADE;

COMMENT ON TABLE corporation_research_projects IS
  'Unified V2 research queue. Legacy research and technology progress tables were removed in migration 290.';
