-- Technology & Research V2 Plan 12: resolve private industrial technology
-- through current corporation membership at settlement time.

CREATE OR REPLACE FUNCTION earth_building_corporation_economic_id(
  p_building_id TEXT
)
RETURNS BIGINT
LANGUAGE SQL
STABLE
AS $$
  SELECT CASE
    WHEN b.ownership_class = 'private' THEN COALESCE(corporation.economic_id, owner.economic_id)
    ELSE owner.economic_id
  END
  FROM buildings b
  JOIN owner_registry owner ON owner.id = COALESCE(b.owner_id, b.city_id)
  LEFT JOIN memberships membership
    ON membership.human_id = b.owner_id
   AND b.ownership_class = 'private'
  LEFT JOIN owner_registry corporation ON corporation.id = membership.corporation_id
  WHERE b.id = p_building_id;
$$;

COMMENT ON FUNCTION earth_building_corporation_economic_id(TEXT) IS
  'Resolves private-building technology through the owner human current corporation; civic assets use their direct owner.';

