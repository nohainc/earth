-- Finance V2 Plan 24: named invariants for monetary, banking and insolvency data.

CREATE OR REPLACE FUNCTION earth_finance_v2_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'net_issued_credit_balance_mismatch', CASE WHEN EXISTS (
    SELECT 1 FROM monetary_supply_snapshots s
    WHERE s.game_day = (SELECT MAX(game_day) FROM monetary_supply_snapshots)
      AND s.issued_total_units - s.retired_total_units <> s.circulating_units
  ) THEN 1 ELSE 0 END
  UNION ALL SELECT 'city_treasury_projection_mismatch', COUNT(*) FROM institution_financial_summary s JOIN institutions i ON i.id = s.institution_id JOIN owner_registry o ON o.id = i.id LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.status = 'active' WHERE i.kind = 'CITY' GROUP BY s.institution_id, s.treasury_units HAVING s.treasury_units <> COALESCE(SUM(a.balance),0)
  UNION ALL SELECT 'corporation_treasury_projection_mismatch', COUNT(*) FROM institution_financial_summary s JOIN institutions i ON i.id = s.institution_id JOIN owner_registry o ON o.id = i.id LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.status = 'active' WHERE i.kind = 'CORPORATION' GROUP BY s.institution_id, s.treasury_units HAVING s.treasury_units <> COALESCE(SUM(a.balance),0)
  UNION ALL SELECT 'deposit_liability_mismatch', CASE WHEN EXISTS (SELECT 1 FROM global_bank_balance_sheet b WHERE b.game_day = (SELECT MAX(game_day) FROM global_bank_balance_sheet) AND (b.deposit_principal_units + b.deposit_interest_payable_units) <> (SELECT COALESCE(SUM(principal_units + accrued_interest_units),0) FROM bank_deposits WHERE status IN ('ACTIVE','MATURED'))) THEN 1 ELSE 0 END
  UNION ALL SELECT 'negative_loan_principal', COUNT(*) FROM bank_loans WHERE outstanding_principal_units < 0
  UNION ALL SELECT 'matured_deposit_still_active', COUNT(*) FROM bank_deposits d CROSS JOIN world_state w WHERE d.status = 'ACTIVE' AND d.maturity_total_game_minute <= (w.game_day - 1) * 1440 + w.game_minute
  UNION ALL SELECT 'repaid_loan_with_balance', COUNT(*) FROM bank_loans WHERE status = 'REPAID' AND outstanding_principal_units <> 0
  UNION ALL SELECT 'bank_equity_mismatch', COUNT(*) FROM global_bank_balance_sheet WHERE equity_units <> assets_units - liabilities_units
  UNION ALL SELECT 'dividend_exceeds_projection', COUNT(*) FROM civic_dividend_payouts p JOIN institution_financial_summary s ON s.institution_id = p.city_id AND s.game_day = p.day WHERE p.distributable_units > s.distributable_surplus_units
  UNION ALL SELECT 'paid_tax_without_transaction', COUNT(*) FROM tax_obligations WHERE status = 'PAID' AND payment_transaction_id IS NULL
  UNION ALL SELECT 'bankruptcy_distribution_exceeds_estate', COUNT(*) FROM (SELECT c.proceeding_id FROM bankruptcy_claims c JOIN bankruptcy_proceedings p ON p.id = c.proceeding_id GROUP BY c.proceeding_id, p.estate_value_units HAVING COALESCE(SUM(c.paid_units),0) > p.estate_value_units) d
  UNION ALL SELECT 'issuance_missing_authority_metadata', COUNT(*) FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id JOIN economic_accounts a ON a.id = e.account_id JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = 'SYSTEM-MONETARY-AUTHORITY' AND (t.rules_version IS NULL OR t.source_type IS NULL OR t.game_day IS NULL OR t.correlation_id IS NULL OR e.reason_code NOT IN ('GENESIS_ISSUANCE','PLAYER_STARTING_GRANT','MONETARY_STABILIZATION'))
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT check_name, invalid_count FROM earth_base_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_market_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_monetary_supply_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_finance_v2_integrity()
$$;
