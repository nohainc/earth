import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';

export async function settleCivicDividends(tx: PostgresRepository, day: number): Promise<void> {
  const cities = await tx.query<{ id: string }>("SELECT id FROM cities");
  for (const c of cities.rows) {
    const cityId = c.id;

    // Idempotency check: Skip if civic dividends for this city and day have already been distributed
    const priorPayout = await tx.query<{ id: string }>(
      'SELECT id FROM civic_dividend_payouts WHERE city_id = $1 AND day = $2',
      [cityId, day],
    );
    if (priorPayout.rows[0]) continue;

    // Query actual recorded net surplus from daily building settlement journals
    const journalQuery = await tx.query<{ total_surplus: string }>(
      "SELECT COALESCE(SUM(net_surplus_crd), 0) AS total_surplus FROM building_settlement_journals WHERE city_id = $1 AND day = $2 AND ownership_class = 'civic'",
      [cityId, day],
    );
    const totalCivicSurplus = Number(journalQuery.rows[0]?.total_surplus ?? 0);
    if (totalCivicSurplus <= 0) continue;

    // Find eligible residents (registered in city)
    const residents = await tx.query<{ human_id: string }>(
      "SELECT human_id FROM memberships WHERE city_id = $1 AND status = 'active'",
      [cityId],
    );
    if (residents.rows.length === 0) continue;

    const residentCount = residents.rows.length;
    // 70/30 Hybrid Formula: 70% Base Equal UBI + 30% Weighted Participation
    const baseDividendPool = totalCivicSurplus * 0.70;
    const baseDividendPerResident = baseDividendPool / residentCount;
    const participationPool = totalCivicSurplus * 0.30;

    // Calculate participation weighting based on civic engagement
    const residentParticipation: { human_id: string; score: number }[] = [];
    let totalParticipationScore = 0;
    for (const res of residents.rows) {
      const partQuery = await tx.query<{ count: string }>(
        'SELECT COUNT(*)::text AS count FROM ballots WHERE human_id = $1',
        [res.human_id],
      );
      const score = 1 + Number(partQuery.rows[0]?.count ?? 0);
      residentParticipation.push({ human_id: res.human_id, score });
      totalParticipationScore += score;
    }

    const cityAccount = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE account_id = $1 FOR UPDATE",
      [`account-city-${cityId}`],
    );
    if (!cityAccount.rows[0]) continue;

    // Distribute to residents with weighted participation
    for (const rp of residentParticipation) {
      const participationDividend = (participationPool * rp.score) / Math.max(1, totalParticipationScore);
      const totalResidentDividend = baseDividendPerResident + participationDividend;
      const payoutCents = BigInt(Math.round(totalResidentDividend * 100));

      if (moneyToCents(cityAccount.rows[0].balance) < payoutCents) break;

      const humanAccount = await tx.query<{ account_id: string }>(
        "SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
        [rp.human_id],
      );
      if (!humanAccount.rows[0]) continue;

      const correlationId = `CIVIC-DIV-${cityId}-${rp.human_id}-${day}`;
      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: cityAccount.rows[0].account_id,
        creditAccount: humanAccount.rows[0].account_id,
        amount: centsToMoney(payoutCents),
        reasonType: 'civic_dividend_payout',
        reasonId: `CIVIC-${cityId}-${day}`,
        ruleVersion: 'civic-dividends-v2',
        correlationId,
      });
    }

    // Record payout summary
    await tx.query(
      `INSERT INTO civic_dividend_payouts (
        id, city_id, day, total_civic_surplus,
        base_dividend_per_resident, participation_dividend_pool,
        eligible_residents_count
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        `PAYOUT-${cityId}-${day}`,
        cityId,
        day,
        totalCivicSurplus,
        baseDividendPerResident,
        participationPool,
        residentCount,
      ],
    );
  }
}
