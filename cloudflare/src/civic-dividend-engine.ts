import type { PostgresRepository } from './repository.ts';
import { centsToMoney, moneyToCents } from './money.ts';

type Resident = { human_id: string; economic_id: string; account_id: string; participation_score: string };

export async function settleCivicDividends(tx: PostgresRepository, day: number): Promise<void> {
  const cities = await tx.query<{ id: string; economic_id: string }>(`SELECT c.id, o.economic_id FROM cities c
    JOIN owner_registry o ON o.id = c.id AND o.owner_type = 'city' AND o.status = 'active'`);
  for (const city of cities.rows) {
    const fiscalState = await tx.query<{ status: string }>('SELECT status FROM financial_states WHERE institution_id = $1', [city.id]);
    if (fiscalState.rows[0]?.status === 'fiscal_stress' || fiscalState.rows[0]?.status === 'receivership') continue;
    if ((await tx.query('SELECT id FROM civic_dividend_payouts WHERE city_id = $1 AND day = $2', [city.id, day])).rows[0]) continue;
    const surplus = await tx.query<{ total_surplus: string }>("SELECT COALESCE(SUM(net_surplus_crd), 0) AS total_surplus FROM building_settlement_journals WHERE city_id = $1 AND day = $2 AND ownership_class = 'civic'", [city.id, day]);
    const grossSurplusUnits = moneyToCents(surplus.rows[0]?.total_surplus ?? '0');
    if (grossSurplusUnits <= 0n) continue;
    const cityAccount = await tx.query<{ account_id: string; balance: string }>("SELECT id AS account_id, balance::TEXT AS balance FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 3 AND is_default_settlement AND status = 'active' FOR UPDATE", [city.economic_id]);
    if (!cityAccount.rows[0]) continue;
    const commitments = await tx.query<{ units: string }>(`SELECT
      COALESCE((SELECT SUM(authorized_units - committed_units - spent_units) FROM institution_budget_lines WHERE institution_id = $1 AND fiscal_period_id = earth_fiscal_period_for_day($2)), 0)
      + COALESCE((SELECT SUM(amount_units) FROM tax_obligations WHERE taxpayer_economic_id = $3 AND status IN ('DUE', 'PARTIAL', 'ARREARS')), 0)
      + COALESCE((SELECT SUM(LEAST(outstanding_principal_units + accrued_interest_units, accrued_interest_units + CASE WHEN remaining_installments > 0 THEN (outstanding_principal_units + remaining_installments - 1) / remaining_installments ELSE 0 END)) FROM bank_loans WHERE borrower_economic_id = $3 AND status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED') AND next_payment_game_day <= $2), 0) AS units`, [city.id, day, city.economic_id]);
    const committedUnits = BigInt(commitments.rows[0]?.units ?? '0');
    const requiredReserveUnits = BigInt(cityAccount.rows[0].balance) / 10n;
    const availableUnits = BigInt(cityAccount.rows[0].balance) - committedUnits - requiredReserveUnits;
    const distributableUnits = availableUnits > 0n ? (availableUnits < grossSurplusUnits ? availableUnits : grossSurplusUnits) : 0n;
    if (distributableUnits <= 0n) continue;
    const residents = await tx.query<Resident>(`SELECT m.human_id, o.economic_id, a.id AS account_id,
      (1 + (SELECT COUNT(*) FROM ballots b WHERE b.human_id = m.human_id))::TEXT AS participation_score
      FROM memberships m JOIN humans h ON h.id = m.human_id JOIN owner_registry o ON o.id = m.human_id AND o.status = 'active'
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 1 AND a.is_default_settlement AND a.status = 'active'
      WHERE m.city_id = $1 AND h.life_status = 'active' ORDER BY m.human_id FOR UPDATE OF a`, [city.id]);
    if (residents.rows.length === 0) continue;
    const basePool = (distributableUnits * 70n) / 100n;
    const participationPool = distributableUnits - basePool;
    const totalScore = residents.rows.reduce((sum, resident) => sum + BigInt(resident.participation_score), 0n);
    const effects: Array<{ account_id: string; delta: string; reason_code: string }> = [];
    let paidUnits = 0n;
    for (const [index, resident] of residents.rows.entries()) {
      const base = index === residents.rows.length - 1 ? distributableUnits - paidUnits : basePool / BigInt(residents.rows.length) + (participationPool * BigInt(resident.participation_score)) / totalScore;
      if (base > 0n) { effects.push({ account_id: resident.account_id, delta: base.toString(), reason_code: 'CIVIC_DIVIDEND' }); paidUnits += base; }
    }
    effects.push({ account_id: cityAccount.rows[0].account_id, delta: (-paidUnits).toString(), reason_code: 'CIVIC_DIVIDEND' });
    const posting = await tx.query<{ transaction_id: string }>('SELECT transaction_id FROM earth_post_settlement_batch($1,$2,1439,$3,$4,$5,$6::jsonb)', [`civic-dividend:${city.id}:${day}`, day, 'city', city.id, 'civic-dividends-v2', JSON.stringify(effects)]);
    await tx.query(`INSERT INTO civic_dividend_payouts (id, city_id, day, total_civic_surplus, base_dividend_per_resident, participation_dividend_pool, eligible_residents_count, economic_transaction_id, committed_obligations_units, required_reserve_units, distributable_units)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, [`PAYOUT-${city.id}-${day}`, city.id, day, centsToMoney(grossSurplusUnits), centsToMoney((paidUnits * 70n) / 100n), centsToMoney((paidUnits * 30n) / 100n), residents.rows.length, posting.rows[0]?.transaction_id, committedUnits, requiredReserveUnits, paidUnits]);
  }
}
