import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { resolveEffectiveConstitution } from './constitutional-kernel-postgres.ts';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate_bps: string | null }>(`SELECT rules_json->>'EARTH.MARKET.TRANSACTION_TAX_RATE' AS rate_bps
    FROM resolved_constitution_snapshots_v5
   WHERE authority_type = 'EARTH' AND authority_id = 'EARTH'
     AND game_day = (SELECT game_day FROM earth_get_current_game_time())`);
  let earthRateBps = result.rows[0]?.rate_bps;
  if (earthRateBps === null || earthRateBps === undefined) {
    const day = (await readAuthoritativeGameTime(repository)).gameDay;
    const resolved = await resolveEffectiveConstitution(repository, { gameDay: day });
    const raw = resolved.rules['EARTH.MARKET.TRANSACTION_TAX_RATE'];
    if (raw === undefined) throw new Error('Canonical Earth market tax Constitution is unavailable');
    earthRateBps = String(raw);
  }
  const earthRate = String(Number(earthRateBps) / 10000);
  if (!humanId) return earthRate;
  const membership = await repository.query<{ corporation_sales_rate?: string | null; corporation_id?: string | null }>(`SELECT
      (SELECT s.rules_json->>'CORPORATION.TAX.SALES_RATE'
         FROM resolved_constitution_snapshots_v5 s
        WHERE s.authority_type = 'CORPORATION'
          AND s.authority_id = ha.corporation_id
          AND s.game_day = (SELECT game_day FROM earth_get_current_game_time())) AS corporation_sales_rate,
      ha.corporation_id
   FROM humans h
   JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
   WHERE h.id = $1 LIMIT 1`, [humanId]);
  const rules = membership.rows[0];
  let corporationRate = rules?.corporation_sales_rate;
  if (corporationRate === undefined || corporationRate === null) {
    if (rules?.corporation_id) {
      const day = (await readAuthoritativeGameTime(repository)).gameDay;
      const resolved = await resolveEffectiveConstitution(repository, { corporationId: rules.corporation_id, gameDay: day });
      const raw = resolved.rules['CORPORATION.TAX.SALES_RATE'];
      if (raw !== undefined) corporationRate = String(raw);
    }
  }
  return corporationRate === undefined || corporationRate === null ? earthRate : String(Number(corporationRate) / 10000);
}
