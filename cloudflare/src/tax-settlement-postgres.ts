import type { PostgresRepository } from './repository.ts';
import { calculateProgressiveCharge, type ProgressiveBracket } from './v5-progressive.ts';

type TaxRule = { id: string; tax_rule_id: string; category: string; rate_bps: number; tax_base_definition: string; base_reference: string; base_amount_units: string; nexus_type: string; authority_type: string; authority_id: string | null; beneficiary_economic_id: string };
type ConstitutionalHouseIncomeTax = { id: string; corporation_id: string; beneficiary_economic_id: string; schedule_id: string; version_id: string };

function positive(value: string | number | null | undefined) {
  const units = BigInt(String(value ?? '0'));
  return units > 0n ? units : 0n;
}

async function assessableBase(tx: PostgresRepository, rule: TaxRule, houseId: string, assessedDay: number) {
  if (rule.tax_base_definition === 'fixed_daily_obligation') return BigInt(rule.base_amount_units);
  if (rule.tax_base_definition === 'positive_realized_daily_income' || rule.tax_base_definition === 'positive_realized_daily_taxable_profit') {
    const statement = (await tx.query<{ net_credit_units: string }>('SELECT net_credit_units::TEXT FROM house_daily_statements WHERE house_id = $1 AND game_day = $2', [houseId, assessedDay])).rows[0];
    return positive(statement?.net_credit_units);
  }
  if (rule.tax_base_definition === 'external_market_trade') {
    const result = await tx.query<{ volume: string }>(`SELECT COALESCE(SUM(f.quantity_units * f.price_units),0)::TEXT AS volume FROM market_fills f JOIN market_batches b ON b.id = f.batch_id WHERE b.game_day = $1 AND (f.buyer_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $2) OR f.seller_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $2))`, [assessedDay, houseId]);
    return positive(result.rows[0]?.volume);
  }
  throw new Error(`Unsupported tax base definition: ${rule.tax_base_definition}`);
}

async function loadSchedule(tx: PostgresRepository, scheduleId: string): Promise<ProgressiveBracket[]> {
  return (await tx.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(
    `SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper,
            marginal_multiplier_numerator::TEXT AS numerator,
            marginal_multiplier_denominator::TEXT AS denominator
       FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [scheduleId],
  )).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
}

async function payObligation(tx: PostgresRepository, input: { obligationId: string; taxpayerEconomicId: string; beneficiaryEconomicId: string; amount: bigint; day: number; correlationId: string; ruleVersion: string }) {
  const wallet = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`, [input.taxpayerEconomicId])).rows[0];
  const beneficiary = (await tx.query<{ id: string }>(`SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type IN ('OPERATIONS','TREASURY') AND status = 'ACTIVE' ORDER BY CASE account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END LIMIT 1 FOR UPDATE`, [input.beneficiaryEconomicId])).rows[0];
  if (!wallet || !beneficiary || BigInt(wallet.balance_units) < input.amount) {
    await tx.query("UPDATE financial_obligations SET status = 'ARREARS', updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND status IN ('DUE','PARTIAL')", [input.obligationId]);
    await tx.query("UPDATE tax_obligations SET status = 'ARREARS' WHERE id = $1 AND status NOT IN ('PAID','SETTLED')", [input.obligationId]);
    return { paid: false, transactionId: null };
  }
  const result = await tx.query<{ transaction_id: string }>(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','TAX_COLLECTION',$3,$4,$5::JSONB) AS transaction_id`, [input.correlationId, input.day, input.obligationId, input.ruleVersion, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-input.amount).toString() }, { account_id: beneficiary.id, asset_id: 1, delta_units: input.amount.toString() }])]);
  const transactionId = result.rows[0]?.transaction_id;
  if (!transactionId) throw new Error('Tax collection transaction was not created');
  await tx.query("UPDATE financial_obligations SET paid_units = principal_due_units + interest_due_units, status = 'PAID', payment_transaction_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1", [input.obligationId, transactionId]);
  await tx.query("UPDATE tax_obligations SET status = 'PAID', payment_transaction_id = $2 WHERE id = $1", [input.obligationId, transactionId]);
  return { paid: true, transactionId };
}

async function assessCanonicalHouseIncomeTax(
  tx: PostgresRepository,
  input: { houseId: string; houseEconomicId: string; authorityType: 'EARTH' | 'CORPORATION'; authorityId: string; beneficiaryEconomicId: string; scheduleId: string; ruleVersion: string; day: number; assessedDay: number },
): Promise<'PAID' | 'ARREARS' | 'EXISTING' | 'ZERO'> {
  const base = await assessableBase(tx, {
    id: input.ruleVersion,
    tax_rule_id: input.authorityType === 'EARTH' ? 'EARTH.HOUSE_INCOME_TAX' : 'CORPORATION.HOUSE_INCOME_TAX',
    category: input.authorityType === 'EARTH' ? 'earth_house_income' : 'corporation_house_income',
    rate_bps: 0,
    tax_base_definition: 'positive_realized_daily_income',
    base_reference: 'positive_realized_daily_income',
    base_amount_units: '0',
    nexus_type: 'HOUSE_INCOME',
    authority_type: input.authorityType,
    authority_id: input.authorityId,
    beneficiary_economic_id: input.beneficiaryEconomicId,
  }, input.houseId, input.assessedDay);
  const brackets = await loadSchedule(tx, input.scheduleId);
  const amount = calculateProgressiveCharge({ quantity: base, baseRate: 10_000n, brackets }).totalCharge;
  if (amount <= 0n) return 'ZERO';
  const key = `v5-house-income-tax:${input.authorityType}:${input.authorityId}:${input.houseId}:${input.assessedDay}:${input.ruleVersion}`;
  const existing = (await tx.query<{ status: string }>('SELECT status FROM financial_obligations WHERE correlation_id = $1', [key])).rows[0];
  if (existing) return existing.status === 'PAID' ? 'EXISTING' : 'EXISTING';
  const obligationId = `V5-HOUSE-TAX-${input.authorityType}-${input.authorityId}-${input.houseId}-${input.assessedDay}`;
  await tx.query(`INSERT INTO financial_obligations
    (id, debtor_economic_id, creditor_economic_id, obligation_type, source_id, principal_due_units,
     due_game_day, priority_class, rule_version, status, created_game_day, nexus_type,
     authority_type, authority_id, base_reference, correlation_id)
    VALUES ($1,$2,$3,'TAX',$4,$5,$6,10,$7,'DUE',$8,$9,$10,$11,$12,$13)`,
    [obligationId, input.houseEconomicId, input.beneficiaryEconomicId, input.ruleVersion, amount.toString(), input.day, input.ruleVersion, input.day, 'HOUSE_INCOME', input.authorityType, input.authorityId, 'positive_realized_daily_income', key]);
  await tx.query(`INSERT INTO tax_obligations
    (id, taxpayer_economic_id, beneficiary_economic_id, tax_type, tax_base_units, amount_units,
     rule_version, game_day, status, due_game_day, nexus_type, authority_type, authority_id,
     base_reference, correlation_id)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'DUE',$9,'HOUSE_INCOME',$10,$11,'positive_realized_daily_income',$12)
    ON CONFLICT (correlation_id) DO NOTHING`,
    [obligationId, input.houseEconomicId, input.beneficiaryEconomicId, input.authorityType === 'EARTH' ? 'earth_house_income' : 'corporation_house_income', base.toString(), amount.toString(), input.ruleVersion, input.assessedDay, input.day, input.authorityType, input.authorityId, key]);
  const result = await payObligation(tx, { obligationId, taxpayerEconomicId: input.houseEconomicId, beneficiaryEconomicId: input.beneficiaryEconomicId, amount, day: input.day, correlationId: `v5-house-income-tax-payment:${key}`, ruleVersion: input.ruleVersion });
  return result.paid ? 'PAID' : 'ARREARS';
}

export async function settlePublicTaxesInTransaction(repository: PostgresRepository, day: number, shard = 0, shardCount = 1) {
  const assessedDay = day - 1;
  if (assessedDay < 1) return { ok: true, day, assessedDay, assessed: 0, paid: 0, arrears: 0 };
  const [constitutionResult, corporationTaxResult, affiliationResult] = await Promise.all([
    repository.query<{ rules_json: Record<string, unknown>; version_ids: Record<string, string> }>(`SELECT rules_json, version_ids
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1`, [assessedDay]),
    repository.query<ConstitutionalHouseIncomeTax>(`SELECT c.id AS corporation_id,
           o.economic_id AS beneficiary_economic_id,
           s.rules_json->>'CORPORATION.HOUSE_INCOME_TAX' AS schedule_id,
           s.version_ids->>'CORPORATION.HOUSE_INCOME_TAX' AS version_id,
           s.version_ids->>'CORPORATION.HOUSE_INCOME_TAX' AS id
      FROM corporations c
      JOIN owner_registry o ON o.id = c.id AND o.owner_type = 'CORPORATION'
      JOIN resolved_constitution_snapshots_v5 s
        ON s.authority_type = 'CORPORATION' AND s.authority_id = c.id AND s.game_day = $1
     WHERE c.status = 'ACTIVE' AND s.rules_json ? 'CORPORATION.HOUSE_INCOME_TAX'`, [assessedDay]),
    repository.query<{ house_id: string; corporation_id: string }>(`SELECT house_id, corporation_id
      FROM house_affiliations
     WHERE status = 'ACTIVE' AND joined_game_day <= $1
       AND (left_game_day IS NULL OR left_game_day >= $1)`, [assessedDay]),
  ]);
  const constitution = constitutionResult.rows[0];
  const constitutionRules = constitution?.rules_json ?? {};
  const canonicalRate = (code: string): number => {
    const value = constitutionRules[code];
    if (value === undefined) throw new Error(`Canonical Earth tax snapshot is missing ${code} for assessed game day ${assessedDay}`);
    const rate = Number(value);
    if (!Number.isSafeInteger(rate) || rate < 0 || rate > 10_000) throw new Error(`Canonical Earth tax rate is invalid: ${code}`);
    return rate;
  };
  const rules: TaxRule[] = [
    {
      id: constitution?.version_ids?.['EARTH.TAX.BASIC_LEVY_RATE'] ?? 'EARTH.TAX.BASIC_LEVY_RATE',
      tax_rule_id: 'EARTH.TAX.BASIC_LEVY_RATE', category: 'basic_levy', rate_bps: canonicalRate('EARTH.TAX.BASIC_LEVY_RATE'),
      tax_base_definition: 'fixed_daily_obligation', base_reference: 'fixed_daily_obligation', base_amount_units: '0',
      nexus_type: 'EARTH', authority_type: 'EARTH', authority_id: 'EARTH', beneficiary_economic_id: 'ECON-EARTH-001',
    },
    {
      id: constitution?.version_ids?.['EARTH.MARKET.TRANSACTION_TAX_RATE'] ?? 'EARTH.MARKET.TRANSACTION_TAX_RATE',
      tax_rule_id: 'EARTH.MARKET.TRANSACTION_TAX_RATE', category: 'market_transaction', rate_bps: canonicalRate('EARTH.MARKET.TRANSACTION_TAX_RATE'),
      tax_base_definition: 'external_market_trade', base_reference: 'external_market_trade', base_amount_units: '0',
      nexus_type: 'EARTH', authority_type: 'EARTH', authority_id: 'EARTH', beneficiary_economic_id: 'ECON-EARTH-001',
    },
  ];
  const corporationMemberships = new Map<string, Set<string>>();
  for (const affiliation of affiliationResult.rows) {
    const housesForCorporation = corporationMemberships.get(affiliation.corporation_id) ?? new Set<string>();
    housesForCorporation.add(affiliation.house_id);
    corporationMemberships.set(affiliation.corporation_id, housesForCorporation);
  }
  const houses = (await repository.query<{ house_id: string; economic_id: string; territory_id: string | null }>(`SELECT h.id AS house_id, o.economic_id, r.territory_id FROM houses h JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE' LEFT JOIN house_residencies r ON r.house_id = h.id AND r.residency_class = 'PRIMARY' AND r.status = 'ACTIVE' WHERE h.status = 'ACTIVE' AND MOD(ABS(hashtextextended(h.id,0)),$1) = $2 ORDER BY h.id`, [shardCount, shard])).rows;
  let assessed = 0; let paid = 0; let arrears = 0;
  for (const house of houses) {
    for (const rule of rules) {
      if (rule.authority_type === 'TERRITORY_GOVERNANCE' && rule.authority_id !== house.territory_id) continue;
      if (rule.authority_type === 'CORPORATION' && !corporationMemberships.get(String(rule.authority_id))?.has(house.house_id)) continue;
      const base = await assessableBase(repository, rule, house.house_id, assessedDay);
      const rateBps = BigInt(rule.rate_bps);
      const ruleVersion = rule.id;
      const amount = base * rateBps / 10_000n;
      if (amount <= 0n) continue;
      const correlationId = `tax:${rule.id}:${house.house_id}:${assessedDay}`;
      const result = await (async (tx) => {
        const existing = (await tx.query<{ id: string; status: string }>('SELECT id, status FROM financial_obligations WHERE correlation_id = $1', [correlationId])).rows[0];
        if (existing) return { paid: existing.status === 'PAID' };
        const obligationId = `TAX-OBL-${rule.id}-${house.house_id}-${assessedDay}`;
        await tx.query(`INSERT INTO financial_obligations (id,debtor_economic_id,creditor_economic_id,obligation_type,source_id,principal_due_units,due_game_day,priority_class,rule_version,status,created_game_day,nexus_type,authority_type,authority_id,base_reference,correlation_id) VALUES ($1,$2,$3,'TAX',$4,$5,$6,10,$7,'DUE',$8,$9,$10,$11,$12,$13)`, [obligationId, house.economic_id, rule.beneficiary_economic_id, rule.id, amount.toString(), day, ruleVersion, day, rule.nexus_type, rule.authority_type, rule.authority_id, rule.base_reference, correlationId]);
        await tx.query(`INSERT INTO tax_obligations (id,taxpayer_economic_id,beneficiary_economic_id,tax_type,tax_base_units,amount_units,rule_version,game_day,status,due_game_day,nexus_type,authority_type,authority_id,base_reference,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'DUE',$9,$10,$11,$12,$13,$14) ON CONFLICT (correlation_id) DO NOTHING`, [obligationId, house.economic_id, rule.beneficiary_economic_id, rule.category, base.toString(), amount.toString(), ruleVersion, assessedDay, day, rule.nexus_type, rule.authority_type, rule.authority_id, rule.base_reference, correlationId]);
        return payObligation(tx, { obligationId, taxpayerEconomicId: house.economic_id, beneficiaryEconomicId: rule.beneficiary_economic_id, amount, day, correlationId: `tax-payment:${correlationId}`, ruleVersion });
      })(repository);
      assessed += 1; if (result.paid) paid += 1; else arrears += 1;
    }
  }
  const earthIncomeScheduleId = constitutionRules['EARTH.HOUSE_INCOME_TAX'] === undefined ? null : String(constitutionRules['EARTH.HOUSE_INCOME_TAX']);
  const corporationIncomeSchedules = new Map<string, { scheduleId: string; versionId: string }>();
  for (const policy of corporationTaxResult.rows) corporationIncomeSchedules.set(policy.corporation_id, { scheduleId: policy.schedule_id, versionId: policy.version_id });
  for (const house of houses) {
    if (earthIncomeScheduleId) {
      const result = await assessCanonicalHouseIncomeTax(repository, { houseId: house.house_id, houseEconomicId: house.economic_id, authorityType: 'EARTH', authorityId: 'EARTH', beneficiaryEconomicId: 'ECON-EARTH-001', scheduleId: earthIncomeScheduleId, ruleVersion: String(constitution?.version_ids?.['EARTH.HOUSE_INCOME_TAX'] ?? earthIncomeScheduleId), day, assessedDay });
      if (result !== 'ZERO' && result !== 'EXISTING') { assessed += 1; if (result === 'PAID') paid += 1; else arrears += 1; }
    }
    const corporationId = corporationMembershipsForHouse(corporationMemberships, house.house_id);
    const corporationPolicy = corporationId ? corporationIncomeSchedules.get(corporationId) : undefined;
    if (corporationPolicy) {
      const beneficiary = (await repository.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = \'CORPORATION\'', [corporationId])).rows[0]?.economic_id;
      if (!beneficiary) throw new Error(`Corporation tax beneficiary is unavailable: ${corporationId}`);
      const result = await assessCanonicalHouseIncomeTax(repository, { houseId: house.house_id, houseEconomicId: house.economic_id, authorityType: 'CORPORATION', authorityId: corporationId, beneficiaryEconomicId: beneficiary, scheduleId: corporationPolicy.scheduleId, ruleVersion: corporationPolicy.versionId, day, assessedDay });
      if (result !== 'ZERO' && result !== 'EXISTING') { assessed += 1; if (result === 'PAID') paid += 1; else arrears += 1; }
    }
  }
  return { ok: true, day, assessedDay, assessed, paid, arrears, shard, shardCount };
}

function corporationMembershipsForHouse(memberships: Map<string, Set<string>>, houseId: string): string | null {
  for (const [corporationId, houses] of memberships) if (houses.has(houseId)) return corporationId;
  return null;
}

export async function settlePublicTaxes(repository: PostgresRepository, day: number, shard = 0, shardCount = 1) {
  return repository.transaction((tx) => settlePublicTaxesInTransaction(tx, day, shard, shardCount));
}
