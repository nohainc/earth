-- Refine House rankings to measure House-owned and finalized activity only.

INSERT INTO ranking_metric_definitions
  (metric_code, category, title, methodology, rules_version, status)
VALUES
  ('MARKET_VOLUME_30D', 'HOUSE', 'Market volume · 30d',
   'Gross CREDIT quote value of finalized market fills involving the House during the trailing 30 game days.',
   'rankings-v2', 'ACTIVE')
ON CONFLICT (metric_code) DO UPDATE SET
  category = EXCLUDED.category,
  title = EXCLUDED.title,
  methodology = EXCLUDED.methodology,
  rules_version = EXCLUDED.rules_version,
  status = 'ACTIVE';

UPDATE ranking_metric_definitions
   SET title = 'House technology patents',
       methodology = 'Count of active technology patents owned by the House. Corporation technology access is not a House achievement and is excluded.',
       rules_version = 'rankings-v2',
       status = 'ACTIVE'
 WHERE metric_code = 'TECHNOLOGY';

UPDATE ranking_metric_definitions
   SET title = 'Successful Initiative contribution',
       methodology = 'Lifetime CREDIT contributions by the House that were applied to an Initiative which reached COMPLETED status. Escrowed and refunded funding is excluded.',
       rules_version = 'rankings-v2',
       status = 'ACTIVE'
 WHERE metric_code = 'PUBLIC_GOODS';

UPDATE ranking_metric_definitions
   SET title = 'Market role (retired)',
       methodology = 'Replaced by trailing-30-day CREDIT market volume.',
       rules_version = 'rankings-v2',
       status = 'RETIRED'
 WHERE metric_code = 'MARKET_ROLE';
