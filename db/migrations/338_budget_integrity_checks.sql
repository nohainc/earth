-- Cities, Corporations & Budgets V2 Plan 34.
-- Extend the existing integrity report; do not create a second diagnostic system.

CREATE OR REPLACE FUNCTION earth_reject_receivership_discretionary_commitment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_spending_class TEXT;
BEGIN
  SELECT fs.status, bc.spending_class INTO v_status, v_spending_class
  FROM institution_budget_lines l
  JOIN budget_categories bc ON bc.id = l.category_id
  LEFT JOIN financial_states fs ON fs.institution_id = l.institution_id
  WHERE l.id = NEW.budget_line_id;
  IF lower(COALESCE(v_status, '')) = 'receivership' AND v_spending_class = 'DISCRETIONARY' THEN
    RAISE EXCEPTION 'Receivership City cannot create discretionary budget commitments';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS institution_budget_commitments_receivership_trigger ON institution_budget_commitments;
CREATE TRIGGER institution_budget_commitments_receivership_trigger
BEFORE INSERT ON institution_budget_commitments
FOR EACH ROW EXECUTE FUNCTION earth_reject_receivership_discretionary_commitment();

ALTER FUNCTION earth_integrity_report() RENAME TO earth_integrity_report_base;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT * FROM earth_integrity_report_base();
  RETURN QUERY
    SELECT 'budget_authority_exceeded', COUNT(*) FROM institution_budget_lines
     WHERE authorized_units < committed_units + spent_units;
  RETURN QUERY
    SELECT 'negative_budget_units', COUNT(*) FROM institution_budget_lines
     WHERE authorized_units < 0 OR committed_units < 0 OR spent_units < 0
    UNION ALL SELECT 'negative_commitment_remaining', COUNT(*) FROM institution_budget_commitments WHERE remaining_units < 0
    UNION ALL SELECT 'commitment_remaining_exceeds_original', COUNT(*) FROM institution_budget_commitments WHERE remaining_units > original_units
    UNION ALL SELECT 'commitment_payment_exceeds_original', COUNT(*) FROM institution_budget_commitments WHERE original_units - remaining_units > original_units
    UNION ALL SELECT 'spending_event_without_economic_transaction', COUNT(*) FROM institution_financial_events WHERE event_type = 'SPENDING' AND economic_transaction_id IS NULL
    UNION ALL SELECT 'spending_event_without_budget_category', COUNT(*) FROM institution_financial_events e LEFT JOIN institution_budget_lines l ON l.id = e.budget_line_id WHERE e.event_type = 'SPENDING' AND (e.budget_line_id IS NULL OR l.id IS NULL)
    UNION ALL SELECT 'institution_spending_without_financial_event', COUNT(*) FROM institution_spending_journals j LEFT JOIN institution_financial_events e ON e.institution_id = j.institution_id AND e.event_type = 'SPENDING' AND e.economic_transaction_id = j.economic_transaction_id WHERE e.id IS NULL
    UNION ALL SELECT 'institution_transaction_without_financial_event', COUNT(*) FROM economic_transactions t LEFT JOIN institution_financial_events e ON e.economic_transaction_id = t.id WHERE t.rules_version = 'institution-budget-v2' AND e.id IS NULL
    UNION ALL SELECT 'grant_received_counted_as_spending', COUNT(*) FROM institution_financial_events e JOIN institution_spending_journals j ON j.institution_id = e.institution_id AND j.economic_transaction_id = e.economic_transaction_id WHERE e.event_type = 'GRANT_RECEIVED'
    UNION ALL SELECT 'dissolved_corporation_active_commitment', COUNT(*) FROM institution_budget_commitments c JOIN institutions i ON i.id = c.institution_id WHERE i.kind = 'CORPORATION' AND i.status = 'dissolved' AND c.status IN ('ACTIVE','PARTIALLY_PAID')
    UNION ALL SELECT 'receivership_discretionary_commitment', COUNT(*) FROM institution_budget_commitments c JOIN institution_budget_lines l ON l.id = c.budget_line_id JOIN budget_categories bc ON bc.id = l.category_id JOIN institutions i ON i.id = c.institution_id JOIN financial_states fs ON fs.institution_id = i.id WHERE i.kind = 'CITY' AND lower(fs.status) = 'receivership' AND bc.spending_class = 'DISCRETIONARY' AND c.status IN ('ACTIVE','PARTIALLY_PAID')
    UNION ALL SELECT 'reserve_transfer_unbalanced', COUNT(*) FROM (SELECT t.id FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id JOIN economic_accounts a ON a.id = e.account_id WHERE t.transaction_kind = 'RESERVE_TRANSFER' GROUP BY t.id HAVING COUNT(*) < 2 OR SUM(e.delta) <> 0) x;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cities' AND column_name = 'treasury') THEN
    RETURN QUERY EXECUTE $q$
      SELECT 'city_scalar_treasury_mismatch', COUNT(*)::BIGINT
      FROM cities c JOIN owner_registry o ON o.id = c.id
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'
      WHERE c.treasury::NUMERIC <> a.balance::NUMERIC / 100$q$;
  ELSE
    RETURN QUERY SELECT 'city_scalar_treasury_mismatch', 0::BIGINT;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'corporations' AND column_name = 'treasury') THEN
    RETURN QUERY EXECUTE $q$
      SELECT 'corporation_scalar_treasury_mismatch', COUNT(*)::BIGINT
      FROM corporations c JOIN owner_registry o ON o.id = c.id
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'
      WHERE c.treasury::NUMERIC <> a.balance::NUMERIC / 100$q$;
  ELSE
    RETURN QUERY SELECT 'corporation_scalar_treasury_mismatch', 0::BIGINT;
  END IF;
END;
$$;
