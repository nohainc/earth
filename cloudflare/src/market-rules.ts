import type { PostgresRepository } from './repository';
import { fromNanoMarkup } from './nano-markup.ts';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate_bps: string }>(`SELECT rate_bps
    FROM tax_rule_versions
   WHERE tax_rule_id = 'TAX-OUC-MARKET'
     AND effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
     AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
   ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`);
  const earthRate = String(Number(result.rows[0]?.rate_bps ?? 0) / 10000);
  if (!humanId) return earthRate;
  const membership = await repository.query<{ city_rules: unknown; corporation_rules: unknown }>("SELECT city_institution.charter_rules AS city_rules, corporation_institution.charter_rules AS corporation_rules FROM memberships LEFT JOIN institutions city_institution ON city_institution.id = memberships.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = memberships.corporation_id WHERE memberships.human_id = $1", [humanId]);
  const rules = membership.rows[0];
  const city = rules?.city_rules ? fromNanoMarkup<Record<string, unknown>>(rules.city_rules) : null;
  const corporation = rules?.corporation_rules ? fromNanoMarkup<Record<string, unknown>>(rules.corporation_rules) : null;
  const localRate = city?.salesTaxBps ?? corporation?.salesTaxBps;
  return localRate === undefined || localRate === null ? earthRate : String(Number(localRate) / 10000);
}
