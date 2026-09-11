-- Cities, Corporations & Budgets V2 Plan 22.
-- Institutional permissions are explicit governance records, not administrator
-- columns masquerading as roles.

CREATE TABLE institution_governance_roles (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  role_code TEXT NOT NULL CHECK (role_code IN ('CITY_MAYOR', 'INFRASTRUCTURE_PLANNER', 'CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER', 'RECEIVERSHIP_RECEIVER')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED', 'REVOKED')),
  source_type TEXT NOT NULL DEFAULT 'CHARTER' CHECK (source_type IN ('CHARTER', 'PROPOSAL', 'EMERGENCY')),
  source_id TEXT,
  effective_from_game_day BIGINT NOT NULL DEFAULT 0,
  effective_to_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (institution_id, human_id, role_code, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX institution_governance_roles_active_idx ON institution_governance_roles (institution_id, human_id, role_code) WHERE status = 'ACTIVE';

INSERT INTO institution_governance_roles (institution_id, human_id, role_code, source_type, source_id)
SELECT i.id, i.administrator_human_id,
       CASE WHEN i.kind = 'CITY' THEN 'CITY_MAYOR' ELSE 'CORPORATION_EXECUTIVE' END,
       'CHARTER', 'legacy-administrator-bootstrap'
  FROM institutions i
 WHERE i.kind IN ('CITY', 'CORPORATION') AND i.administrator_human_id IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION earth_can_perform_institution_action(
  p_human_id TEXT,
  p_institution_id TEXT,
  p_action TEXT,
  p_game_day BIGINT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_day BIGINT := COALESCE(p_game_day, (SELECT game_day FROM world_state WHERE id = 'WORLD'), 0);
BEGIN
  RETURN EXISTS (
    SELECT 1
      FROM institution_governance_roles r
      JOIN humans h ON h.id = r.human_id AND h.life_status = 'active' AND h.account_status = 'active'
      JOIN institutions i ON i.id = r.institution_id AND i.status = 'active'
     WHERE r.human_id = p_human_id AND r.institution_id = p_institution_id
       AND r.status = 'ACTIVE'
       AND r.effective_from_game_day <= v_day
       AND (r.effective_to_game_day IS NULL OR r.effective_to_game_day >= v_day)
       AND r.role_code = ANY (CASE upper(p_action)
         WHEN 'SET_BUDGET' THEN ARRAY['CITY_MAYOR','INFRASTRUCTURE_PLANNER','CORPORATION_EXECUTIVE']
         WHEN 'CREATE_COMMITMENT' THEN ARRAY['CITY_MAYOR','INFRASTRUCTURE_PLANNER','CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         WHEN 'APPROVE_SPENDING' THEN ARRAY['CITY_MAYOR','INFRASTRUCTURE_PLANNER','CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         WHEN 'TRANSFER_TO_RESERVE' THEN ARRAY['CITY_MAYOR','CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         WHEN 'AUTHORIZE_GRANT' THEN ARRAY['CITY_MAYOR','CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         WHEN 'CHANGE_TAX_RULE' THEN ARRAY['CITY_MAYOR','INFRASTRUCTURE_PLANNER','CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         WHEN 'DECLARE_DIVIDEND' THEN ARRAY['CORPORATION_EXECUTIVE','CORPORATION_TREASURER']
         ELSE ARRAY[]::TEXT[] END)
  ) OR (upper(p_action) IN ('APPROVE_SPENDING','TRANSFER_TO_RESERVE') AND EXISTS (
    SELECT 1 FROM institution_governance_roles r
     WHERE r.institution_id = p_institution_id AND r.human_id = p_human_id
       AND r.role_code = 'RECEIVERSHIP_RECEIVER' AND r.status = 'ACTIVE'
  ));
END;
$$;
