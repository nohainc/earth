-- EARTH ACTIVE MIGRATION: V4-backed compatibility projections for finance reads

-- These projections keep the existing finance API readable while the write and
-- settlement paths use the V4 snapshot and organization state models.
CREATE OR REPLACE VIEW financial_states AS
SELECT s.institution_id,
       i.kind AS institution_kind,
       COALESCE(s.financial_state, 'HEALTHY') AS status,
       s.game_day AS evaluated_game_day,
       s.cash_treasury_units,
       s.cash_operations_units,
       s.cash_reserve_units,
       s.period_revenue_units,
       s.period_spending_units,
       s.budget_authorized_units,
       s.budget_committed_units,
       s.budget_spent_units,
       s.tax_receivable_units,
       s.arrears_units,
       s.rules_version,
       s.created_at,
       s.updated_at
  FROM institution_financial_snapshots s
  JOIN institutions i ON i.id = s.institution_id
 WHERE (s.institution_id, s.game_day) IN (
   SELECT institution_id, MAX(game_day)
     FROM institution_financial_snapshots
    GROUP BY institution_id
 );

CREATE OR REPLACE VIEW bankruptcy_events AS
SELECT c.id,
       c.organization_id,
       c.case_type AS event_type,
       c.status,
       c.opened_game_day AS game_day,
       c.effective_game_day,
       c.approved_proposal_id,
       c.correlation_id,
       c.details,
       c.opened_game_day AS created_at
  FROM organization_resolution_cases c;
