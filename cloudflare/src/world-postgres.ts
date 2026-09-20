import type { PostgresRepository } from './repository.ts';
import { listCommunities } from './communities-postgres.ts';
import { listWorldConditions } from './world-conditions-postgres.ts';
import { listRankings } from './rankings-postgres.ts';
import { listOrganizations } from './organizations-postgres.ts';
import { getDecisionQueue } from './decision-queue-postgres.ts';
import { listTechnology } from './read-postgres.ts';
import { listCorporationBuildingResearch } from './corporation-building-research-postgres.ts';
import { assetUnitScale, MARKET_BATCH_GAME_MINUTES } from './market-model.ts';
import { priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { marketFeeRate } from './market-rules.ts';
import { getConstitutionReadModel } from './constitutional-kernel-postgres.ts';
import { getHouseSettlementProfileSnapshot, getCorporationSettlementProfileSnapshot } from './v5-settlement-profiles-postgres.ts';
import { getAvailableScaleCapabilities } from './v5-scale-postgres.ts';
import { readAuthoritativeGameTime, getSettlementCursor } from './world-clock-postgres.ts';
import { corporationPoliciesFromConstitution, corporationProfileFromSource } from './corporation-profile.ts';
import { getInstitutionFinancialProjection } from './financial-projections.ts';
import type { HumanProfile } from './human-profile.ts';
import type { HumanAuthoritySummary } from './human-authority-summary.ts';
import { buildingPortfolio } from './building-contract.ts';
import { readMarketOrderRows, serializeMarketOrder } from './market-order-read-model.ts';

/** PostgreSQL BIGINT values must have one explicit JSON wire representation. */
function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  }
  return value;
}

export async function worldSnapshot(repository: PostgresRepository, viewerId?: string, viewerHouseId?: string): Promise<Record<string, unknown>> {
  const clock = await readAuthoritativeGameTime(repository);
  const [cursor, world, institutions, humans, assets, communities, serviceAssessments, conditions, viewer, dailyMaintenance, personalRoles, lifeEvents, catalog, buildings, corporationBuildings, corporationBuildingPermissions, accounts, residency, obligations, proposals, rankings, territories, corporation, organizations, governanceRules, taxRules] = await Promise.all([
    getSettlementCursor(repository, clock.gameDay),
    repository.query("SELECT id, world_seed, status, genesis_at FROM world_state WHERE id = 'WORLD'"),
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query("SELECT id, house_id, display_name, age_years, standing, final_legacy, status FROM humans WHERE status = 'ACTIVE' ORDER BY id"),
    repository.query('SELECT code, asset_kind FROM economic_assets ORDER BY id'),
    listCommunities(repository, viewerHouseId, 'mine'),
    viewerHouseId ? repository.query<{ need_code: string; risk_level: string; game_day: number }>(`SELECT need_code, risk_level, game_day FROM house_need_assessments WHERE house_id = $1 ORDER BY game_day DESC, need_code`, [viewerHouseId]) : Promise.resolve({ rows: [] as { need_code: string; risk_level: string; game_day: number }[] }),
    listWorldConditions(repository, clock.gameDay, viewerHouseId),
    viewerId ? repository.query(`SELECT h.id, h.house_id, h.display_name, h.epitaph, h.birth_game_day, h.age_years, h.standing, h.final_legacy, h.status,
                                        hs.house_name, hs.motto, hs.generation, hs.dynasty_legacy
                                   FROM humans h JOIN houses hs ON hs.id = h.house_id
                                  WHERE h.id = $1`, [viewerId]) : Promise.resolve({ rows: [] }),
    viewerId ? repository.query(`SELECT game_day, food_required_units::TEXT, food_consumed_units::TEXT,
                                        food_shortfall_units::TEXT, energy_required_units::TEXT,
                                        energy_consumed_units::TEXT, energy_shortfall_units::TEXT, status
                                   FROM personal_life_maintenance
                                  WHERE human_id = $1
                                  ORDER BY game_day DESC
                                  LIMIT 1`, [viewerId]) : Promise.resolve({ rows: [] }),
    viewerId ? repository.query(`SELECT i.kind AS institution_type, r.institution_id,
                                        r.role_code AS code,
                                        CASE r.role_code
                                          WHEN 'CORPORATION_EXECUTIVE' THEN 'Corporation Executive'
                                          WHEN 'CORPORATION_TREASURER' THEN 'Corporation Treasurer'
                                          WHEN 'CORPORATION_OPERATOR' THEN 'Corporation Operator'
                                          ELSE r.role_code END AS name,
                                        i.name AS institution_name,
                                        r.effective_from_game_day
                                   FROM institution_governance_roles r
                                   JOIN institutions i ON i.id = r.institution_id
                                  WHERE r.human_id = $1
                                    AND r.status = 'ACTIVE'
                                    AND i.kind IN ('EARTH', 'CORPORATION')
                                  ORDER BY r.role_code`, [viewerId]) : Promise.resolve({ rows: [] }),
    viewerId ? repository.query(`SELECT game_day, title, event_type, details
                                   FROM game_events
                                  WHERE actor_human_id = $1 AND category = 'LIFECYCLE'
                                  ORDER BY game_day DESC, game_minute DESC NULLS LAST
                                  LIMIT 8`, [viewerId]) : Promise.resolve({ rows: [] }),
    repository.query(`SELECT c.id, c.code, c.name, c.description, c.category,
                             c.code AS building_type, c.family_code, c.tier, c.tier_formula_version,
                             c.economic_role, c.ownership_scope, lower(c.ownership_scope) AS ownership_class,
                             c.construction_credit_units, c.construction_minutes,
                             c.research_credit_units, c.research_duration_game_days,
                             c.operating_credit_units, c.service_type, c.service_capacity_units,
                             c.slot_footprint, c.definition_version, c.technology_domain, c.minimum_scale_capability,
                             COALESCE(jsonb_agg(jsonb_build_object(
                               'assetCode', a.code,
                               'constructionUnits', f.construction_units::TEXT,
                               'operatingInputUnits', f.operating_input_units::TEXT,
                               'operatingOutputUnits', f.operating_output_units::TEXT
                             ) ORDER BY a.code) FILTER (WHERE f.asset_id IS NOT NULL), '[]'::jsonb) AS resource_flows
                        FROM building_catalog c
                        LEFT JOIN building_catalog_resource_flows f ON f.catalog_id = c.id
                        LEFT JOIN economic_assets a ON a.id = f.asset_id
                       GROUP BY c.id, c.code, c.name, c.description, c.category, c.family_code, c.tier, c.tier_formula_version,
                                c.economic_role, c.ownership_scope, c.construction_credit_units,
                                c.construction_minutes, c.research_credit_units, c.research_duration_game_days,
                                c.operating_credit_units, c.service_type,
                                c.service_capacity_units, c.slot_footprint, c.definition_version,
                                c.technology_domain, c.minimum_scale_capability
                       ORDER BY c.code, c.tier, c.id`),
    viewerHouseId ? repository.query(`SELECT b.id, b.territory_id, b.catalog_id, b.status, b.started_game_day,
                                             o.id AS owner_id, o.owner_type,
                                             b.construction_state, b.installed_generation, b.technology_definition_version,
                                             b.operating_mode,
                                             c.code, c.code AS building_type, c.family_code, c.tier, c.economic_role,
                                             c.ownership_scope, lower(c.ownership_scope) AS ownership_class,
                                             c.service_type, c.service_capacity_units, c.slot_footprint,
                                             c.operating_credit_units, c.technology_domain, c.minimum_scale_capability,
                                             COALESCE(latest.utilization_bps, 10000) AS utilization_bps,
                                             latest.game_day AS latest_settlement_game_day,
                                             latest.status AS latest_settlement_status,
                                             latest.input_units AS settlement_input_units,
                                             latest.output_units AS settlement_output_units,
                                             latest.operating_credit_units::TEXT AS settlement_operating_credit_units
                                        FROM buildings b
                                        JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        JOIN building_catalog c ON c.id = b.catalog_id
                                        LEFT JOIN LATERAL (
                                          SELECT utilization_bps, game_day, status,
                                                 input_units, output_units, operating_credit_units
                                            FROM building_settlement_journals
                                           WHERE building_id = b.id
                                           ORDER BY game_day DESC
                                           LIMIT 1
                                        ) latest ON TRUE
                                       WHERE o.id = $1
                                       ORDER BY b.status, b.id`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT
        EXISTS (SELECT 1 FROM institution_governance_roles r
                 WHERE r.institution_id = ha.corporation_id AND r.human_id = $2
                   AND r.status = 'ACTIVE'
                   AND r.role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER', 'CORPORATION_OPERATOR')) AS viewer_can_build,
        EXISTS (SELECT 1 FROM institution_governance_roles r
                 WHERE r.institution_id = ha.corporation_id AND r.human_id = $2
                   AND r.status = 'ACTIVE'
                   AND r.role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_OPERATOR')) AS viewer_can_propose,
        EXISTS (SELECT 1 FROM institution_governance_roles r
                 WHERE r.institution_id = ha.corporation_id AND r.human_id = $2
                   AND r.status = 'ACTIVE'
                   AND r.role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER', 'CORPORATION_OPERATOR')) AS viewer_can_operate,
        EXISTS (SELECT 1 FROM institution_governance_roles r
                 WHERE r.institution_id = ha.corporation_id AND r.human_id = $2
                   AND r.status = 'ACTIVE'
                   AND r.role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_OPERATOR')) AS viewer_can_upgrade,
        EXISTS (SELECT 1 FROM institution_governance_roles r
                 WHERE r.institution_id = ha.corporation_id AND r.human_id = $2
                   AND r.status = 'ACTIVE'
                   AND r.role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_OPERATOR')) AS viewer_can_retrofit
      FROM house_affiliations ha
     WHERE ha.house_id = $1 AND ha.status = 'ACTIVE'
     ORDER BY ha.joined_game_day DESC
     LIMIT 1`, [viewerHouseId, viewerId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT b.id, b.territory_id, b.catalog_id, b.status, b.started_game_day,
                                             o.id AS owner_id, o.owner_type,
                                             b.construction_state, b.installed_generation, b.technology_definition_version,
                                             b.operating_mode,
                                             c.code, c.code AS building_type, c.family_code, c.tier, c.economic_role,
                                             c.ownership_scope, lower(c.ownership_scope) AS ownership_class,
                                             c.service_type, c.service_capacity_units, c.slot_footprint,
                                             c.operating_credit_units, c.technology_domain, c.minimum_scale_capability,
                                             COALESCE(latest.utilization_bps, 10000) AS utilization_bps,
                                             latest.game_day AS latest_settlement_game_day,
                                             latest.status AS latest_settlement_status,
                                             latest.input_units AS settlement_input_units,
                                             latest.output_units AS settlement_output_units,
                                             latest.operating_credit_units::TEXT AS settlement_operating_credit_units
                                        FROM buildings b
                                        JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'CORPORATION'
                                        JOIN house_affiliations ha ON ha.corporation_id = o.id AND ha.house_id = $1 AND ha.status = 'ACTIVE'
                                        JOIN building_catalog c ON c.id = b.catalog_id AND c.ownership_scope = 'PUBLIC'
                                        LEFT JOIN LATERAL (
                                          SELECT utilization_bps, game_day, status, input_units, output_units, operating_credit_units
                                            FROM building_settlement_journals
                                           WHERE building_id = b.id
                                           ORDER BY game_day DESC
                                           LIMIT 1
                                        ) latest ON TRUE
                                       ORDER BY b.status, b.id`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT a.account_type, asset.code, a.balance_units::TEXT AS balance_units
                                        FROM economic_accounts a
                                        JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
                                        JOIN economic_assets asset ON asset.id = a.asset_id
                                       WHERE owner.id = $1 AND a.status = 'ACTIVE'
                                       ORDER BY asset.id, a.account_type`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT r.territory_id, r.residency_class, r.status, r.effective_from_game_day,
                                             t.name AS territory_name, t.corporation_id,
                                             i.name AS corporation_name
                                        FROM house_residencies r
                                        JOIN territories t ON t.id = r.territory_id
                                        LEFT JOIN institutions i ON i.id = t.corporation_id
                                       WHERE r.house_id = $1 AND r.status = 'ACTIVE'
                                       ORDER BY r.effective_from_game_day DESC`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT id, obligation_type, principal_due_units::TEXT AS principal_due_units,
                                             interest_due_units::TEXT AS interest_due_units,
                                             status, due_game_day
                                        FROM financial_obligations
                                       WHERE debtor_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)
                                         AND status IN ('DUE', 'PARTIAL', 'ARREARS')
                                       ORDER BY due_game_day, id LIMIT 100`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    repository.query(`SELECT p.*, h.display_name AS creator_name, i.name AS institution_name,
                             i.kind AS institution_kind,
                             CASE WHEN i.kind = 'WORLD' THEN 'WORLD'
                                  WHEN i.kind = 'CITY' OR c.id IS NOT NULL THEN 'TERRITORY'
                                  WHEN i.kind = 'CORPORATION' THEN 'CORPORATION'
                                  ELSE 'UNKNOWN' END AS scope,
                             COALESCE(v.support_count, 0) AS support,
                             COALESCE(v.oppose_count, 0) AS oppose,
                             COALESCE(v.abstain_count, 0) AS abstain,
                             COALESCE(v.voter_count, 0) AS cast_count,
                             0 AS eligible_voter_count,
                             b.choice AS my_vote,
                             jsonb_build_object(
                               'canVote', CASE
                                 WHEN p.status NOT IN ('OPEN', 'VOTING') THEN FALSE
                                 WHEN i.kind = 'WORLD' THEN TRUE
                                 WHEN i.kind = 'CITY' OR c.id IS NOT NULL THEN EXISTS (
                                   SELECT 1 FROM house_affiliations ha JOIN humans vh ON vh.house_id = ha.house_id
                                    WHERE vh.id = $1 AND ha.status = 'ACTIVE' AND (ha.primary_territory_id = p.institution_id OR ha.primary_territory_id = i.id))
                                 WHEN i.kind = 'CORPORATION' THEN EXISTS (
                                   SELECT 1 FROM house_affiliations ha JOIN humans vh ON vh.house_id = ha.house_id
                                    WHERE vh.id = $1 AND ha.status = 'ACTIVE' AND ha.corporation_id IN (p.institution_id, i.id))
                                 ELSE FALSE END,
                               'canPropose', FALSE,
                               'myVote', b.choice,
                               'ineligibleReason', CASE WHEN p.status NOT IN ('OPEN', 'VOTING') THEN 'Voting is not open.' ELSE NULL END
                             ) AS viewer
                        FROM proposals p
                        LEFT JOIN humans h ON h.id = p.created_by_human_id
                        LEFT JOIN institutions i ON i.id = p.institution_id
                        LEFT JOIN territories c ON c.id = COALESCE(p.target_id, p.institution_id)
                        LEFT JOIN (
                          SELECT proposal_id,
                                 COUNT(*) FILTER (WHERE LOWER(choice) = 'support') AS support_count,
                                 COUNT(*) FILTER (WHERE LOWER(choice) = 'oppose') AS oppose_count,
                                 COUNT(*) FILTER (WHERE LOWER(choice) = 'abstain') AS abstain_count,
                                 COUNT(*) AS voter_count
                            FROM ballots
                           GROUP BY proposal_id
                        ) v ON v.proposal_id = p.id
                        LEFT JOIN ballots b ON b.proposal_id = p.id
                                           AND b.cast_by_human_id = $1
                       WHERE p.status IN ('OPEN', 'VOTING', 'PASSED')
                       ORDER BY p.created_game_day DESC, p.id LIMIT 100`, [viewerId ?? null]),
    listRankings(repository),
    repository.query(`SELECT t.id, t.corporation_id, t.name, t.territory_type, t.status, t.is_primary, t.created_game_day,
                             s.house_capacity, s.active_house_count,
                             s.private_slot_capacity, s.private_slots_used,
                             i.name AS corporation_name
                        FROM territories t
                        LEFT JOIN territory_capacity_state s ON s.territory_id = t.id
                        LEFT JOIN institutions i ON i.id = t.corporation_id
                       WHERE t.status IN ('ACTIVE', 'UNGOVERNED')
                       ORDER BY t.corporation_id, t.is_primary DESC, t.id`),
    viewerHouseId
      ? repository.query(`SELECT c.id, i.name, c.status, c.charter_version, c.admission_policy,
                                 c.created_game_day,
                                 (SELECT COUNT(*)::INTEGER FROM territories t WHERE t.corporation_id = c.id AND t.status = 'ACTIVE') AS territory_count,
                                 (SELECT COUNT(*)::INTEGER FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_count,
                                 (SELECT COUNT(*)::INTEGER FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_house_count,
                                 (SELECT COUNT(*)::INTEGER FROM organization_technology_adoptions a WHERE a.organization_id = c.id AND a.status = 'ADOPTED') AS technology_count,
                                 (SELECT s.total_occupied_units::TEXT FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_occupied_capacity,
                                 (SELECT s.required_territory_units::TEXT FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_required_territory_units,
                                 (SELECT s.standard_territory_capacity_units::TEXT FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_standard_territory_capacity,
                                 COALESCE((SELECT SUM(o.assessed_units) FROM v5_capacity_obligations o WHERE o.corporation_id = c.id AND o.capacity_level = 'HOUSE' AND o.game_day = (SELECT MAX(game_day) FROM v5_capacity_obligations WHERE corporation_id = c.id AND capacity_level = 'HOUSE')), 0)::TEXT AS house_capacity_revenue_units,
                                 COALESCE((SELECT SUM(o.assessed_units) FROM v5_capacity_obligations o WHERE o.corporation_id = c.id AND o.capacity_level = 'CORPORATION' AND o.game_day = (SELECT MAX(game_day) FROM v5_capacity_obligations WHERE corporation_id = c.id AND capacity_level = 'CORPORATION')), 0)::TEXT AS earth_capacity_expense_units,
                                 COALESCE((SELECT status FROM v5_capacity_delinquency_state d WHERE d.subject_type = 'CORPORATION' AND d.subject_id = c.id), 'CURRENT') AS capacity_status,
                                 (SELECT t.name FROM territories t WHERE t.corporation_id = c.id AND t.is_primary = TRUE AND t.status = 'ACTIVE' LIMIT 1) AS primary_territory_name
                            FROM house_affiliations ha
                            JOIN corporations c ON c.id = ha.corporation_id
                            JOIN institutions i ON i.id = c.id
                           WHERE ha.house_id = $1 AND ha.status = 'ACTIVE'
                           LIMIT 1`, [viewerHouseId])
      : Promise.resolve({ rows: [] }),
    listOrganizations(repository, viewerHouseId ?? ''),
    repository.query(`SELECT id, institution_id, name, category, value_json, quorum_threshold,
                             approval_threshold, voting_period_days, implementation_delay_days,
                             version, status, created_by, effective_from_game_day, effective_to_game_day
                        FROM governance_rules
                       WHERE status IN ('active', 'superseded')
                       ORDER BY institution_id, category, version DESC, id`),
    repository.query(`SELECT scope, category, minimum_rate_bps, maximum_rate_bps,
                             allowed_tax_base_definitions, beneficiary_scope, rules_version
                        FROM tax_governance_rules
                       ORDER BY scope, category`),
  ]);
  const latestServiceDay = serviceAssessments.rows[0]?.game_day;
  const serviceStatus = Object.fromEntries(serviceAssessments.rows.filter((row) => row.game_day === latestServiceDay).map((row) => [row.need_code, row.risk_level === 'NORMAL' ? 'normal' : row.risk_level === 'WATCH' ? 'basic' : 'critical']));
  const gameDay = clock.gameDay;
  const gameMinute = clock.gameMinute;
  const constitution = await getConstitutionReadModel(repository, {
    gameDay,
    corporationId: corporation.rows[0]?.id,
  });
  const constitutionRules = (constitution.rules ?? {}) as Record<string, unknown>;
  const constitutionDefinitions = Array.isArray(constitution.definitions)
    ? constitution.definitions as Array<Record<string, unknown>>
    : [];
  const constitutionVersionIds = (constitution.versionIds ?? {}) as Record<string, unknown>;
  const constitutionProvenance = (constitution.provenance ?? {}) as Record<string, unknown>;
  const canonicalTaxRules = constitutionDefinitions
    .filter((definition) => String(definition.rule_code ?? '').includes('.TAX') || String(definition.rule_code ?? '').includes('HOUSE_INCOME_TAX'))
    .filter((definition) => constitutionRules[String(definition.rule_code)] !== undefined)
    .map((definition) => {
      const ruleCode = String(definition.rule_code);
      const source = String(constitutionProvenance[ruleCode] ?? 'EARTH');
      return {
        id: constitutionVersionIds[ruleCode] ?? null,
        rule_code: ruleCode,
        category: ruleCode,
        value_type: definition.value_type ?? null,
        value: constitutionRules[ruleCode],
        rule_version: constitutionVersionIds[ruleCode] ?? null,
        authority_type: source,
        authority_id: source === 'CORPORATION' ? corporation.rows[0]?.id ?? null : 'EARTH',
        generatedFrom: 'constitutional_rule_versions_v5',
      };
    });
  const house = viewer.rows[0] ?? null;
  const affiliatedCorporation = corporation.rows[0] ?? null;
  const humanProfile: HumanProfile | null = house
    ? {
        id: String(house.id),
        displayName: String(house.display_name ?? ''),
        epitaph: house.epitaph == null ? null : String(house.epitaph),
        houseId: String(house.house_id),
        houseName: String(house.house_name ?? ''),
        birthGameDay: house.birth_game_day == null ? null : Number(house.birth_game_day),
        ageYears: house.age_years == null ? null : Number(house.age_years),
        status: String(house.status ?? 'UNKNOWN'),
        standing: house.standing == null ? null : Number(house.standing),
        finalLegacy: house.final_legacy == null ? null : Number(house.final_legacy),
        corporationId: affiliatedCorporation?.id == null ? null : String(affiliatedCorporation.id),
        corporationName: affiliatedCorporation?.name == null ? null : String(affiliatedCorporation.name),
      }
    : null;
  const maintenance = dailyMaintenance.rows[0] ?? null;
  const humanAuthoritySummary: HumanAuthoritySummary[] = personalRoles.rows.map((row: any) => ({
    institutionType: String(row.institution_type),
    institutionId: String(row.institution_id),
    institutionName: String(row.institution_name),
    roleCode: String(row.code),
    roleName: String(row.name),
    effectiveFromDay: Number(row.effective_from_game_day),
  }));
  const humanDailyNeeds = maintenance
    ? {
        gameDay: Number(maintenance.game_day),
        foodRequiredUnits: String(maintenance.food_required_units),
        foodConsumedUnits: String(maintenance.food_consumed_units),
        foodShortfallUnits: String(maintenance.food_shortfall_units),
        energyRequiredUnits: String(maintenance.energy_required_units),
        energyConsumedUnits: String(maintenance.energy_consumed_units),
        energyShortfallUnits: String(maintenance.energy_shortfall_units),
        status: String(maintenance.status),
      }
    : null;
  const resources = Object.fromEntries(accounts.rows
    .filter((row: any) => row.code !== 'CREDIT')
    .filter((row: any) => row.account_type === 'INVENTORY')
    .map((row: any) => [String(row.code).toLowerCase(), String(row.balance_units)]));
  if (resources.material != null && resources.materials == null) resources.materials = resources.material;
  const wallet = accounts.rows.find((row: any) => row.code === 'CREDIT' && row.account_type === 'WALLET');
  const territory = residency.rows.find((row: any) => row.residency_class === 'PRIMARY') ?? residency.rows[0];
  const capacity = territory?.territory_id ? (await repository.query(`SELECT territory_id, active_house_count, house_capacity, population_capacity, private_slot_capacity, public_slot_capacity, private_slots_used, public_slots_used, housing_capacity, health_capacity, energy_capacity, connectivity_capacity, service_capacity FROM territory_capacity_state WHERE territory_id = $1`, [territory.territory_id])).rows[0] : null;
  const corpId = corporation.rows[0]?.id;
  const [
    technology,
    corporationBuildingResearch,
    marketInstruments,
    marketOrders,
    houseProfile,
    corpProfile,
    corpAccounts,
    corpFinancialProjection,
    houseOwnerEcon,
    corpOwnerEcon,
  ] = await Promise.all([
    viewerId ? listTechnology(repository, viewerId) : Promise.resolve({ catalog: [], projects: [] }),
    viewerId ? listCorporationBuildingResearch(repository, viewerId) : Promise.resolve({ corporationId: null, projects: [], unlocks: [] }),
    repository.query(`SELECT i.id, i.symbol, i.asset_id, i.rules_version, i.genesis_reference_price_units::TEXT,
                             s.last_clearing_price_units::TEXT, s.best_bid_units::TEXT, s.best_ask_units::TEXT,
                             s.open_buy_units::TEXT, s.open_sell_units::TEXT, s.updated_at
                        FROM market_instruments i
                        LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
                       WHERE i.instrument_type = 'SPOT' AND i.status = 'ACTIVE'
                       ORDER BY i.symbol`),
    readMarketOrderRows(repository, { ownerRegistryId: viewerHouseId ?? '__NO_HOUSE__', statuses: ['OPEN', 'PARTIAL'] }),
    viewerHouseId ? getHouseSettlementProfileSnapshot(repository, viewerHouseId) : Promise.resolve(null),
    corpId ? getCorporationSettlementProfileSnapshot(repository, corpId) : Promise.resolve(null),
    corpId ? repository.query(`SELECT a.account_type, asset.code, a.balance_units::TEXT AS balance_units
                                FROM economic_accounts a
                                JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
                                JOIN economic_assets asset ON asset.id = a.asset_id
                               WHERE owner.id = $1 AND a.status = 'ACTIVE'
                               ORDER BY asset.id, a.account_type`, [corpId]) : Promise.resolve({ rows: [] }),
    corporation.rows[0]?.id
      ? getInstitutionFinancialProjection(repository, corporation.rows[0].id).catch(() => null)
      : Promise.resolve(null),
    viewerHouseId ? repository.query<{ economic_id: string }>(`SELECT economic_id FROM owner_registry WHERE id = $1`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    corpId ? repository.query<{ economic_id: string }>(`SELECT economic_id FROM owner_registry WHERE id = $1`, [corpId]) : Promise.resolve({ rows: [] }),
  ]);
  const houseEconId = houseOwnerEcon.rows[0]?.economic_id;
  const corpEconId = corpOwnerEcon.rows[0]?.economic_id;
  const houseScaleCaps = houseEconId
    ? Array.from(await getAvailableScaleCapabilities(repository, houseEconId, 'HOUSE', corpEconId))
    : ['SCALE_NONE'];
  const corpScaleCaps = corpEconId
    ? Array.from(await getAvailableScaleCapabilities(repository, corpEconId, 'CORPORATION', null))
    : ['SCALE_NONE'];
  const corpTreasury = (corpAccounts.rows.find((row: any) => row.code === 'CREDIT' && (row.account_type === 'TREASURY' || row.account_type === 'WALLET')) as any)?.balance_units ?? '0';
  const corpResources = Object.fromEntries(corpAccounts.rows
    .filter((row: any) => row.code !== 'CREDIT' && row.account_type === 'INVENTORY')
    .map((row: any) => [String(row.code).toLowerCase(), String(row.balance_units)]));
  if (corpResources.material != null && corpResources.materials == null) corpResources.materials = corpResources.material;
  const corporationSnapshot = corporation.rows[0] ? {
    ...corporation.rows[0],
    treasury: corpTreasury,
    treasury_units: corpTreasury,
    operations_units: String(corpAccounts.rows.find((row: any) => row.code === 'CREDIT' && row.account_type === 'OPERATIONS')?.balance_units ?? '0'),
    reserve_units: String(corpAccounts.rows.find((row: any) => row.code === 'CREDIT' && row.account_type === 'RESERVE')?.balance_units ?? '0'),
    income_tax_bps: constitutionRules['CORPORATION.TAX.INCOME_RATE'] == null ? null : Number(constitutionRules['CORPORATION.TAX.INCOME_RATE']),
    sales_tax_bps: constitutionRules['CORPORATION.TAX.SALES_RATE'] == null ? null : Number(constitutionRules['CORPORATION.TAX.SALES_RATE']),
    corporate_tax_bps: constitutionRules['CORPORATION.TAX.CORPORATE_RATE'] == null ? null : Number(constitutionRules['CORPORATION.TAX.CORPORATE_RATE']),
    property_tax_bps: constitutionRules['CORPORATION.TAX.PROPERTY_RATE'] == null ? null : Number(constitutionRules['CORPORATION.TAX.PROPERTY_RATE']),
    house_capacity_base_rate_units: constitutionRules['CORPORATION.HOUSE_CAPACITY.BASE_RATE'] == null ? null : String(constitutionRules['CORPORATION.HOUSE_CAPACITY.BASE_RATE']),
    resources: corpResources,
    settlementProfile: corpProfile,
    v5_occupied_capacity: corpProfile?.total_occupied_capacity_units ?? corporation.rows[0].v5_occupied_capacity ?? null,
    v5_required_territory_units: corporation.rows[0].v5_required_territory_units ?? null,
    v5_standard_territory_capacity: corporation.rows[0].v5_standard_territory_capacity ?? null,
    scaleCapabilities: corpScaleCaps,
  } : null;
  const corporationProfile = corporationSnapshot
    ? corporationProfileFromSource({
        ...corporationSnapshot,
        memberHouseCount: corporationSnapshot.member_house_count,
        occupiedCapacityUnits: corporationSnapshot.v5_occupied_capacity ?? '0',
        availableCapacityUnits: corpProfile
          ? String(BigInt(String(corporationSnapshot.v5_standard_territory_capacity ?? '0')) * BigInt(String(corporationSnapshot.v5_required_territory_units ?? '0')))
          : '0',
        residentialUnits: corpProfile?.member_residential_capacity_units ?? '0',
        privateProductiveUnits: corpProfile?.member_productive_capacity_units ?? '0',
        publicUnits: corpProfile?.public_capacity_units ?? '0',
        houseCapacityRevenueUnits: corporationSnapshot.house_capacity_revenue_units,
        earthCapacityExpenseUnits: corporationSnapshot.earth_capacity_expense_units,
        capacityMarginUnits: String(BigInt(String(corporationSnapshot.house_capacity_revenue_units ?? '0')) - BigInt(String(corporationSnapshot.earth_capacity_expense_units ?? '0'))),
        capacityStatus: corporationSnapshot.capacity_status,
        authorizedUnits: corpFinancialProjection?.authorizedUnits,
        committedUnits: corpFinancialProjection?.committedUnits,
        availableUnits: corpFinancialProjection?.availableUnits,
        dailyRevenueUnits: corpFinancialProjection?.revenueUnits,
        dailyExpenseUnits: corpFinancialProjection?.expenseUnits,
        requiredStandardUnits: corporationSnapshot.v5_required_territory_units ?? '0',
        standardCapacityUnits: corporationSnapshot.v5_standard_territory_capacity ?? '0',
        houseCapacityBaseRateUnits: corporationSnapshot.house_capacity_base_rate_units,
        treasuryUnits: corporationSnapshot.treasury_units,
        operationsUnits: corporationSnapshot.operations_units,
        reserveUnits: corporationSnapshot.reserve_units,
        technologyCount: corporationSnapshot.technology_count,
        rules: constitutionRules,
        provenance: constitutionProvenance,
        policies: corporationPoliciesFromConstitution(constitution),
      })
    : null;
  const marketProducts = Object.fromEntries(marketInstruments.rows.map((row: any) => {
    const product = String(row.symbol).replace(/^SPOT-/, '').toLowerCase();
    const priceUnits = row.last_clearing_price_units ?? row.genesis_reference_price_units;
    return [product, {
      product,
      price: priceUnits == null ? null : priceUnitsToDisplayPrice(String(priceUnits)),
      priceAvailable: priceUnits != null,
      bestBid: row.best_bid_units == null ? null : priceUnitsToDisplayPrice(String(row.best_bid_units)),
      bestAsk: row.best_ask_units == null ? null : priceUnitsToDisplayPrice(String(row.best_ask_units)),
      supply: unitsToDisplayQuantity(String(row.open_sell_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2))),
      demand: unitsToDisplayQuantity(String(row.open_buy_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2))),
      rulesVersion: row.rules_version,
      updatedAt: row.updated_at,
    }];
  }));
  const market = {
    products: marketProducts,
    orders: marketOrders.rows.map((row: Record<string, unknown>) => serializeMarketOrder(row)),
    feeRate: Number(await marketFeeRate(repository, viewerId)),
    reservedCredits: priceUnitsToDisplayPrice(marketOrders.rows.reduce((sum: bigint, row: Record<string, unknown>) =>
      sum + (String(row.side) === 'BUY' ? BigInt(String(row.reserved_escrow_units ?? '0')) : 0n), 0n)),
    clearingIntervalMinutes: MARKET_BATCH_GAME_MINUTES,
    nextClearingGameMinute: (gameMinute + (MARKET_BATCH_GAME_MINUTES - (gameMinute % MARKET_BATCH_GAME_MINUTES))) % 1440,
    nextClearingAbsoluteMinute: (Math.floor(clock.totalGameMinutes / MARKET_BATCH_GAME_MINUTES) + 1) * MARKET_BATCH_GAME_MINUTES,
    gameDay,
    generatedFrom: 'postgres-canonical-facts',
  };
  const needs = serviceAssessments.rows.filter((row) => row.game_day === latestServiceDay);
  const decisionQueue = viewerHouseId
    ? (await getDecisionQueue(repository, viewerHouseId, 20)).decisions
    : [];
  return toJsonSafe({
    ok: true,
    viewerId: viewerId ?? null,
    world: world.rows[0] ? { ...world.rows[0] } : null,
    clock: {
      day: clock.gameDay,
      minute: clock.gameMinute,
      totalGameMinutes: clock.totalGameMinutes,
      genesisAt: clock.genesisAt,
      serverNow: clock.serverNow,
      realSecondsPerGameMinute: clock.realSecondsPerGameMinute,
    },
    settlement: {
      settledThroughGameDay: cursor.settledThroughGameDay,
      lastClosedGameDay: cursor.lastClosedGameDay,
      backlogDays: cursor.backlogDays,
      status: cursor.status,
      failedGameDay: cursor.failedGameDay ?? null,
      failedPhase: cursor.failedPhase ?? null,
      failedError: cursor.failedError ?? null,
    },
    human: house,
    humanProfile,
    humanDailyNeeds,
    roles: personalRoles.rows,
    humanAuthoritySummary,
    recentLifeEvents: lifeEvents.rows,
    resources,
    resourceFlows: {},
    institutions: institutions.rows,
    territories: territories.rows,
    organizations: organizations['organizations'] ?? [],
    corporation: corporationSnapshot,
    corporationProfile,
    settlementProfile: houseProfile,
    scaleCapabilities: houseScaleCaps,
    humans: humans.rows,
    economicAssets: assets.rows,
    communities: communities.communities,
    serviceStatus,
    serviceNeeds: needs,
    buildings: buildings.rows,
    buildingCatalog: catalog.rows,
    buildingPortfolio: buildingPortfolio(
      buildings.rows as Record<string, unknown>[],
      corporationBuildings.rows as Record<string, unknown>[],
      catalog.rows as Record<string, unknown>[],
      corporationBuildingPermissions.rows[0] as Record<string, unknown> | undefined,
    ),
    technology: { catalog: technology.catalog, projects: technology.projects },
    corporationBuildingResearch,
    corporateResearch: technology.projects,
    market,
    finance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    taxRules: canonicalTaxRules,
    legacyTaxRules: taxRules.rows,
    personalFinance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    membership: corporation.rows[0] ? {
      territory_id: territory?.territory_id ?? null,
      territory_name: territory?.territory_name ?? null,
      residency_class: territory?.residency_class ?? null,
      corporation_id: corporation.rows[0].id,
      corporation_name: corporation.rows[0].name,
    } : territory ? {
      territory_id: territory.territory_id,
      territory_name: territory.territory_name,
      residency_class: territory.residency_class,
      corporation_id: territory.corporation_id ?? null,
      corporation_name: territory.corporation_name ?? null,
    } : null,
    governance: {
      proposals: proposals.rows,
      rules: constitution.rules,
      constitution,
      legacyRules: governanceRules.rows,
    },
    districtZoning: capacity ?? {},
    decisionQueue,
    rankings,
    worldConditions: {
      status: 'AVAILABLE',
      authoritativeGameDay: conditions.authoritativeGameDay,
      snapshotVersion: conditions.snapshotVersion,
      rulesVersion: conditions.rulesVersion,
      globalConditionCount: conditions.globalConditionCount,
      viewerApplicableConditionCount: conditions.viewerApplicableConditionCount,
      worldState: conditions.viewerApplicableConditionCount > 0 ? 'ACTIVE_CONDITIONS' : 'STABLE',
      activeConditions: conditions.conditions.filter((condition: any) => condition.appliesToViewer),
      conditions: conditions.conditions,
    },
  });
}
