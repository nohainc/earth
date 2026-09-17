import type { PostgresRepository } from './repository.ts';

type CorporationTaxRow = {
  id: string;
  economic_id: string;
  corporate_tax_bps: number;
  tax_rule_version: string;
};

// @mutation-boundary caller-owned-transaction: invoked by the daily settlement transaction.
/** Assess and collect the Corporation's own income tax from its realized V4 operating result. */
export async function settleCorporationIncomeTax(
  tx: PostgresRepository,
  day: number,
): Promise<Record<string, unknown>> {
  const assessedDay = day - 1;
  if (assessedDay < 1) return { ok: true, day, assessedDay, assessed: 0, paid: 0, arrears: 0 };

  const corporations = (await tx.query<CorporationTaxRow>(`
    SELECT c.id, oe.economic_id,
           COALESCE((snap.rules_json->>'CORPORATION.TAX.CORPORATE_RATE')::INTEGER, (c.tax_charter->>'corporateTaxBps')::INTEGER, 0) AS corporate_tax_bps,
           COALESCE(snap.version_ids->>'CORPORATION.TAX.CORPORATE_RATE', 'legacy-corporation-tax-v' || c.tax_charter_version::TEXT) AS tax_rule_version
      FROM corporations c
      JOIN owner_registry oe ON oe.id = c.id AND oe.owner_type = 'CORPORATION'
     LEFT JOIN resolved_constitution_snapshots_v5 snap ON snap.authority_type = 'CORPORATION' AND snap.authority_id = c.id AND snap.game_day = $1
     WHERE c.status = 'ACTIVE'
       AND COALESCE((snap.rules_json->>'CORPORATION.TAX.CORPORATE_RATE')::INTEGER, (c.tax_charter->>'corporateTaxBps')::INTEGER, 0) > 0
     ORDER BY c.id
  `, [assessedDay])).rows;
  let assessed = 0;
  let paid = 0;
  let arrears = 0;

  for (const corporation of corporations) {
    const snapshot = (await tx.query<{ service_revenue_units: string; operating_cost_units: string }>(`
      SELECT service_revenue_units::TEXT, operating_cost_units::TEXT
        FROM corporation_operating_snapshots
       WHERE corporation_id = $1 AND game_day = $2
    `, [corporation.id, assessedDay])).rows[0];
    const revenue = BigInt(snapshot?.service_revenue_units ?? '0');
    const cost = BigInt(snapshot?.operating_cost_units ?? '0');
    const taxableProfit = revenue > cost ? revenue - cost : 0n;
    const amount = taxableProfit * BigInt(corporation.corporate_tax_bps) / 10_000n;
    if (amount <= 0n) continue;

    const correlationId = `corporation-tax:${corporation.id}:${assessedDay}:${corporation.tax_rule_version}`;
    const existing = (await tx.query<{ status: string }>(
      'SELECT status FROM financial_obligations WHERE correlation_id = $1', [correlationId],
    )).rows[0];
    if (existing) {
      assessed += 1;
      if (existing.status === 'PAID') paid += 1;
      else if (existing.status === 'ARREARS') arrears += 1;
      continue;
    }

    const obligationId = `CORP-TAX-${corporation.id}-${assessedDay}-${corporation.tax_rule_version}`;
    const earthAccount = (await tx.query<{ id: string }>(`
      SELECT a.id::TEXT AS id
        FROM economic_accounts a
        JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE o.id = 'EARTH' AND o.owner_type = 'EARTH'
         AND a.asset_id = 1 AND a.account_type IN ('OPERATIONS', 'TREASURY') AND a.status = 'ACTIVE'
       ORDER BY CASE a.account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END LIMIT 1
    `)).rows[0];
    const corporationAccount = (await tx.query<{ id: string; balance_units: string }>(`
      SELECT a.id::TEXT AS id, a.balance_units::TEXT
        FROM economic_accounts a
       WHERE a.owner_economic_id = $1 AND a.asset_id = 1
         AND a.account_type IN ('OPERATIONS', 'TREASURY') AND a.status = 'ACTIVE'
       ORDER BY CASE a.account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END LIMIT 1 FOR UPDATE
    `, [corporation.economic_id])).rows[0];
    if (!earthAccount || !corporationAccount) throw new Error(`Tax accounts are unavailable for Corporation ${corporation.id}`);

    await tx.query(`
      INSERT INTO financial_obligations
        (id, debtor_economic_id, creditor_economic_id, obligation_type, source_id,
         principal_due_units, due_game_day, priority_class, rule_version, status,
         created_game_day, nexus_type, authority_type, authority_id, base_reference, correlation_id)
      VALUES ($1,$2,'ECON-EARTH-001','TAX',$3,$4,$5,10,$8,'DUE',$6,
              'EARTH','EARTH','EARTH','positive_realized_daily_taxable_profit',$7)
    `, [obligationId, corporation.economic_id, corporation.id, amount.toString(), day, day, correlationId, corporation.tax_rule_version]);
    await tx.query(`
      INSERT INTO tax_obligations
        (id, taxpayer_economic_id, beneficiary_economic_id, tax_type, tax_base_units,
         amount_units, rule_version, game_day, status, due_game_day, nexus_type,
         authority_type, authority_id, base_reference, correlation_id)
      VALUES ($1,$2,'ECON-EARTH-001','corporate_income',$3,$4,$8,$5,'DUE',$6,
              'EARTH','EARTH','EARTH','positive_realized_daily_taxable_profit',$7)
      ON CONFLICT (correlation_id) DO NOTHING
    `, [obligationId, corporation.economic_id, taxableProfit.toString(), amount.toString(), assessedDay, day, correlationId, corporation.tax_rule_version]);

    const balance = BigInt(corporationAccount.balance_units);
    if (balance < amount) {
      await tx.query("UPDATE financial_obligations SET status = 'ARREARS', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [obligationId]);
      await tx.query("UPDATE tax_obligations SET status = 'ARREARS' WHERE id = $1", [obligationId]);
      arrears += 1;
    } else {
      const posted = (await tx.query<{ transaction_id: string }>(`
        SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','TAX_COLLECTION',$3,$4,$5::JSONB) AS transaction_id
      `, [`corporation-tax-payment:${correlationId}`, day, corporation.id, corporation.tax_rule_version, JSON.stringify([
        { account_id: corporationAccount.id, asset_id: 1, delta_units: (-amount).toString() },
        { account_id: earthAccount.id, asset_id: 1, delta_units: amount.toString() },
      ])])).rows[0];
      await tx.query("UPDATE financial_obligations SET paid_units = principal_due_units, status = 'PAID', payment_transaction_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1", [obligationId, posted.transaction_id]);
      await tx.query("UPDATE tax_obligations SET status = 'PAID', payment_transaction_id = $2 WHERE id = $1", [obligationId, posted.transaction_id]);
      paid += 1;
    }
    assessed += 1;
  }
  return { ok: true, day, assessedDay, assessed, paid, arrears };
}
