import type { PostgresRepository } from './repository.ts';
import { getResolvedConstitutionForDay } from './constitutional-kernel-postgres.ts';

function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  }
  return value;
}

export async function getTaxStatement(repository: PostgresRepository, humanId: string) {
  const result = await repository.transaction(async (tx) => {
    const house = (await tx.query<{ house_id: string; territory_id: string | null; corporation_id: string | null }>(`SELECT h.house_id, r.territory_id, a.corporation_id FROM humans h LEFT JOIN house_residencies r ON r.house_id = h.house_id AND r.residency_class = 'PRIMARY' AND r.status = 'ACTIVE' LEFT JOIN LATERAL (SELECT corporation_id FROM house_affiliations WHERE house_id = h.house_id AND status = 'ACTIVE' ORDER BY joined_game_day DESC, corporation_id LIMIT 1) a ON TRUE WHERE h.id = $1 AND h.status = 'ACTIVE' ORDER BY r.effective_from_game_day DESC LIMIT 1`, [humanId])).rows[0];
    if (!house) throw new Error('Active House is required');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const [obligations, arrears, constitution] = await Promise.all([
      tx.query(`SELECT id, obligation_type, principal_due_units::TEXT, interest_due_units::TEXT, paid_units::TEXT, due_game_day, status, rule_version, nexus_type, authority_type, authority_id, base_reference FROM financial_obligations WHERE debtor_economic_id = (SELECT o.economic_id FROM owner_registry o WHERE o.id = $1 AND o.owner_type = 'HOUSE') AND obligation_type = 'TAX' ORDER BY due_game_day DESC, id DESC`, [house.house_id]),
      tx.query(`SELECT id, tax_type, tax_base_units::TEXT, amount_units::TEXT, rule_version, game_day, status, nexus_type, authority_type, authority_id, base_reference FROM tax_obligations WHERE taxpayer_economic_id = (SELECT o.economic_id FROM owner_registry o WHERE o.id = $1 AND o.owner_type = 'HOUSE') ORDER BY game_day DESC, id DESC`, [house.house_id]),
      getResolvedConstitutionForDay(tx, { corporationId: house.corporation_id ?? undefined, gameDay: day }),
    ]);
    const constitutionalTaxRules = Object.fromEntries(Object.entries(constitution.rules).filter(([code]) => code.includes('.TAX') || code === 'EARTH.HOUSE_INCOME_TAX' || code === 'CORPORATION.HOUSE_INCOME_TAX'));
    const constitutionalTaxVersionIds = Object.fromEntries(Object.entries(constitution.versionIds).filter(([code]) => code.includes('.TAX') || code === 'EARTH.HOUSE_INCOME_TAX' || code === 'CORPORATION.HOUSE_INCOME_TAX'));
    const constitutionalTaxProvenance = Object.fromEntries(Object.entries(constitution.provenance).filter(([code]) => code.includes('.TAX') || code === 'EARTH.HOUSE_INCOME_TAX' || code === 'CORPORATION.HOUSE_INCOME_TAX'));
    const activeRules = Object.entries(constitutionalTaxRules).map(([code, value]) => ({
      id: constitutionalTaxVersionIds[code] ?? null,
      tax_rule_id: code,
      category: code,
      value,
      rule_version: constitutionalTaxVersionIds[code] ?? null,
      authority_type: constitutionalTaxProvenance[code] ?? 'EARTH',
      authority_id: constitutionalTaxProvenance[code] === 'CORPORATION' ? house.corporation_id : 'EARTH',
      generatedFrom: 'constitutional_rule_versions_v5',
    }));
    return toJsonSafe({ houseId: house.house_id, territoryId: house.territory_id, corporationId: house.corporation_id, gameDay: day, constitutionSnapshotId: constitution.snapshotId, constitutionalTaxRules, constitutionalTaxVersionIds, constitutionalTaxProvenance, activeRules, financialObligations: obligations.rows, taxObligations: arrears.rows, generatedFrom: 'postgres-canonical-facts' });
  });
  return result;
}
