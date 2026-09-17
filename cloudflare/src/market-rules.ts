import type { PostgresRepository } from './repository';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate_bps: string | null }>(`SELECT rules_json->>'EARTH.MARKET.TRANSACTION_TAX_RATE' AS rate_bps
    FROM resolved_constitution_snapshots_v5
   WHERE authority_type = 'EARTH' AND authority_id = 'EARTH'
     AND game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD')`);
  const earthRateBps = result.rows[0]?.rate_bps;
  if (earthRateBps === null || earthRateBps === undefined) throw new Error('Canonical Earth market tax Constitution is unavailable');
  const earthRate = String(Number(earthRateBps) / 10000);
  if (!humanId) return earthRate;
  const membership = await repository.query<{ corporation_sales_rate?: string | null }>(`SELECT
      (SELECT s.rules_json->>'CORPORATION.TAX.SALES_RATE'
         FROM resolved_constitution_snapshots_v5 s
        WHERE s.authority_type = 'CORPORATION'
          AND s.authority_id = ha.corporation_id
          AND s.game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD')) AS corporation_sales_rate
   FROM humans h
   JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
   WHERE h.id = $1 LIMIT 1`, [humanId]);
  const rules = membership.rows[0];
  const corporationRate = rules?.corporation_sales_rate;
  return corporationRate === undefined || corporationRate === null ? earthRate : String(Number(corporationRate) / 10000);
}
