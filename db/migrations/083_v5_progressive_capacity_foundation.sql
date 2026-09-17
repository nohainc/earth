-- EARTH ACTIVE MIGRATION: V5 progressive policy and pooled capacity foundation.
-- Additive only: legacy Territory/residency columns remain available for
-- compatibility and historical audit during the V5 rollout.

CREATE TABLE progressive_policy_schedules (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL,
  basis_type TEXT NOT NULL CHECK (basis_type IN ('EARTH_CORPORATION_CAPACITY','CORPORATION_HOUSE_CAPACITY','HOUSE_INCOME_TAX')),
  authority_institution_id TEXT NOT NULL REFERENCES institutions(id),
  version INTEGER NOT NULL CHECK (version > 0),
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (code, version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE TABLE progressive_policy_brackets (
  schedule_id TEXT NOT NULL REFERENCES progressive_policy_schedules(id),
  ordinal INTEGER NOT NULL CHECK (ordinal >= 1),
  lower_bound_units BIGINT NOT NULL CHECK (lower_bound_units >= 0),
  upper_bound_units BIGINT CHECK (upper_bound_units IS NULL OR upper_bound_units > lower_bound_units),
  marginal_multiplier_numerator BIGINT NOT NULL CHECK (marginal_multiplier_numerator >= 0),
  marginal_multiplier_denominator BIGINT NOT NULL CHECK (marginal_multiplier_denominator > 0),
  PRIMARY KEY (schedule_id, ordinal),
  UNIQUE (schedule_id, lower_bound_units)
);

CREATE TABLE v5_capacity_policy_versions (
  id TEXT PRIMARY KEY,
  version INTEGER NOT NULL CHECK (version > 0),
  standard_territory_capacity_units BIGINT NOT NULL CHECK (standard_territory_capacity_units > 0),
  earth_base_capacity_rate_units BIGINT NOT NULL CHECK (earth_base_capacity_rate_units >= 0),
  earth_corporation_schedule_id TEXT NOT NULL REFERENCES progressive_policy_schedules(id),
  earth_house_schedule_id TEXT NOT NULL REFERENCES progressive_policy_schedules(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE TABLE corporation_capacity_policy_versions (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  version INTEGER NOT NULL CHECK (version > 0),
  house_base_capacity_rate_units BIGINT NOT NULL CHECK (house_base_capacity_rate_units >= 0),
  house_schedule_id TEXT NOT NULL REFERENCES progressive_policy_schedules(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (corporation_id, version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE TABLE corporation_capacity_state_v5 (
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  residential_units_used BIGINT NOT NULL CHECK (residential_units_used >= 0),
  private_building_units_used BIGINT NOT NULL CHECK (private_building_units_used >= 0),
  public_building_units_used BIGINT NOT NULL CHECK (public_building_units_used >= 0),
  total_occupied_units BIGINT NOT NULL CHECK (total_occupied_units = residential_units_used + private_building_units_used + public_building_units_used),
  standard_territory_capacity_units BIGINT NOT NULL CHECK (standard_territory_capacity_units > 0),
  required_territory_units BIGINT NOT NULL CHECK (required_territory_units >= 0),
  rules_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_id, game_day)
);

CREATE TABLE house_capacity_statements_v5 (
  house_id TEXT NOT NULL REFERENCES houses(id),
  corporation_id TEXT REFERENCES corporations(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  residential_units BIGINT NOT NULL CHECK (residential_units IN (0, 1)),
  building_units BIGINT NOT NULL CHECK (building_units >= 0),
  total_units BIGINT NOT NULL CHECK (total_units = residential_units + building_units),
  base_rate_units BIGINT NOT NULL CHECK (base_rate_units >= 0),
  progressive_schedule_id TEXT REFERENCES progressive_policy_schedules(id),
  assessed_rent_units BIGINT NOT NULL DEFAULT 0 CHECK (assessed_rent_units >= 0),
  paid_rent_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_rent_units >= 0),
  arrears_units BIGINT NOT NULL DEFAULT 0 CHECK (arrears_units >= 0),
  delinquency_status TEXT NOT NULL DEFAULT 'CURRENT' CHECK (delinquency_status IN ('CURRENT','GRACE','RESTRICTED','SUSPENDED','RESOLVING')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (house_id, game_day)
);

ALTER TABLE financial_obligations DROP CONSTRAINT IF EXISTS financial_obligations_obligation_type_check;
ALTER TABLE financial_obligations ADD CONSTRAINT financial_obligations_obligation_type_check
  CHECK (obligation_type IN ('TAX','ROYALTY','LICENSE_PAYMENT','LOAN_PAYMENT','SERVICE_INVOICE','FINE_FEE','CAPACITY_RENT'));

CREATE TABLE v5_capacity_obligations (
  id TEXT PRIMARY KEY,
  capacity_level TEXT NOT NULL CHECK (capacity_level IN ('HOUSE','CORPORATION')),
  house_id TEXT REFERENCES houses(id),
  corporation_id TEXT REFERENCES corporations(id),
  payer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  usage_units BIGINT NOT NULL CHECK (usage_units >= 0),
  base_rate_units BIGINT NOT NULL CHECK (base_rate_units >= 0),
  schedule_id TEXT NOT NULL REFERENCES progressive_policy_schedules(id),
  assessed_units BIGINT NOT NULL CHECK (assessed_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0 AND paid_units <= assessed_units),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','ARREARS')),
  financial_obligation_id TEXT REFERENCES financial_obligations(id),
  payment_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((status = 'PAID' AND paid_units = assessed_units) OR status <> 'PAID'),
  CHECK ((capacity_level = 'HOUSE' AND house_id IS NOT NULL) OR (capacity_level = 'CORPORATION' AND corporation_id IS NOT NULL))
);

CREATE INDEX v5_capacity_obligations_house_day_idx ON v5_capacity_obligations (house_id, game_day);
CREATE INDEX v5_capacity_obligations_corporation_day_idx ON v5_capacity_obligations (corporation_id, game_day);

ALTER TABLE territories ADD COLUMN IF NOT EXISTS v5_sequence_number INTEGER;
ALTER TABLE territories ADD COLUMN IF NOT EXISTS v5_capacity_units BIGINT;
ALTER TABLE territories ADD COLUMN IF NOT EXISTS v5_activated_game_day BIGINT;
ALTER TABLE territories ADD COLUMN IF NOT EXISTS v5_retired_game_day BIGINT;
ALTER TABLE territories ADD COLUMN IF NOT EXISTS v5_rules_version TEXT;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS v5_productive_status TEXT NOT NULL DEFAULT 'ACTIVE';
DO $$ BEGIN
  ALTER TABLE buildings ADD CONSTRAINT buildings_v5_productive_status_check CHECK (v5_productive_status IN ('ACTIVE','SUSPENDED'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS territories_v5_corporation_sequence_uq
  ON territories (corporation_id, v5_sequence_number) WHERE v5_sequence_number IS NOT NULL;

CREATE TABLE corporation_membership_applications_v5 (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED','WITHDRAWN')),
  requested_game_day BIGINT NOT NULL CHECK (requested_game_day >= 1),
  decided_game_day BIGINT,
  decided_by_human_id TEXT REFERENCES humans(id),
  decision_reason TEXT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX corporation_membership_applications_v5_pending_uq
  ON corporation_membership_applications_v5 (corporation_id, house_id) WHERE status = 'PENDING';

CREATE TABLE corporation_invites_v5 (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  target_house_id TEXT REFERENCES houses(id),
  token_hash TEXT NOT NULL UNIQUE,
  issued_by_human_id TEXT NOT NULL REFERENCES humans(id),
  issued_game_day BIGINT NOT NULL CHECK (issued_game_day >= 1),
  expires_game_day BIGINT NOT NULL CHECK (expires_game_day >= issued_game_day),
  max_uses INTEGER NOT NULL DEFAULT 1 CHECK (max_uses > 0),
  uses INTEGER NOT NULL DEFAULT 0 CHECK (uses >= 0 AND uses <= max_uses),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED','EXPIRED','EXHAUSTED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX corporation_invites_v5_lookup_idx ON corporation_invites_v5 (corporation_id, status, expires_game_day);

CREATE TABLE v5_capacity_delinquency_state (
  subject_type TEXT NOT NULL CHECK (subject_type IN ('HOUSE','CORPORATION')),
  subject_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('CURRENT','ARREARS','GRACE','EXPANSION_BLOCKED','PRODUCTIVE_CAPACITY_SUSPENDED','EARTH_RENT_ARREARS','EXPANSION_SPENDING_RESTRICTED','EARTH_RECEIVERSHIP')),
  arrears_since_game_day BIGINT,
  consecutive_missed_days INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_missed_days >= 0),
  last_assessed_game_day BIGINT NOT NULL CHECK (last_assessed_game_day >= 1),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (subject_type, subject_id)
);

CREATE TABLE v5_corporation_founding_policy_versions (
  id TEXT PRIMARY KEY,
  version INTEGER NOT NULL UNIQUE CHECK (version > 0),
  founding_fee_units BIGINT NOT NULL CHECK (founding_fee_units >= 0),
  initial_treasury_reserve_units BIGINT NOT NULL CHECK (initial_treasury_reserve_units >= 0),
  initial_house_base_capacity_rate_units BIGINT NOT NULL CHECK (initial_house_base_capacity_rate_units >= 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE TABLE v5_corporation_founding_commands (
  correlation_id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Map legacy values explicitly before V5 admission commands consume them.
UPDATE corporations SET admission_policy = 'APPROVAL' WHERE upper(admission_policy) IN ('REQUEST','REVIEW','APPLICATION');
UPDATE corporations SET admission_policy = 'INVITE_ONLY' WHERE upper(admission_policy) IN ('INVITE','CLOSED','PRIVATE');

CREATE INDEX progressive_policy_schedule_lookup_idx ON progressive_policy_schedules (code, effective_from_game_day, effective_to_game_day, status);
CREATE INDEX progressive_policy_brackets_schedule_idx ON progressive_policy_brackets (schedule_id, lower_bound_units);
CREATE INDEX corporation_capacity_state_day_idx ON corporation_capacity_state_v5 (game_day, corporation_id);
CREATE INDEX house_capacity_statements_corporation_day_idx ON house_capacity_statements_v5 (corporation_id, game_day, house_id);

CREATE OR REPLACE FUNCTION earth_validate_v5_progressive_schedule(p_schedule_id TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  row_item RECORD;
  previous RECORD;
  count_rows INTEGER := 0;
BEGIN
  FOR row_item IN SELECT * FROM progressive_policy_brackets WHERE schedule_id = p_schedule_id ORDER BY ordinal LOOP
    count_rows := count_rows + 1;
    IF row_item.ordinal <> count_rows THEN RAISE EXCEPTION 'V5 progressive ordinals must be contiguous'; END IF;
    IF count_rows = 1 AND row_item.lower_bound_units <> 0 THEN RAISE EXCEPTION 'V5 progressive schedule must begin at zero'; END IF;
    IF previous IS NOT NULL AND previous.upper_bound_units IS DISTINCT FROM row_item.lower_bound_units THEN RAISE EXCEPTION 'V5 progressive brackets must be contiguous'; END IF;
    IF previous IS NOT NULL AND row_item.marginal_multiplier_numerator::NUMERIC * previous.marginal_multiplier_denominator::NUMERIC < previous.marginal_multiplier_numerator::NUMERIC * row_item.marginal_multiplier_denominator::NUMERIC THEN RAISE EXCEPTION 'V5 progressive multipliers must be non-decreasing'; END IF;
    previous := row_item;
  END LOOP;
  IF count_rows = 0 OR previous.upper_bound_units IS NOT NULL THEN RAISE EXCEPTION 'V5 progressive schedule must have an open-ended final bracket'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_validate_v5_progressive_activation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ACTIVE' THEN
    PERFORM earth_validate_v5_progressive_schedule(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER progressive_policy_schedule_activation_guard
  BEFORE INSERT OR UPDATE OF status ON progressive_policy_schedules
  FOR EACH ROW EXECUTE FUNCTION earth_validate_v5_progressive_activation();

CREATE OR REPLACE FUNCTION earth_guard_v5_active_schedule_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'DELETE' AND (EXISTS (SELECT 1 FROM progressive_policy_schedules WHERE id = NEW.schedule_id AND status = 'ACTIVE') OR (TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM progressive_policy_schedules WHERE id = OLD.schedule_id AND status = 'ACTIVE'))) THEN
    RAISE EXCEPTION 'Active V5 progressive schedules are immutable';
  END IF;
  IF TG_OP = 'DELETE' AND EXISTS (SELECT 1 FROM progressive_policy_schedules WHERE id = OLD.schedule_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Active V5 progressive schedules are immutable';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER progressive_policy_bracket_immutability_guard
  BEFORE INSERT OR UPDATE OR DELETE ON progressive_policy_brackets
  FOR EACH ROW EXECUTE FUNCTION earth_guard_v5_active_schedule_mutation();

CREATE OR REPLACE FUNCTION earth_guard_v5_active_schedule_header_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'ACTIVE' AND (
    NEW.code IS DISTINCT FROM OLD.code OR NEW.basis_type IS DISTINCT FROM OLD.basis_type OR
    NEW.authority_institution_id IS DISTINCT FROM OLD.authority_institution_id OR NEW.version IS DISTINCT FROM OLD.version OR
    NEW.effective_from_game_day IS DISTINCT FROM OLD.effective_from_game_day OR NEW.effective_to_game_day IS DISTINCT FROM OLD.effective_to_game_day
  ) THEN RAISE EXCEPTION 'Active V5 progressive schedules are immutable'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER progressive_policy_schedule_immutability_guard
  BEFORE UPDATE ON progressive_policy_schedules
  FOR EACH ROW EXECUTE FUNCTION earth_guard_v5_active_schedule_header_mutation();

-- Active effective-dated authorities must be unambiguous. Drafts may overlap
-- while policy authors prepare a future rollout, but activation cannot create
-- two competing rules for the same authority and interval.
CREATE OR REPLACE FUNCTION earth_guard_v5_policy_overlap()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ACTIVE' AND EXISTS (
    SELECT 1 FROM progressive_policy_schedules s
     WHERE s.status = 'ACTIVE' AND s.id <> NEW.id
       AND s.code = NEW.code AND s.authority_institution_id = NEW.authority_institution_id
       AND s.effective_from_game_day <= COALESCE(NEW.effective_to_game_day, 9223372036854775807)
       AND NEW.effective_from_game_day <= COALESCE(s.effective_to_game_day, 9223372036854775807)
  ) THEN RAISE EXCEPTION 'Overlapping active V5 progressive policy schedule'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER progressive_policy_schedule_overlap_guard
  BEFORE INSERT OR UPDATE OF status, code, authority_institution_id, effective_from_game_day, effective_to_game_day ON progressive_policy_schedules
  FOR EACH ROW EXECUTE FUNCTION earth_guard_v5_policy_overlap();

CREATE OR REPLACE FUNCTION earth_guard_v5_capacity_policy_overlap()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ACTIVE' AND EXISTS (
    SELECT 1 FROM v5_capacity_policy_versions p
     WHERE p.status = 'ACTIVE' AND p.id <> NEW.id
       AND p.effective_from_game_day <= COALESCE(NEW.effective_to_game_day, 9223372036854775807)
       AND NEW.effective_from_game_day <= COALESCE(p.effective_to_game_day, 9223372036854775807)
  ) THEN RAISE EXCEPTION 'Overlapping active V5 capacity policy'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER v5_capacity_policy_overlap_guard
  BEFORE INSERT OR UPDATE OF status, effective_from_game_day, effective_to_game_day ON v5_capacity_policy_versions
  FOR EACH ROW EXECUTE FUNCTION earth_guard_v5_capacity_policy_overlap();

CREATE OR REPLACE FUNCTION earth_guard_v5_corporation_policy_overlap()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ACTIVE' AND EXISTS (
    SELECT 1 FROM corporation_capacity_policy_versions p
     WHERE p.status = 'ACTIVE' AND p.id <> NEW.id AND p.corporation_id = NEW.corporation_id
       AND p.effective_from_game_day <= COALESCE(NEW.effective_to_game_day, 9223372036854775807)
       AND NEW.effective_from_game_day <= COALESCE(p.effective_to_game_day, 9223372036854775807)
  ) THEN RAISE EXCEPTION 'Overlapping active Corporation capacity policy'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER corporation_capacity_policy_overlap_guard
  BEFORE INSERT OR UPDATE OF status, corporation_id, effective_from_game_day, effective_to_game_day ON corporation_capacity_policy_versions
  FOR EACH ROW EXECUTE FUNCTION earth_guard_v5_corporation_policy_overlap();
