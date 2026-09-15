import type { PostgresRepository } from './repository';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate_bps: string }>(`SELECT rate_bps
    FROM tax_rule_versions
     WHERE (tax_rule_id = 'TAX-MARKET-TRANSACTION' OR tax_rule_id = 'TAX-OUC-MARKET')
     AND effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
     AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
   ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`);
  const earthRate = String(Number(result.rows[0]?.rate_bps ?? 0) / 10000);
  if (!humanId) return earthRate;
  const membership = await repository.query<{ city_rules?: Record<string, unknown> | null; corporation_rules: Record<string, unknown> | null }>("SELECT NULL::JSONB AS city_rules, c.tax_charter AS corporation_rules FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE' LEFT JOIN corporations c ON c.id = ha.corporation_id WHERE h.id = $1 LIMIT 1", [humanId]);
  const rules = membership.rows[0];
  const cityRate = rules?.city_rules?.salesTaxBps;
  const corporationRate = rules?.corporation_rules?.salesTaxBps;
  const localRate = cityRate ?? corporationRate;
  return localRate === undefined || localRate === null ? earthRate : String(Number(localRate) / 10000);
}
