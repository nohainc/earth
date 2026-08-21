import type { PostgresRepository } from './repository';
import { fromNanoMarkup } from './nano-markup.ts';

export async function marketFeeRate(repository: PostgresRepository, humanId?: string): Promise<string> {
  const result = await repository.query<{ rate: string }>("SELECT rate FROM tax_rules WHERE scope = 'global' AND category = 'market' AND active = true LIMIT 1");
  const earthRate = result.rows[0]?.rate ?? '0';
  if (!humanId) return earthRate;
  const membership = await repository.query<{ city_rules: unknown; corporation_rules: unknown }>("SELECT city_institution.charter_rules AS city_rules, corporation_institution.charter_rules AS corporation_rules FROM memberships LEFT JOIN institutions city_institution ON city_institution.id = memberships.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = memberships.corporation_id WHERE memberships.human_id = $1", [humanId]);
  const rules = membership.rows[0];
  const city = rules?.city_rules ? fromNanoMarkup<Record<string, unknown>>(rules.city_rules) : null;
  const corporation = rules?.corporation_rules ? fromNanoMarkup<Record<string, unknown>>(rules.corporation_rules) : null;
  const localRate = city?.salesTaxBps ?? corporation?.salesTaxBps;
  return localRate === undefined || localRate === null ? earthRate : String(Number(localRate) / 10000);
}
