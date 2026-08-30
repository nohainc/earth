-- Migration 080: Drop deprecated schema relics
--
-- Prune unused and redundant tables from early schema iterations:
-- 1. asset_ownership_events & assets: Superseded by buildings and generic ownership_events.
-- 2. character_lineage: Superseded by houses and house_lineage_records.
-- 3. technology_prerequisites & technology_events: Unused static/audit relics.

DROP TABLE IF EXISTS asset_ownership_events CASCADE;
DROP TABLE IF EXISTS assets CASCADE;
DROP TABLE IF EXISTS character_lineage CASCADE;
DROP TABLE IF EXISTS technology_prerequisites CASCADE;
DROP TABLE IF EXISTS technology_events CASCADE;
