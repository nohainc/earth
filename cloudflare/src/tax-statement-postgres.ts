import type { PostgresRepository } from './repository.ts';

export async function getTaxStatement(repository: PostgresRepository, humanId: string) {
  const result = await repository.transaction(async (tx) => {
    const house = (await tx.query<{ house_id: string; territory_id: string | null }>(`SELECT h.house_id, r.territory_id FROM humans h LEFT JOIN house_residencies r ON r.house_id = h.house_id AND r.residency_class = 'PRIMARY' AND r.status = 'ACTIVE' WHERE h.id = $1 AND h.status = 'ACTIVE' ORDER BY r.effective_from_game_day DESC LIMIT 1`, [humanId])).rows[0];
    if (!house) throw new Error('Active House is required');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const [rules, obligations, arrears] = await Promise.all([
      tx.query(`SELECT r.id, r.tax_rule_id, r.category, r.rate_bps, r.version, r.tax_base_definition, r.base_reference, r.nexus_type, r.authority_type, r.authority_id, r.beneficiary_economic_id, r.effective_from_game_day, r.effective_to_game_day FROM tax_rule_versions r WHERE r.effective_from_game_day <= $1 AND (r.effective_to_game_day IS NULL OR r.effective_to_game_day >= $1) AND (r.authority_type = 'EARTH' OR (r.authority_type = 'TERRITORY_GOVERNANCE' AND r.authority_id = $2)) ORDER BY r.category, r.version DESC`, [day, house.territory_id]),
      tx.query(`SELECT id, obligation_type, principal_due_units::TEXT, interest_due_units::TEXT, paid_units::TEXT, due_game_day, status, rule_version, nexus_type, authority_type, authority_id, base_reference FROM financial_obligations WHERE debtor_economic_id = (SELECT o.economic_id FROM owner_registry o WHERE o.id = $1 AND o.owner_type = 'HOUSE') AND obligation_type = 'TAX' ORDER BY due_game_day DESC, id DESC`, [house.house_id]),
      tx.query(`SELECT id, tax_type, tax_base_units::TEXT, amount_units::TEXT, rule_version, game_day, status, nexus_type, authority_type, authority_id, base_reference FROM tax_obligations WHERE taxpayer_economic_id = (SELECT o.economic_id FROM owner_registry o WHERE o.id = $1 AND o.owner_type = 'HOUSE') ORDER BY game_day DESC, id DESC`, [house.house_id]),
    ]);
    return { houseId: house.house_id, territoryId: house.territory_id, gameDay: day, activeRules: rules.rows, financialObligations: obligations.rows, taxObligations: arrears.rows, generatedFrom: 'postgres-canonical-facts' };
  });
  return result;
}
