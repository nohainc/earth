import type { PostgresRepository } from './repository.ts';

// @mutation-boundary caller-owned-transaction
import { calculateProgressiveCharge, type ProgressiveBracket } from './v5-progressive.ts';
import { postSettlementTransaction } from './economic-transaction-postgres.ts';

type Policy = { id: string; earthBaseRate: bigint; standardCapacity: bigint; corporationScheduleId: string; houseScheduleId: string };
type Schedule = { id: string; brackets: ProgressiveBracket[] };
type Member = { houseId: string; corporationId: string | null; houseEconomicId: string; corporationEconomicId: string | null; buildingUnits: bigint };

async function loadSchedule(tx: PostgresRepository, scheduleId: string): Promise<Schedule> {
  const rows = (await tx.query<{ ordinal: number; lower_bound_units: string; upper_bound_units: string | null; marginal_multiplier_numerator: string; marginal_multiplier_denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT, upper_bound_units::TEXT, marginal_multiplier_numerator::TEXT, marginal_multiplier_denominator::TEXT
    FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [scheduleId])).rows;
  const brackets = rows.length > 0
    ? rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower_bound_units), upperBound: row.upper_bound_units === null ? null : BigInt(row.upper_bound_units), multiplierNumerator: BigInt(row.marginal_multiplier_numerator), multiplierDenominator: BigInt(row.marginal_multiplier_denominator) }))
    : [{ ordinal: 1, lowerBound: 0n, upperBound: null, multiplierNumerator: 1n, multiplierDenominator: 1n }];
  return { id: scheduleId, brackets };
}

async function activePolicy(tx: PostgresRepository, day: number): Promise<Policy> {
  const snapshot = (await tx.query<{ id: string; rules_json: Record<string, unknown> }>(`SELECT id, rules_json
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1`, [day])).rows[0];
  const snapshotRules = snapshot?.rules_json ?? {};
  const snapshotFields = [
    'EARTH.CAPACITY.BASE_RATE',
    'EARTH.CAPACITY.STANDARD',
    'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE',
    'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE',
  ];
  if (snapshot && snapshotFields.every((code) => snapshotRules[code] !== undefined)) {
    return {
      id: snapshot.id,
      earthBaseRate: BigInt(String(snapshotRules['EARTH.CAPACITY.BASE_RATE'])),
      standardCapacity: BigInt(String(snapshotRules['EARTH.CAPACITY.STANDARD'])),
      corporationScheduleId: String(snapshotRules['EARTH.CAPACITY.PROGRESSIVE_SCHEDULE']),
      houseScheduleId: String(snapshotRules['EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE']),
    };
  }
  throw new Error(`Canonical Earth capacity snapshot is unavailable for assessed game day ${day}`);
}

async function account(tx: PostgresRepository, economicId: string, types: string[], lock = false): Promise<{ id: string; balance: bigint } | null> {
  const result = await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts
    WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = ANY($2::TEXT[]) AND status = 'ACTIVE'
    ORDER BY CASE account_type WHEN 'WALLET' THEN 0 WHEN 'OPERATIONS' THEN 1 WHEN 'TREASURY' THEN 2 ELSE 3 END
    LIMIT 1${lock ? ' FOR UPDATE' : ''}`, [economicId, types]);
  const row = result.rows[0];
  return row ? { id: row.id, balance: BigInt(row.balance_units) } : null;
}

async function recordObligation(tx: PostgresRepository, input: {
  level: 'HOUSE' | 'CORPORATION'; houseId?: string; corporationId?: string; payerEconomicId: string; beneficiaryEconomicId: string;
  day: number; assessedDay: number; usage: bigint; baseRate: bigint; schedule: Schedule; assessed: bigint; sourceKey: string; rulesVersion: string;
}): Promise<'PAID' | 'PARTIAL' | 'ARREARS' | 'EXISTING'> {
  const existing = (await tx.query<{ status: string }>('SELECT status FROM v5_capacity_obligations WHERE correlation_id = $1', [input.sourceKey])).rows[0];
  if (existing) return 'EXISTING';
  const obligationId = `V5-CAP-${input.level}-${input.sourceKey.replace(/[^A-Za-z0-9-]/g, '-')}`;
  const financialId = `V5-FIN-${input.level}-${input.sourceKey.replace(/[^A-Za-z0-9-]/g, '-')}`;
  await tx.query(`INSERT INTO financial_obligations
    (id, debtor_economic_id, creditor_economic_id, obligation_type, source_id, principal_due_units, due_game_day,
     priority_class, rule_version, status, created_game_day, debtor_account_purpose, creditor_account_purpose,
     nexus_type, authority_type, authority_id, base_reference, correlation_id)
    VALUES ($1,$2,$3,'CAPACITY_RENT',$4,$5,$6,20,$7,'DUE',$8,'WALLET','OPERATIONS','MEMBERSHIP','EARTH',$9,'physical_capacity_units',$10)
    ON CONFLICT (correlation_id) DO NOTHING`, [financialId, input.payerEconomicId, input.beneficiaryEconomicId, input.sourceKey, input.assessed.toString(), input.day, input.rulesVersion, input.day, input.level === 'HOUSE' ? (input.corporationId ?? 'EARTH') : 'EARTH', `v5-fin:${input.sourceKey}`]);
  const subjectColumn = input.level === 'HOUSE' ? 'house_id' : 'corporation_id';
  const subjectId = input.level === 'HOUSE' ? input.houseId : input.corporationId;
  const priorObligations = (await tx.query<{ id: string; financial_obligation_id: string | null; assessed_units: string; paid_units: string }>(
    `SELECT id, financial_obligation_id, assessed_units::TEXT, paid_units::TEXT
       FROM v5_capacity_obligations
      WHERE capacity_level = $1 AND ${subjectColumn} = $2 AND status <> 'PAID'
      ORDER BY game_day ASC, created_at ASC, id ASC FOR UPDATE`,
    [input.level, subjectId],
  )).rows;
  let priorOutstanding = priorObligations.reduce((sum, row) => sum + BigInt(row.assessed_units) - BigInt(row.paid_units), 0n);
  const payer = await account(tx, input.payerEconomicId, input.level === 'HOUSE' ? ['WALLET'] : ['OPERATIONS', 'TREASURY'], true);
  const beneficiary = await account(tx, input.beneficiaryEconomicId, ['OPERATIONS', 'TREASURY']);
  let remainingLiquidity = payer && beneficiary ? payer.balance : 0n;
  let paidPrior = 0n;
  for (const prior of priorObligations) {
    const due = BigInt(prior.assessed_units) - BigInt(prior.paid_units);
    const payment = remainingLiquidity < due ? remainingLiquidity : due;
    if (payment > 0n && prior.financial_obligation_id) {
      const newPaid = BigInt(prior.paid_units) + payment;
      const priorStatus = newPaid === BigInt(prior.assessed_units) ? 'PAID' : 'PARTIAL';
      await tx.query(`UPDATE v5_capacity_obligations SET paid_units = $2, status = $3 WHERE id = $1`, [prior.id, newPaid.toString(), priorStatus]);
      await tx.query(`UPDATE financial_obligations SET paid_units = $2, status = $3, updated_at = CURRENT_TIMESTAMP WHERE id = $1`, [prior.financial_obligation_id, newPaid.toString(), priorStatus]);
      paidPrior += payment;
      remainingLiquidity -= payment;
      priorOutstanding -= payment;
    }
  }
  const paid = remainingLiquidity < input.assessed ? remainingLiquidity : input.assessed;
  const totalOutstandingAfterPayment = priorOutstanding + input.assessed - paid;
  const status: 'PAID' | 'PARTIAL' | 'ARREARS' = totalOutstandingAfterPayment === 0n ? 'PAID' : (paidPrior + paid) > 0n ? (priorOutstanding > 0n ? 'ARREARS' : 'PARTIAL') : 'ARREARS';
  let transactionId: string | null = null;
  const totalPaid = paidPrior + paid;
  if (totalPaid > 0n) {
    const result = await postSettlementTransaction(tx, {
      correlationId: `v5-payment:${input.sourceKey}`,
      gameDay: input.day,
      kind: 'ASSET_TRANSFER',
      sourceType: 'CAPACITY_RENT',
      sourceId: input.level === 'HOUSE' ? input.houseId : input.corporationId,
      rulesVersion: input.rulesVersion,
      entries: [
        { accountId: payer!.id, assetId: 1, deltaUnits: (-totalPaid).toString() },
        { accountId: beneficiary!.id, assetId: 1, deltaUnits: totalPaid.toString() },
      ],
    });
    transactionId = result.transactionId ?? null;
    if (priorObligations.length) {
      await tx.query(`UPDATE v5_capacity_obligations SET payment_transaction_id = COALESCE(payment_transaction_id, $2) WHERE id = ANY($1::TEXT[])`, [priorObligations.map((row) => row.id), transactionId]);
    }
  }
  await tx.query(`INSERT INTO v5_capacity_obligations
    (id, capacity_level, house_id, corporation_id, payer_economic_id, beneficiary_economic_id, game_day, usage_units,
     base_rate_units, schedule_id, assessed_units, paid_units, status, financial_obligation_id, payment_transaction_id, correlation_id)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`, [obligationId, input.level, input.houseId ?? null, input.corporationId ?? null, input.payerEconomicId, input.beneficiaryEconomicId, input.assessedDay, input.usage.toString(), input.baseRate.toString(), input.schedule.id, input.assessed.toString(), paid.toString(), status, financialId, transactionId, input.sourceKey]);
  await tx.query(`UPDATE financial_obligations SET paid_units = $2, status = $3, payment_transaction_id = $4, updated_at = CURRENT_TIMESTAMP WHERE id = $1`, [financialId, paid.toString(), status, transactionId]);
  return status;
}

async function updateDelinquency(tx: PostgresRepository, subjectType: 'HOUSE' | 'CORPORATION', subjectId: string, day: number, outcome: 'PAID' | 'PARTIAL' | 'ARREARS' | 'EXISTING'): Promise<void> {
  if (outcome === 'EXISTING') return;
  const prior = (await tx.query<{ consecutive_missed_days: number; arrears_since_game_day: number | null }>(`SELECT consecutive_missed_days, arrears_since_game_day FROM v5_capacity_delinquency_state WHERE subject_type = $1 AND subject_id = $2 FOR UPDATE`, [subjectType, subjectId])).rows[0];
  const missed = outcome === 'PAID' ? 0 : Number(prior?.consecutive_missed_days ?? 0) + 1;
  let status: string;
  if (outcome === 'PAID') status = 'CURRENT';
  else if (subjectType === 'HOUSE') status = missed >= 5 ? 'PRODUCTIVE_CAPACITY_SUSPENDED' : missed >= 3 ? 'EXPANSION_BLOCKED' : missed >= 2 ? 'GRACE' : 'ARREARS';
  else status = missed >= 7 ? 'EARTH_RECEIVERSHIP' : missed >= 5 ? 'EXPANSION_SPENDING_RESTRICTED' : missed >= 2 ? 'GRACE' : 'EARTH_RENT_ARREARS';
  await tx.query(`INSERT INTO v5_capacity_delinquency_state (subject_type, subject_id, status, arrears_since_game_day, consecutive_missed_days, last_assessed_game_day)
    VALUES ($1,$2,$3,$4,$5,$6)
    ON CONFLICT (subject_type, subject_id) DO UPDATE SET status = EXCLUDED.status,
      arrears_since_game_day = CASE WHEN EXCLUDED.status = 'CURRENT' THEN NULL ELSE COALESCE(v5_capacity_delinquency_state.arrears_since_game_day, EXCLUDED.arrears_since_game_day) END,
      consecutive_missed_days = EXCLUDED.consecutive_missed_days, last_assessed_game_day = EXCLUDED.last_assessed_game_day, updated_at = CURRENT_TIMESTAMP`, [subjectType, subjectId, status, outcome === 'PAID' ? null : (prior?.arrears_since_game_day ?? day), missed, day]);
}

async function applyHouseProductiveStatus(tx: PostgresRepository, houseId: string, status: string): Promise<void> {
  const productiveStatus = status === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 'SUSPENDED' : 'ACTIVE';
  await tx.query(`UPDATE buildings b SET v5_productive_status = $2
    FROM owner_registry o
    WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND b.owner_economic_id = o.economic_id
      AND b.status = 'ACTIVE' AND b.v5_productive_status IS DISTINCT FROM $2`, [houseId, productiveStatus]);
}

async function ensureCorporationReceivershipCase(tx: PostgresRepository, corporationId: string, status: string, day: number, arrearsUnits: bigint): Promise<void> {
  if (status !== 'EARTH_RECEIVERSHIP') return;
  await tx.query(`INSERT INTO v5_corporation_receivership_cases (id, corporation_id, trigger_status, opened_game_day, arrears_units)
    VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, [`V5-RECEIVERSHIP-${corporationId}`, corporationId, status, day, arrearsUnits.toString()]);
}

/** V5 daily capacity assessment. The caller owns the settlement transaction. */
export async function settleV5CapacityInTransaction(tx: PostgresRepository, day: number): Promise<Record<string, unknown>> {
  if (day <= 1) return { ok: true, day, assessedDay: day - 1, skipped: true, houses: 0, corporations: 0, paid: 0, partial: 0, arrears: 0 };
  const policy = await activePolicy(tx, day - 1);
  const assessedDay = day - 1;
  const { executePendingV5CorporationDissolutionsInTransaction } = await import('./v5-membership-postgres.ts');
  await executePendingV5CorporationDissolutionsInTransaction(tx, assessedDay);
  const [houseSchedule, corporationSchedule] = await Promise.all([loadSchedule(tx, policy.houseScheduleId), loadSchedule(tx, policy.corporationScheduleId)]);
  const members = (await tx.query<Member>(`SELECT hsp.house_id AS "houseId", hsp.corporation_id AS "corporationId",
      ho.economic_id AS "houseEconomicId", co.economic_id AS "corporationEconomicId",
      hsp.productive_capacity_units::TEXT AS "buildingUnits"
    FROM v5_house_settlement_profiles hsp
    JOIN houses h ON h.id = hsp.house_id AND h.status = 'ACTIVE'
    JOIN owner_registry ho ON ho.id = hsp.house_id AND ho.owner_type = 'HOUSE'
    LEFT JOIN owner_registry co ON co.id = hsp.corporation_id AND co.owner_type = 'CORPORATION'
    LEFT JOIN corporations corp ON corp.id = hsp.corporation_id
   WHERE hsp.corporation_id IS NULL OR corp.created_game_day <= $1
    ORDER BY hsp.house_id`, [assessedDay])).rows.map((row) => ({ ...row, buildingUnits: BigInt(String(row.buildingUnits)) }));
  const corporationUnits = new Map<string, { economicId: string; residential: bigint; privateBuildings: bigint; publicBuildings: bigint }>();
  let paid = 0; let partial = 0; let arrears = 0; let houseAssessments = 0;
  for (const member of members) {
    const usage = 1n + member.buildingUnits;
    const baseRateResolution = member.corporationId === null
      ? { rate: policy.earthBaseRate, ruleSetId: policy.id }
      : await corporationBaseRate(tx, member.corporationId, assessedDay);
    const baseRate = baseRateResolution?.rate ?? null;
    if (baseRate !== null) {
      const charge = calculateProgressiveCharge({ quantity: usage, baseRate, brackets: houseSchedule.brackets });
      const result = await recordObligation(tx, { level: 'HOUSE', houseId: member.houseId, corporationId: member.corporationId ?? undefined, payerEconomicId: member.houseEconomicId, beneficiaryEconomicId: member.corporationEconomicId ?? 'ECON-EARTH-001', day, assessedDay, usage, baseRate, schedule: houseSchedule, assessed: charge.totalCharge, rulesVersion: baseRateResolution.ruleSetId, sourceKey: `house:${member.houseId}:${assessedDay}:${houseSchedule.id}:${member.corporationId ?? 'EARTH'}` });
      await updateDelinquency(tx, 'HOUSE', member.houseId, assessedDay, result);
      const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [member.houseId])).rows[0];
      await applyHouseProductiveStatus(tx, member.houseId, delinquency?.status ?? 'CURRENT');
      const statement = (await tx.query<{ assessed_units: string; paid_units: string; status: string }>(`SELECT assessed_units::TEXT, paid_units::TEXT, status FROM v5_capacity_obligations WHERE capacity_level = 'HOUSE' AND house_id = $1 AND game_day = $2 ORDER BY created_at DESC LIMIT 1`, [member.houseId, assessedDay])).rows[0];
      if (statement) {
        // Replays return EXISTING from recordObligation. The persisted
        // obligation status, rather than that replay marker, is the source
        // of truth for the statement projection.
        const statementDelinquency = delinquency?.status ?? (statement.status === 'PAID' ? 'CURRENT' : 'ARREARS');
        await tx.query(`INSERT INTO house_capacity_statements_v5
          (house_id, corporation_id, game_day, residential_units, building_units, total_units, base_rate_units,
           progressive_schedule_id, assessed_rent_units, paid_rent_units, arrears_units, delinquency_status, rules_version)
          VALUES ($1,$2,$3,1,$4,$5,$6,$7,$8,$9,$10,$11,$12)
          ON CONFLICT (house_id, game_day) DO UPDATE SET corporation_id = EXCLUDED.corporation_id,
            residential_units = EXCLUDED.residential_units, building_units = EXCLUDED.building_units,
            total_units = EXCLUDED.total_units, base_rate_units = EXCLUDED.base_rate_units,
            progressive_schedule_id = EXCLUDED.progressive_schedule_id, assessed_rent_units = EXCLUDED.assessed_rent_units,
          paid_rent_units = EXCLUDED.paid_rent_units, arrears_units = EXCLUDED.arrears_units,
            delinquency_status = EXCLUDED.delinquency_status, rules_version = EXCLUDED.rules_version`, [member.houseId, member.corporationId, assessedDay, member.buildingUnits.toString(), usage.toString(), baseRate.toString(), houseSchedule.id, statement.assessed_units, statement.paid_units, (BigInt(statement.assessed_units) - BigInt(statement.paid_units)).toString(), statementDelinquency, baseRateResolution.ruleSetId]);
      }
      if (result !== 'EXISTING') { houseAssessments += 1; if (result === 'PAID') paid += 1; else if (result === 'PARTIAL') partial += 1; else arrears += 1; }
    }
    if (member.corporationId) {
      const current = corporationUnits.get(member.corporationId) ?? { economicId: member.corporationEconomicId ?? '', residential: 0n, privateBuildings: 0n, publicBuildings: 0n };
      current.residential += 1n; current.privateBuildings += member.buildingUnits; corporationUnits.set(member.corporationId, current);
    }
  }
  const corporationProfiles = (await tx.query<{ corporation_id: string; economic_id: string; residential: string; productive: string; public_units: string }>(`SELECT p.corporation_id, o.economic_id,
      p.member_residential_capacity_units::TEXT AS residential,
      p.member_productive_capacity_units::TEXT AS productive,
      p.public_capacity_units::TEXT AS public_units
    FROM v5_corporation_settlement_profiles p
    JOIN corporations c ON c.id = p.corporation_id AND c.status = 'ACTIVE'
    JOIN owner_registry o ON o.id = p.corporation_id AND o.owner_type = 'CORPORATION'
   WHERE c.created_game_day <= $1
    ORDER BY p.corporation_id`, [assessedDay])).rows;
  for (const row of corporationProfiles) {
    corporationUnits.set(row.corporation_id, {
      economicId: row.economic_id,
      residential: BigInt(row.residential),
      privateBuildings: BigInt(row.productive),
      publicBuildings: BigInt(row.public_units),
    });
  }
  for (const [corporationId, units] of corporationUnits) {
    if (!units.economicId) units.economicId = (await tx.query<{ economic_id: string }>(`SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'CORPORATION'`, [corporationId])).rows[0]?.economic_id ?? '';
    if (!units.economicId) continue;
    const usage = units.residential + units.privateBuildings + units.publicBuildings;
    const charge = calculateProgressiveCharge({ quantity: usage, baseRate: policy.earthBaseRate, brackets: corporationSchedule.brackets });
    const requiredTerritories = usage === 0n ? 0n : (usage + policy.standardCapacity - 1n) / policy.standardCapacity;
    await tx.query(`INSERT INTO corporation_capacity_state_v5
      (corporation_id, game_day, residential_units_used, private_building_units_used, public_building_units_used,
      total_occupied_units, standard_territory_capacity_units, required_territory_units, rules_version)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      ON CONFLICT (corporation_id, game_day) DO UPDATE SET residential_units_used = EXCLUDED.residential_units_used,
        private_building_units_used = EXCLUDED.private_building_units_used, public_building_units_used = EXCLUDED.public_building_units_used,
        total_occupied_units = EXCLUDED.total_occupied_units, standard_territory_capacity_units = EXCLUDED.standard_territory_capacity_units,
        required_territory_units = EXCLUDED.required_territory_units, rules_version = EXCLUDED.rules_version, updated_at = CURRENT_TIMESTAMP`, [corporationId, assessedDay, units.residential.toString(), units.privateBuildings.toString(), units.publicBuildings.toString(), usage.toString(), policy.standardCapacity.toString(), requiredTerritories.toString(), policy.id]);
    const result = await recordObligation(tx, { level: 'CORPORATION', corporationId, payerEconomicId: units.economicId, beneficiaryEconomicId: 'ECON-EARTH-001', day, assessedDay, usage, baseRate: policy.earthBaseRate, schedule: corporationSchedule, assessed: charge.totalCharge, rulesVersion: policy.id, sourceKey: `corporation:${corporationId}:${assessedDay}:${corporationSchedule.id}` });
    await updateDelinquency(tx, 'CORPORATION', corporationId, assessedDay, result);
    const corporationStatus = (await tx.query<{ status: string; consecutive_missed_days: number }>(`SELECT status, consecutive_missed_days FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1`, [corporationId])).rows[0];
    const outstanding = charge.totalCharge;
    await ensureCorporationReceivershipCase(tx, corporationId, corporationStatus?.status ?? 'CURRENT', assessedDay, outstanding);
    if (result !== 'EXISTING') { if (result === 'PAID') paid += 1; else if (result === 'PARTIAL') partial += 1; else arrears += 1; }
  }
  return { ok: true, day, assessedDay, houses: houseAssessments, corporations: corporationUnits.size, paid, partial, arrears, policyVersion: policy.id };
}

async function corporationBaseRate(tx: PostgresRepository, corporationId: string, day: number): Promise<{ rate: bigint; ruleSetId: string }> {
  const snapshot = (await tx.query<{ id: string; rules_json: Record<string, unknown> }>(`SELECT id, rules_json FROM resolved_constitution_snapshots_v5 WHERE authority_type = 'CORPORATION' AND authority_id = $1 AND game_day = $2`, [corporationId, day])).rows[0];
  const snapshotRate = snapshot?.rules_json?.['CORPORATION.HOUSE_CAPACITY.BASE_RATE'];
  if (snapshotRate !== undefined && snapshot) return { rate: BigInt(String(snapshotRate)), ruleSetId: snapshot.id };
  throw new Error(`Canonical Corporation capacity snapshot is unavailable for Corporation ${corporationId} on game day ${day}`);
}
