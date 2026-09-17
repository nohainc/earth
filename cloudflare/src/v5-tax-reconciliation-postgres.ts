import type { PostgresRepository } from './repository.ts';

type EarthLegacyTaxRule = { id: string; tax_rule_id: string; rate_bps: number };
type CorporationTaxState = {
  corporation_id: string;
  tax_charter: Record<string, unknown> | null;
  rules_json: Record<string, unknown> | null;
  version_ids: Record<string, unknown> | null;
};

const earthRuleCodes: Record<string, string> = {
  'TAX-BASIC-LEVY': 'EARTH.TAX.BASIC_LEVY_RATE',
  'TAX-MARKET-TRANSACTION': 'EARTH.MARKET.TRANSACTION_TAX_RATE',
  'TAX-OUC-MARKET': 'EARTH.MARKET.TRANSACTION_TAX_RATE',
};

function rate(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

/**
 * Compare migrated tax authorities without writing obligations, transactions,
 * or either rule store. This is deliberately a settlement phase so the
 * evidence is tied to the same assessed-day Constitution snapshots used by
 * tax execution.
 */
// @mutation-boundary caller-owned-transaction reconciliation-only
export async function reconcileV5TaxRulesInTransaction(tx: PostgresRepository, day: number): Promise<Record<string, unknown>> {
  const assessedDay = day - 1;
  if (assessedDay < 1) return { ok: true, day, assessedDay, rulesCompared: 0, matches: 0, mismatches: 0, missingCanonical: 0 };
  const runId = `V5-TAX-RECON-D${assessedDay}`;
  const [legacy, earthSnapshot, corporations] = await Promise.all([
    tx.query<EarthLegacyTaxRule>(`SELECT id, tax_rule_id, rate_bps
      FROM tax_rule_versions
     WHERE authority_type = 'EARTH'
       AND tax_rule_id = ANY($1::TEXT[])
       AND effective_from_game_day <= $2
       AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
     ORDER BY id`, [Object.keys(earthRuleCodes), assessedDay]),
    tx.query<{ rules_json: Record<string, unknown>; version_ids: Record<string, unknown> }>(`SELECT rules_json, version_ids
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1`, [assessedDay]),
    tx.query<CorporationTaxState>(`SELECT c.id AS corporation_id, c.tax_charter,
           s.rules_json, s.version_ids
      FROM corporations c
      LEFT JOIN resolved_constitution_snapshots_v5 s
        ON s.authority_type = 'CORPORATION' AND s.authority_id = c.id AND s.game_day = $1
     WHERE c.status = 'ACTIVE'`, [assessedDay]),
  ]);
  await tx.query(`INSERT INTO v5_tax_reconciliation_runs (id, assessed_game_day, status, completed_at)
    VALUES ($1, $2, 'COMPLETED', CURRENT_TIMESTAMP)
    ON CONFLICT (assessed_game_day) DO UPDATE SET status = 'COMPLETED', error_message = NULL, completed_at = CURRENT_TIMESTAMP`, [runId, assessedDay]);
  let rulesCompared = 0; let matches = 0; let mismatches = 0; let missingCanonical = 0;
  const record = async (input: { authorityType: 'EARTH' | 'CORPORATION'; authorityId: string; legacyRuleId: string; canonicalRuleCode: string; legacyRateBps: number; canonicalRateBps: number | null; legacyVersionId?: string | null; canonicalVersionId?: string | null }) => {
    const result = input.canonicalRateBps === null ? 'MISSING_CANONICAL' : input.canonicalRateBps === input.legacyRateBps ? 'MATCH' : 'MISMATCH';
    rulesCompared += 1;
    if (result === 'MATCH') matches += 1;
    if (result === 'MISMATCH') mismatches += 1;
    if (result === 'MISSING_CANONICAL') missingCanonical += 1;
    await tx.query(`INSERT INTO v5_tax_reconciliation_items
      (id, run_id, assessed_game_day, authority_type, authority_id, legacy_rule_id,
       canonical_rule_code, legacy_rate_bps, canonical_rate_bps, legacy_version_id,
       canonical_version_id, result)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
      ON CONFLICT (run_id, legacy_rule_id, authority_id) DO UPDATE SET
        canonical_rate_bps = EXCLUDED.canonical_rate_bps,
        canonical_version_id = EXCLUDED.canonical_version_id,
        result = EXCLUDED.result`, [`${runId}:${input.authorityType}:${input.authorityId}:${input.legacyRuleId}`, runId, assessedDay, input.authorityType, input.authorityId, input.legacyRuleId, input.canonicalRuleCode, input.legacyRateBps, input.canonicalRateBps, input.legacyVersionId ?? null, input.canonicalVersionId ?? null, result]);
  };
  const earth = earthSnapshot.rows[0];
  for (const rule of legacy.rows) {
    const code = earthRuleCodes[rule.tax_rule_id];
    if (!code) continue;
    await record({ authorityType: 'EARTH', authorityId: 'EARTH', legacyRuleId: rule.id, canonicalRuleCode: code, legacyRateBps: Number(rule.rate_bps), canonicalRateBps: rate(earth?.rules_json?.[code]), legacyVersionId: rule.id, canonicalVersionId: String(earth?.version_ids?.[code] ?? '') || null });
  }
  const corporationTaxFields: Array<[string, string]> = [
    ['incomeTaxBps', 'CORPORATION.TAX.INCOME_RATE'],
    ['salesTaxBps', 'CORPORATION.TAX.SALES_RATE'],
    ['corporateTaxBps', 'CORPORATION.TAX.CORPORATE_RATE'],
    ['propertyTaxBps', 'CORPORATION.TAX.PROPERTY_RATE'],
  ];
  for (const corporation of corporations.rows) {
    for (const [legacyField, code] of corporationTaxFields) {
      const legacyRateBps = rate(corporation.tax_charter?.[legacyField]);
      if (legacyRateBps === null) continue;
      await record({ authorityType: 'CORPORATION', authorityId: corporation.corporation_id, legacyRuleId: `tax_charter:${corporation.corporation_id}:${legacyField}`, canonicalRuleCode: code, legacyRateBps, canonicalRateBps: rate(corporation.rules_json?.[code]), legacyVersionId: `tax_charter-v${corporation.corporation_id}`, canonicalVersionId: String(corporation.version_ids?.[code] ?? '') || null });
    }
  }
  await tx.query(`UPDATE v5_tax_reconciliation_runs
     SET rules_compared = $2, matches = $3, mismatches = $4, missing_canonical = $5,
         status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
   WHERE id = $1`, [runId, rulesCompared, matches, mismatches, missingCanonical]);
  return { ok: true, day, assessedDay, rulesCompared, matches, mismatches, missingCanonical, runId };
}

/** Read-only operator report for one assessed game day. */
export async function getV5TaxReconciliation(repository: PostgresRepository, requestedAssessedDay?: number): Promise<Record<string, unknown>> {
  const assessedDay = requestedAssessedDay ?? Math.max(1, Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1) - 1);
  const run = (await repository.query('SELECT * FROM v5_tax_reconciliation_runs WHERE assessed_game_day = $1', [assessedDay])).rows[0];
  if (!run) return { ok: true, available: false, assessedGameDay: assessedDay, items: [], generatedFrom: 'postgres-v5-tax-reconciliation' };
  const items = (await repository.query('SELECT * FROM v5_tax_reconciliation_items WHERE run_id = $1 ORDER BY authority_type, authority_id, canonical_rule_code', [run.id])).rows;
  return { ok: true, available: true, run, items, generatedFrom: 'postgres-v5-tax-reconciliation' };
}
