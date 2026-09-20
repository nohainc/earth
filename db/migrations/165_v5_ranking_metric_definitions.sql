-- V5 ranking definitions: dimensions must remain physically and economically
-- valid. Historical snapshots remain immutable under their original metric.

INSERT INTO ranking_metric_definitions
  (metric_code, category, title, methodology, rules_version, status)
VALUES
  ('LIQUID_CREDIT', 'HOUSE', 'Liquid CREDIT',
   'Active CREDIT account balances owned by the House; resource inventories are excluded because they use a different unit dimension.',
   'rankings-v2', 'ACTIVE')
ON CONFLICT (metric_code) DO UPDATE SET
  category = EXCLUDED.category,
  title = EXCLUDED.title,
  methodology = EXCLUDED.methodology,
  rules_version = EXCLUDED.rules_version,
  status = 'ACTIVE';

UPDATE ranking_metric_definitions
   SET title = 'Liquid CREDIT',
       methodology = 'Active CREDIT account balances owned by the House; resource inventories are excluded because they use a different unit dimension.',
       rules_version = 'rankings-v2',
       status = 'RETIRED'
 WHERE metric_code = 'WEALTH';

UPDATE ranking_metric_definitions
   SET title = 'Productive capacity footprint',
       methodology = 'Sum of active building_catalog.slot_footprint units owned by the House; buildings under construction are excluded.',
       rules_version = 'rankings-v2',
       status = 'ACTIVE'
 WHERE metric_code = 'PRODUCTIVE_CAPACITY';

UPDATE ranking_metric_definitions
   SET status = 'RETIRED', rules_version = 'rankings-v2'
 WHERE metric_code IN ('ORGANIZATION_SCALE', 'TERRITORY_QUALITY');
