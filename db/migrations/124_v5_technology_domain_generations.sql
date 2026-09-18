-- EARTH ACTIVE MIGRATION: V5 domain generation catalog

INSERT INTO technology_generations
  (id, domain_id, generation_number, name, predecessor_id, minimum_game_day, research_points_required, status)
SELECT 'TECH-GEN-' || d.code || '-1', d.id, 1, d.name || ' Generation I', NULL, 1, 100, 'ELIGIBLE'
  FROM technology_domains d
 WHERE d.code IN ('ENERGY','FOOD','MATERIAL','COMPONENTS','COMPUTE','CONNECTIVITY','HEALTH','RESEARCH')
ON CONFLICT (id) DO NOTHING;

INSERT INTO technology_generations
  (id, domain_id, generation_number, name, predecessor_id, minimum_game_day, research_points_required, status)
SELECT 'TECH-GEN-' || d.code || '-2', d.id, 2, d.name || ' Generation II',
       'TECH-GEN-' || d.code || '-1', 30, 250, 'LOCKED'
  FROM technology_domains d
 WHERE d.code IN ('ENERGY','FOOD','MATERIAL','COMPONENTS','COMPUTE','CONNECTIVITY','HEALTH','RESEARCH')
ON CONFLICT (id) DO NOTHING;
