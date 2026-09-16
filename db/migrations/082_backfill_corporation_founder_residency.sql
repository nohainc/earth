-- EARTH ACTIVE MIGRATION: restore primary residency for existing founders.
-- Corporation membership and Territory residency are separate relations, but
-- a founder's newly created primary Territory is also their initial home.

INSERT INTO house_residencies
  (id, house_id, territory_id, residency_class, effective_from_game_day, correlation_id)
SELECT 'RES-' || ha.corporation_id || '-' || ha.house_id,
       ha.house_id,
       ha.primary_territory_id,
       'PRIMARY',
       GREATEST(ha.joined_game_day, 1),
       'residency:corporation-genesis:' || ha.corporation_id || ':' || ha.house_id
  FROM house_affiliations ha
 WHERE ha.status = 'ACTIVE'
   AND ha.primary_territory_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1
       FROM house_residencies r
      WHERE r.house_id = ha.house_id
        AND r.status = 'ACTIVE'
        AND r.residency_class = 'PRIMARY'
   )
ON CONFLICT (id) DO NOTHING;
