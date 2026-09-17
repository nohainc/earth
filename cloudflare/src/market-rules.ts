import type { PostgresRepository } from './repository';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate_bps: string }>(`SELECT COALESCE(
      (SELECT s.rules_json->>'EARTH.MARKET.TRANSACTION_TAX_RATE'
         FROM resolved_constitution_snapshots_v5 s
        WHERE s.authority_type = 'EARTH'
          AND s.authority_id = 'EARTH'
          AND s.game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD')),
      rate_bps::TEXT
    ) AS rate_bps
    FROM tax_rule_versions
     WHERE (tax_rule_id = 'TAX-MARKET-TRANSACTION' OR tax_rule_id = 'TAX-OUC-MARKET')
     AND effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
     AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
   ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`);
  const earthRate = String(Number(result.rows[0]?.rate_bps ?? 0) / 10000);
  if (!humanId) return earthRate;
  const membership = await repository.query<{ corporation_sales_rate?: string | null; corporation_rules?: Record<string, unknown> | null }>(`SELECT
      (SELECT s.rules_json->>'CORPORATION.TAX.SALES_RATE'
         FROM resolved_constitution_snapshots_v5 s
        WHERE s.authority_type = 'CORPORATION'
          AND s.authority_id = ha.corporation_id
          AND s.game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD')) AS corporation_sales_rate
    FROM humans h
    JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
   WHERE h.id = $1 LIMIT 1`, [humanId]);
  const rules = membership.rows[0];
  const corporationRate = rules?.corporation_sales_rate ?? rules?.corporation_rules?.salesTaxBps;
  return corporationRate === undefined || corporationRate === null ? earthRate : String(Number(corporationRate) / 10000);
}
