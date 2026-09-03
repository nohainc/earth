-- Migration: 094_fix_private_estate_base_tier.sql
-- Description: Fix default user estate plots that were mistakenly set or defaulted to Tier 3 High-Rise Arcology Strata.

UPDATE buildings
SET 
  tier = 1,
  catalog_id = 'private-estate-plot-t1',
  name = 'Ground Estate Deed',
  updated_at = CURRENT_TIMESTAMP
WHERE building_type = 'private-estate-plot'
  AND (tier IS NULL OR tier = 3 OR catalog_id = 'private-estate-plot-t3' OR name = 'High-Rise Arcology Strata');
