-- EARTH ACTIVE MIGRATION: copy the local-only Program/Project data into the
-- canonical Initiative lifecycle. The old tables remain readable for rollback
-- diagnostics, but no new player path writes to them.

INSERT INTO v5_governance_proposals
  (id, subject_type, subject_id, action_type, payload, title, body, status,
   submitted_game_day, voting_start_game_day, voting_end_game_day,
   effective_from_game_day, created_by_human_id, correlation_id, policy_group)
SELECT
  'MIGRATED-INIT-PROGRAM-' || g.id,
  'EARTH', NULL, 'INITIATIVE_CREATE',
  jsonb_build_object(
    'initiativeType', 'PROGRAM',
    'programType', g.program_type,
    'name', g.name,
    'initiativeDescription', g.description,
    'fundingTargetUnits', g.target_units::TEXT,
    'treasuryAuthorizedUnits', g.authorized_units::TEXT,
    'matchingPolicy', CASE WHEN g.matching_authorized_units > 0 THEN 'BREADTH_MATCH' ELSE 'NONE' END,
    'matchingCapUnits', g.matching_authorized_units::TEXT,
    'fundingDeadlineGameDay', g.funding_deadline_game_day,
    'fundingModel', CASE WHEN g.authorized_units > 0 THEN 'MIXED' ELSE 'CROWDFUND' END,
    'executionModel', 'TIMED_PROGRAM',
    'executionDurationGameDays', 30,
    'progressModel', 'TIME',
    'outcome', jsonb_build_object('type', 'LEGACY_PROGRAM_OUTPUT')
  ),
  g.name, g.description, 'ACTIVATED',
  GREATEST(g.created_game_day - 1, 1), GREATEST(g.created_game_day, 2), GREATEST(g.created_game_day, 2),
  GREATEST(g.created_game_day, 2), (SELECT id FROM humans WHERE status = 'ACTIVE' ORDER BY id LIMIT 1),
  'migrate:initiative:program:' || g.id, 'EARTH:INITIATIVE:MIGRATED'
FROM global_programs g
WHERE NOT EXISTS (SELECT 1 FROM v5_governance_proposals p WHERE p.id = 'MIGRATED-INIT-PROGRAM-' || g.id);

INSERT INTO v5_governance_proposals
  (id, subject_type, subject_id, action_type, payload, title, body, status,
   submitted_game_day, voting_start_game_day, voting_end_game_day,
   effective_from_game_day, created_by_human_id, correlation_id, policy_group)
SELECT
  'MIGRATED-INIT-PROJECT-' || p.id,
  'EARTH', NULL, 'INITIATIVE_CREATE',
  jsonb_build_object(
    'initiativeType', 'PUBLIC_PROJECT',
    'name', p.name,
    'initiativeDescription', p.description,
    'fundingTargetUnits', p.target_units::TEXT,
    'treasuryAuthorizedUnits', '0',
    'matchingPolicy', CASE WHEN p.matching_pool_authorized_units > 0 THEN 'BREADTH_MATCH' ELSE 'NONE' END,
    'matchingCapUnits', p.matching_pool_authorized_units::TEXT,
    'fundingDeadlineGameDay', p.deadline_game_day,
    'fundingModel', 'MATCHED',
    'executionModel', 'PUBLIC_WORK',
    'progressModel', 'FUNDING_ONLY',
    'outcome', jsonb_build_object('type', 'LEGACY_PUBLIC_PROJECT_OUTPUT')
  ),
  p.name, p.description, 'ACTIVATED',
  GREATEST(p.created_game_day - 1, 1), GREATEST(p.created_game_day, 2), GREATEST(p.created_game_day, 2),
  GREATEST(p.created_game_day, 2), p.created_by_human_id,
  'migrate:initiative:project:' || p.id, 'EARTH:INITIATIVE:MIGRATED'
FROM public_projects p
WHERE NOT EXISTS (SELECT 1 FROM v5_governance_proposals v WHERE v.id = 'MIGRATED-INIT-PROJECT-' || p.id);

INSERT INTO v5_initiatives
  (id, scope_type, scope_id, initiative_type, name, description, program_type,
   funding_target_units, treasury_authorized_units, matching_policy, matching_cap_units,
   funding_deadline_game_day, funding_model, execution_model, outcome,
   governance_proposal_id, status, effective_game_day, created_game_day)
SELECT
  'MIGRATED-INIT-PROGRAM-' || g.id, 'EARTH', NULL, 'PROGRAM', g.name, g.description, g.program_type,
  g.target_units, g.authorized_units,
  CASE WHEN g.matching_authorized_units > 0 THEN 'BREADTH_MATCH' ELSE 'NONE' END,
  g.matching_authorized_units, g.funding_deadline_game_day,
  CASE WHEN g.authorized_units > 0 THEN 'MIXED' ELSE 'CROWDFUND' END, 'TIMED_PROGRAM',
  jsonb_build_object('type', 'LEGACY_PROGRAM_OUTPUT'), 'MIGRATED-INIT-PROGRAM-' || g.id,
  CASE WHEN g.status = 'COMPLETED' THEN 'COMPLETED' WHEN g.status = 'CANCELLED' THEN 'CANCELLED' ELSE 'FUNDING' END,
  GREATEST(g.created_game_day, 2), GREATEST(g.created_game_day, 2)
FROM global_programs g
ON CONFLICT (id) DO NOTHING;

INSERT INTO v5_initiatives
  (id, scope_type, scope_id, initiative_type, name, description, program_type,
   funding_target_units, treasury_authorized_units, matching_policy, matching_cap_units,
   funding_deadline_game_day, funding_model, execution_model, outcome,
   governance_proposal_id, status, effective_game_day, created_game_day)
SELECT
  'MIGRATED-INIT-PROJECT-' || p.id, 'EARTH', NULL, 'PUBLIC_PROJECT', p.name, p.description, NULL,
  p.target_units, 0,
  CASE WHEN p.matching_pool_authorized_units > 0 THEN 'BREADTH_MATCH' ELSE 'NONE' END,
  p.matching_pool_authorized_units, p.deadline_game_day, 'MATCHED', 'PUBLIC_WORK',
  jsonb_build_object('type', 'LEGACY_PUBLIC_PROJECT_OUTPUT'), 'MIGRATED-INIT-PROJECT-' || p.id,
  CASE WHEN p.status IN ('SETTLED') THEN 'COMPLETED' WHEN p.status IN ('FAILED','CANCELLED') THEN 'FAILED' ELSE 'FUNDING' END,
  GREATEST(p.created_game_day, 2), GREATEST(p.created_game_day, 2)
FROM public_projects p
ON CONFLICT (id) DO NOTHING;

INSERT INTO initiative_contributions
  (id, initiative_id, house_id, amount_units, matching_units, escrow_account_id,
   contribution_transaction_id, status, created_game_day, settled_game_day, correlation_id)
SELECT
  'MIGRATED-CONTRIB-PROGRAM-' || c.id,
  'MIGRATED-INIT-PROGRAM-' || c.program_id,
  c.house_id, c.amount_units, c.matching_units, NULL, c.transaction_id,
  CASE c.status WHEN 'ESCROWED' THEN 'ESCROWED' WHEN 'APPLIED' THEN 'APPLIED' WHEN 'REFUNDED' THEN 'REFUNDED' ELSE 'CANCELLED' END,
  GREATEST(c.game_day, 1), c.refunded_game_day, 'migrate:contribution:program:' || c.id
FROM global_program_contributions c
WHERE EXISTS (SELECT 1 FROM v5_initiatives i WHERE i.id = 'MIGRATED-INIT-PROGRAM-' || c.program_id)
ON CONFLICT (correlation_id) DO NOTHING;

INSERT INTO initiative_contributions
  (id, initiative_id, house_id, amount_units, matching_units, escrow_account_id,
   contribution_transaction_id, status, created_game_day, correlation_id)
SELECT
  'MIGRATED-CONTRIB-PROJECT-' || c.id,
  'MIGRATED-INIT-PROJECT-' || c.project_id,
  c.house_id, c.amount_units, 0, c.escrow_account_id, c.contribution_transaction_id,
  CASE c.status WHEN 'ESCROWED' THEN 'ESCROWED' WHEN 'RELEASED' THEN 'RELEASED' WHEN 'REFUNDED' THEN 'REFUNDED' ELSE 'CANCELLED' END,
  GREATEST(c.created_game_day, 1), 'migrate:contribution:project:' || c.id
FROM public_project_contributions c
WHERE EXISTS (SELECT 1 FROM v5_initiatives i WHERE i.id = 'MIGRATED-INIT-PROJECT-' || c.project_id)
ON CONFLICT (correlation_id) DO NOTHING;
