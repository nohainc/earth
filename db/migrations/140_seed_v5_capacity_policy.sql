-- EARTH ACTIVE MIGRATION: seed the canonical Day-1 V5 capacity policy.
-- Capacity settlement fails closed when its Earth snapshot is incomplete, so
-- fresh installations need one explicit constitutional policy.

INSERT INTO progressive_policy_schedules
  (id, code, basis_type, authority_institution_id, version, status, effective_from_game_day)
VALUES
  ('EARTH-CORP-CAPACITY-DEFAULT', 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'EARTH_CORPORATION_CAPACITY', 'EARTH', 1, 'DRAFT', 1),
  ('EARTH-HOUSE-CAPACITY-DEFAULT', 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'CORPORATION_HOUSE_CAPACITY', 'EARTH', 1, 'DRAFT', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO progressive_policy_brackets
  (schedule_id, ordinal, lower_bound_units, upper_bound_units, marginal_multiplier_numerator, marginal_multiplier_denominator)
VALUES
  ('EARTH-CORP-CAPACITY-DEFAULT', 1, 0, NULL, 1, 1),
  ('EARTH-HOUSE-CAPACITY-DEFAULT', 1, 0, NULL, 1, 1)
ON CONFLICT (schedule_id, ordinal) DO NOTHING;

-- The original validator uses an unassigned RECORD in `previous IS NOT NULL`,
-- which PostgreSQL rejects when the first active schedule is validated. Keep
-- the validator semantics but use scalar state for the forward migration.
CREATE OR REPLACE FUNCTION earth_validate_v5_progressive_schedule(p_schedule_id TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  row_item RECORD;
  previous_upper BIGINT;
  previous_numerator BIGINT;
  previous_denominator BIGINT;
  has_previous BOOLEAN := FALSE;
  count_rows INTEGER := 0;
BEGIN
  FOR row_item IN
    SELECT ordinal, lower_bound_units, upper_bound_units,
           marginal_multiplier_numerator, marginal_multiplier_denominator
      FROM progressive_policy_brackets
     WHERE schedule_id = p_schedule_id
     ORDER BY ordinal
  LOOP
    count_rows := count_rows + 1;
    IF row_item.ordinal <> count_rows THEN RAISE EXCEPTION 'V5 progressive ordinals must be contiguous'; END IF;
    IF count_rows = 1 AND row_item.lower_bound_units <> 0 THEN RAISE EXCEPTION 'V5 progressive schedule must begin at zero'; END IF;
    IF has_previous AND previous_upper IS DISTINCT FROM row_item.lower_bound_units THEN RAISE EXCEPTION 'V5 progressive brackets must be contiguous'; END IF;
    IF has_previous AND row_item.marginal_multiplier_numerator::NUMERIC * previous_denominator::NUMERIC < previous_numerator::NUMERIC * row_item.marginal_multiplier_denominator::NUMERIC THEN RAISE EXCEPTION 'V5 progressive multipliers must be non-decreasing'; END IF;
    previous_upper := row_item.upper_bound_units;
    previous_numerator := row_item.marginal_multiplier_numerator;
    previous_denominator := row_item.marginal_multiplier_denominator;
    has_previous := TRUE;
  END LOOP;
  IF count_rows = 0 OR previous_upper IS NOT NULL THEN RAISE EXCEPTION 'V5 progressive schedule must have an open-ended final bracket'; END IF;
END;
$$;

UPDATE progressive_policy_schedules
   SET status = 'ACTIVE'
 WHERE id IN ('EARTH-CORP-CAPACITY-DEFAULT', 'EARTH-HOUSE-CAPACITY-DEFAULT');

INSERT INTO v5_capacity_policy_versions
  (id, version, standard_territory_capacity_units, earth_base_capacity_rate_units,
   earth_corporation_schedule_id, earth_house_schedule_id, effective_from_game_day, status)
VALUES
  ('V5-EARTH-POLICY-1', 1, 100, 1000,
   'EARTH-CORP-CAPACITY-DEFAULT', 'EARTH-HOUSE-CAPACITY-DEFAULT', 1, 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, status)
VALUES
  ('V5-CONST-EARTH-CAPACITY-1', 'EARTH.CAPACITY.STANDARD', 'EARTH', 'EARTH', 1, '{"value":"100"}'::JSONB, 1, 'ACTIVE'),
  ('V5-CONST-EARTH-RATE-1', 'EARTH.CAPACITY.BASE_RATE', 'EARTH', 'EARTH', 1, '{"value":"1000"}'::JSONB, 1, 'ACTIVE'),
  ('V5-CONST-EARTH-SCHEDULE-1', 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'EARTH', 'EARTH', 1, '{"scheduleId":"EARTH-CORP-CAPACITY-DEFAULT"}'::JSONB, 1, 'ACTIVE'),
  ('V5-CONST-EARTH-HOUSE-SCHEDULE-1', 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'EARTH', 'EARTH', 1, '{"scheduleId":"EARTH-HOUSE-CAPACITY-DEFAULT"}'::JSONB, 1, 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

UPDATE resolved_constitution_snapshots_v5
   SET rules_json = rules_json || jsonb_build_object(
         'EARTH.CAPACITY.STANDARD', '100',
         'EARTH.CAPACITY.BASE_RATE', '1000',
         'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'EARTH-CORP-CAPACITY-DEFAULT',
         'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'EARTH-HOUSE-CAPACITY-DEFAULT'),
       version_ids = version_ids || jsonb_build_object(
         'EARTH.CAPACITY.STANDARD', 'V5-CONST-EARTH-CAPACITY-1',
         'EARTH.CAPACITY.BASE_RATE', 'V5-CONST-EARTH-RATE-1',
         'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'V5-CONST-EARTH-SCHEDULE-1',
         'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'V5-CONST-EARTH-HOUSE-SCHEDULE-1')
 WHERE authority_type = 'EARTH' AND authority_id = 'EARTH';
