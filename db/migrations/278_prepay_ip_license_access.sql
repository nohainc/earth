-- Technology & Research V2 Plan 25: daily license fees are prepaid.

-- Keep the Plan 24 implementation as the worker and wrap it with retry/
-- suspension policy. A failed payment is not silently treated as valid access.
ALTER FUNCTION earth_settle_technology_license_fees(BIGINT)
  RENAME TO earth_settle_technology_license_fees_worker;

CREATE OR REPLACE FUNCTION earth_settle_technology_license_fees(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_paid BIGINT;
BEGIN
  UPDATE technology_license_contracts
  SET status = 'ACTIVE'
  WHERE status = 'SUSPENDED'
    AND effective_from_game_day <= p_game_day
    AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day);

  v_paid := earth_settle_technology_license_fees_worker(p_game_day);

  UPDATE technology_license_contracts
  SET status = 'SUSPENDED'
  WHERE status = 'ACTIVE'
    AND daily_fee_units > 0
    AND effective_from_game_day <= p_game_day
    AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)
    AND paid_through_game_day < p_game_day;

  RETURN v_paid;
END;
$$;

CREATE OR REPLACE FUNCTION earth_corporation_has_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM corporation_technology_access a
    WHERE a.corporation_economic_id = p_corporation_economic_id
      AND a.technology_id = p_technology_id
      AND a.status = 'ACTIVE'
      AND a.effective_from_game_day <= p_game_day
      AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
      AND (
        a.access_source <> 'LICENSED'
        OR EXISTS (
          SELECT 1
          FROM technology_license_contracts c
          WHERE c.id = a.source_id
            AND c.status = 'ACTIVE'
            AND c.paid_through_game_day >= p_game_day
        )
      )
  );
$$;

COMMENT ON FUNCTION earth_settle_technology_license_fees(BIGINT) IS
  'Prepay IP_LICENSE_DAILY fees before building settlement; suspend unpaid contracts.';
