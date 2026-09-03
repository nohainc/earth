-- Private Estate Plots are personal property and do not belong to a city.
ALTER TABLE buildings ALTER COLUMN city_id DROP NOT NULL;
ALTER TABLE building_settlement_journals ALTER COLUMN city_id DROP NOT NULL;

UPDATE buildings
SET city_id = NULL,
    name = CASE WHEN tier = 1 THEN 'Private Estate Plot' ELSE name END,
    updated_at = CURRENT_TIMESTAMP
WHERE building_type = 'private-estate-plot'
  AND ownership_class = 'private';

UPDATE building_catalog
SET name = 'Private Estate Plot',
    description = 'Personal residential plot and private vertical capacity foundation.'
WHERE id = 'private-estate-plot-t1';
