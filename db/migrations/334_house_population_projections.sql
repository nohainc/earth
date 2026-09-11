-- Death & Continuity V2 Plan 25.
-- Population and corporation membership are derived from persistent House
-- affiliations. Scalar columns remain compatibility/read projections only.

CREATE OR REPLACE VIEW city_population_summary AS
SELECT c.id AS city_id,
       COUNT(a.house_id)::INTEGER AS active_house_count
  FROM cities c
  LEFT JOIN house_affiliations a
    ON a.city_id = c.id AND a.status = 'ACTIVE'
 GROUP BY c.id;

CREATE OR REPLACE VIEW corporation_membership_summary AS
SELECT c.id AS corporation_id,
       COUNT(a.house_id)::INTEGER AS active_house_count
  FROM corporations c
  LEFT JOIN house_affiliations a
    ON a.corporation_id = c.id AND a.status = 'ACTIVE'
 GROUP BY c.id;

CREATE OR REPLACE FUNCTION earth_refresh_population_projections(
  p_corporation_id TEXT DEFAULT NULL,
  p_city_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE corporations c
     SET member_count = s.active_house_count
    FROM corporation_membership_summary s
   WHERE c.id = s.corporation_id
     AND (p_corporation_id IS NULL OR c.id = p_corporation_id);

  UPDATE cities c
     SET residents = s.active_house_count
    FROM city_population_summary s
   WHERE c.id = s.city_id
     AND (p_city_id IS NULL OR c.id = p_city_id);
END;
$$;

-- Reconcile existing compatibility counters once during cutover.
SELECT earth_refresh_population_projections();
