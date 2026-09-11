-- Cities, Corporations & Budgets V2 Plan 20.
-- Budget authority funds real service providers; it does not create capacity.

CREATE TABLE public_service_projects (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  city_id TEXT NOT NULL REFERENCES cities(id),
  provider_building_id TEXT NOT NULL REFERENCES buildings(id),
  service_type TEXT NOT NULL CHECK (service_type IN ('HOUSING', 'ENERGY', 'CONNECTIVITY', 'HEALTH')),
  budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  commitment_id BIGINT REFERENCES institution_budget_commitments(id),
  recipient_account_id BIGINT REFERENCES economic_accounts(id),
  authorized_units BIGINT NOT NULL DEFAULT 0 CHECK (authorized_units >= 0),
  funded_units BIGINT NOT NULL DEFAULT 0 CHECK (funded_units >= 0 AND funded_units <= authorized_units),
  status TEXT NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED', 'APPROVED', 'ACTIVE', 'COMPLETED', 'CANCELLED')),
  rule_version TEXT NOT NULL,
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 0),
  completed_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (provider_building_id, service_type, budget_line_id)
);
CREATE INDEX public_service_projects_city_day_idx ON public_service_projects (city_id, status, created_game_day);

CREATE OR REPLACE FUNCTION earth_create_public_service_project(
  p_id TEXT,
  p_institution_id TEXT,
  p_provider_building_id TEXT,
  p_service_type TEXT,
  p_budget_line_id BIGINT,
  p_authorized_units BIGINT,
  p_rule_version TEXT,
  p_created_game_day BIGINT
)
RETURNS public_service_projects
LANGUAGE plpgsql
AS $$
DECLARE
  v_project public_service_projects;
  v_city_id TEXT;
  v_catalog_service_type TEXT;
  v_catalog_mode TEXT;
  v_category_code TEXT;
BEGIN
  IF p_authorized_units < 0 OR NULLIF(p_rule_version, '') IS NULL THEN
    RAISE EXCEPTION 'Invalid public service project terms';
  END IF;
  SELECT c.id INTO v_city_id
    FROM cities c
   WHERE c.id = p_institution_id AND c.institution_id = p_institution_id;
  IF v_city_id IS NULL THEN RAISE EXCEPTION 'Institution % is not a city', p_institution_id; END IF;

  SELECT b.city_id, upper(cat.service_type), upper(cat.service_mode)
    INTO v_city_id, v_catalog_service_type, v_catalog_mode
    FROM buildings b
    JOIN building_catalog cat ON cat.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
   WHERE b.id = p_provider_building_id AND b.city_id = p_institution_id;
  IF v_city_id IS NULL OR v_catalog_service_type <> upper(p_service_type) OR v_catalog_mode <> 'PUBLIC_CONTRACT' THEN
    RAISE EXCEPTION 'Building % is not a matching public service provider', p_provider_building_id;
  END IF;

  SELECT bc.category_code INTO v_category_code
    FROM institution_budget_lines l JOIN budget_categories bc ON bc.id = l.category_id
   WHERE l.id = p_budget_line_id AND l.institution_id = p_institution_id
   FOR UPDATE;
  IF v_category_code IS NULL OR (upper(p_service_type) = 'HEALTH' AND v_category_code NOT IN ('HEALTH', 'ESSENTIAL_SERVICES')) OR (upper(p_service_type) <> 'HEALTH' AND v_category_code <> upper(p_service_type)) THEN
    RAISE EXCEPTION 'Budget line % is not eligible for % service', p_budget_line_id, p_service_type;
  END IF;

  INSERT INTO public_service_projects (id, institution_id, city_id, provider_building_id, service_type, budget_line_id, authorized_units, rule_version, created_game_day)
  VALUES (p_id, p_institution_id, p_institution_id, p_provider_building_id, upper(p_service_type), p_budget_line_id, p_authorized_units, p_rule_version, p_created_game_day)
  RETURNING * INTO v_project;
  RETURN v_project;
END;
$$;

COMMENT ON TABLE public_service_projects IS
  'A budget-funded contract with a real Building V2 service provider; project funding does not itself create service capacity.';
