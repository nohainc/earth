-- Migration 019: Drop obsolete JSONB columns in favor of typed columns and relational sub-tables

-- 1. institution_roles: drop authority_json (replaced by can_propose, can_vote, can_manage_budget, can_manage_treasury, can_appoint_manager)
alter table institution_roles
  drop column if exists authority_json;

-- 2. governance_rules: drop value_json (replaced by quorum_threshold, approval_threshold, voting_period_days)
alter table governance_rules
  drop column if exists value_json;

-- 3. technologies: drop metadata (replaced by required_compute, cost_credits, technology_prerequisites)
alter table technologies
  drop column if exists metadata;

-- 4. negotiated_contracts: drop terms_json (replaced by merger_contracts sub-table)
alter table negotiated_contracts
  drop column if exists terms_json;

-- 5. assets: drop metadata (replaced by typed machines table)
alter table assets
  drop column if exists metadata;
