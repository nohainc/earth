import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { runEconomicMutation, postEconomicTransaction } from './settlement-barrier-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { applyConditionStack } from './world-conditions.ts';
import { quoteV5HouseCapacityChange } from './v5-capacity-postgres.ts';
import { refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';

export type TerritoryCapacity = {
  territory_id: string;
  game_day: number;
  active_house_count: number;
  house_capacity: number;
  population_capacity: number;
  private_slot_capacity: number;
  public_slot_capacity: number;
  private_slots_used: number;
  public_slots_used: number;
  housing_capacity: number;
  health_capacity: number;
  energy_capacity: number;
  connectivity_capacity: number;
  service_capacity: Record<string, number>;
};

export async function getTerritoryCapacity(repository: PostgresRepository, territoryId: string): Promise<Record<string, unknown>> {
  const territory = await repository.query(`SELECT t.id, t.corporation_id, t.name, t.territory_type, t.status, t.is_primary,
    i.name AS corporation_name
    FROM territories t
    LEFT JOIN institutions i ON i.id = t.corporation_id
    WHERE t.id = $1`, [territoryId]);
  if (!territory.rows[0]) throw new Error('Territory not found');
  const state = await repository.query<TerritoryCapacity>('SELECT * FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
  const infrastructure = await repository.query(`SELECT b.status, c.code, c.ownership_scope,
      COUNT(*)::INTEGER AS building_count,
      COALESCE(SUM(c.slot_footprint), 0)::BIGINT AS slot_footprint
    FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id
    WHERE b.territory_id = $1 AND b.status <> 'DESTROYED'
    GROUP BY b.status, c.code, c.ownership_scope
    ORDER BY b.status, c.code`, [territoryId]);
  const capacity = state.rows[0] ?? null;
  return {
    territory: territory.rows[0],
    capacity,
    infrastructure: infrastructure.rows,
    services: capacity?.service_capacity ?? {},
    generatedFrom: 'postgres-canonical-facts',
  };
}

type ConstructionRequirement = { code: string; asset_id: number; required_units: string; available_units: string; missing_units: string };

export async function effectiveConstructionMinutes(tx: PostgresRepository, day: number, territoryId: string | null, buildingCode: string, baseMinutes: number): Promise<{ minutes: number; modifiersBps: number[]; modifierDetails: Record<string, unknown>[] }> {
  const corporationId = (await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM territories WHERE id = $1', [territoryId])).rows[0]?.corporation_id ?? null;
  const conditions = await tx.query<{ scope_type: string; scope_id: string | null; effect_type: string; target_key: string; modifier_bps: number }>(`SELECT condition.scope_type, condition.scope_id, effect.effect_type, effect.target_key, effect.modifier_bps
    FROM world_conditions condition
    JOIN world_condition_effects effect ON effect.condition_id = condition.id
   WHERE effect.effect_type IN ('CONSTRUCTION_INDEX', 'LABOR_INDEX') AND condition.effective_from_game_day <= $1
     AND (condition.effective_to_game_day IS NULL OR condition.effective_to_game_day >= $1)
     AND (condition.scope_type = 'EARTH' OR (condition.scope_type = 'CORPORATION' AND condition.scope_id = $2))
     AND (effect.target_key = '*' OR upper(effect.target_key) = upper($3))
   ORDER BY condition.scope_type, condition.scope_id NULLS FIRST, effect.target_key, effect.id`, [day, corporationId, buildingCode]);
  const modifiersBps = conditions.rows.map((condition) => Number(condition.modifier_bps));
  const modifierDetails = conditions.rows.map((condition) => ({ effectType: condition.effect_type, scopeType: condition.scope_type, scopeId: condition.scope_id, targetKey: condition.target_key, modifierBps: Number(condition.modifier_bps) }));
  const minutes = Number(applyConditionStack(BigInt(baseMinutes), modifiersBps));
  return { minutes: Math.max(1, minutes), modifiersBps, modifierDetails };
}

export async function loadConstructionRequirements(
  tx: PostgresRepository,
  catalogId: string,
  ownerEconomicId: string,
  isPublic: boolean,
): Promise<ConstructionRequirement[]> {
  const rows = await tx.query<{ code: string; asset_id: number; required_units: string; available_units: string }>(
    `SELECT asset.code, asset.id AS asset_id, flow.construction_units::TEXT AS required_units,
            COALESCE(account.balance_units, 0)::TEXT AS available_units
       FROM building_catalog_resource_flows flow
       JOIN economic_assets asset ON asset.id = flow.asset_id AND asset.asset_kind = 'RESOURCE'
       LEFT JOIN economic_accounts account
         ON account.owner_economic_id = $2 AND account.asset_id = flow.asset_id
        AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE flow.catalog_id = $1 AND flow.construction_units > 0
      ORDER BY asset.id`, [catalogId, ownerEconomicId],
  );
  if (isPublic) return [];
  return rows.rows.map((row) => {
    const required = BigInt(row.required_units);
    const available = BigInt(row.available_units);
    return { ...row, missing_units: (required > available ? required - available : 0n).toString() };
  });
}

export async function getConstructionQuote(
  repository: PostgresRepository,
  input: { ownerId: string; territoryId: string; buildingType: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const territory = (await tx.query<{ corporation_id: string }>("SELECT corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE'", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    const owner = (await tx.query<{ house_id: string; economic_id: string }>(
      `SELECT h.house_id, o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
        WHERE h.id = $1 AND h.status = 'ACTIVE'`, [input.ownerId])).rows[0];
    if (!owner) throw new Error('House economic owner not found');
    const catalog = (await tx.query<{ id: string; code: string; ownership_scope: 'PRIVATE' | 'PUBLIC'; construction_credit_units: string; construction_minutes: number }>(
      `SELECT id, code, ownership_scope, construction_credit_units, construction_minutes FROM building_catalog
        WHERE (id = $1 OR code = $1 OR lower(code) = lower($1)) LIMIT 1`, [input.buildingType])).rows[0];
    if (!catalog) throw new Error('Unknown building blueprint');
    const isPublic = catalog.ownership_scope === 'PUBLIC';
    if (isPublic) {
      const membership = (await tx.query("SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [owner.house_id, territory.corporation_id])).rows[0];
      if (!membership) throw new Error('House must belong to the governing Corporation for public construction');
    }
    const economicOwner = isPublic ? (await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'CORPORATION'", [territory.corporation_id])).rows[0]?.economic_id : owner.economic_id;
    if (!economicOwner) throw new Error(`${isPublic ? 'Corporation' : 'House'} economic owner not found`);
    const credit = (await tx.query<{ balance_units: string }>(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE'`, [economicOwner, isPublic ? 'TREASURY' : 'WALLET'])).rows[0]?.balance_units ?? '0';
    const requirements = await loadConstructionRequirements(tx, catalog.id, economicOwner, isPublic);
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const duration = await effectiveConstructionMinutes(tx, day, input.territoryId, catalog.code, catalog.construction_minutes);
    return {
      catalog: { id: catalog.id, code: catalog.code, ownershipScope: catalog.ownership_scope, constructionMinutes: catalog.construction_minutes, effectiveConstructionMinutes: duration.minutes, constructionIndexModifiersBps: duration.modifiersBps, conditionModifiers: duration.modifierDetails },
      requirements: {
        CREDIT: { required_units: catalog.construction_credit_units, available_units: credit, missing_units: (BigInt(catalog.construction_credit_units) > BigInt(credit) ? BigInt(catalog.construction_credit_units) - BigInt(credit) : 0n).toString() },
        ...Object.fromEntries(requirements.map((item) => [item.code, { required_units: item.required_units, available_units: item.available_units, missing_units: item.missing_units }])),
      },
      v5Capacity: catalog.ownership_scope === 'PRIVATE'
        ? await quoteV5HouseCapacityChange(tx, owner.house_id, BigInt(catalog.slot_footprint), day)
        : null,
    };
  });
}

export async function purchaseBuildingInTerritory(
  repository: PostgresRepository,
  input: { ownerId: string; territoryId: string; buildingType: string; name: string; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]?.source_id) return { ok: true, alreadyProcessed: true, building: (await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.rows[0].source_id])).rows[0], correlationId: input.correlationId };

    const territory = (await tx.query<{ id: string; corporation_id: string }>("SELECT id, corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    const owner = (await tx.query<{ house_id: string; economic_id: string }>(
      `SELECT h.house_id, o.economic_id
         FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
        WHERE h.id = $1 AND h.status = 'ACTIVE'`, [input.ownerId],
    )).rows[0];
    if (!owner) throw new Error('House economic owner not found');
    const catalog = (await tx.query<{ id: string; code: string; ownership_scope: 'PRIVATE' | 'PUBLIC'; construction_credit_units: string; construction_minutes: number; slot_footprint: number; service_type: string | null }>(
      `SELECT id, code, ownership_scope, construction_credit_units, construction_minutes, slot_footprint, service_type FROM building_catalog
        WHERE (id = $1 OR code = $1 OR lower(code) = lower($1)) LIMIT 1`, [input.buildingType],
    )).rows[0];
    if (!catalog) throw new Error('Unknown building blueprint');
    const isPublic = catalog.ownership_scope === 'PUBLIC';
    if (isPublic) {
      const membership = (await tx.query(
        "SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [owner.house_id, territory.corporation_id],
      )).rows[0];
      if (!membership) throw new Error('House must belong to the governing Corporation for public construction');
      const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1`, [territory.corporation_id])).rows[0];
      if (['EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency?.status ?? '')) throw new Error('Corporation capacity delinquency blocks public expansion');
    }
    const ownerEconomicId = isPublic
      ? (await tx.query<{ economic_id: string }>(
        `SELECT o.economic_id FROM owner_registry o
          WHERE o.id = $1 AND o.owner_type = 'CORPORATION'`, [territory.corporation_id],
      )).rows[0]?.economic_id
      : owner.economic_id;
    if (!ownerEconomicId) throw new Error(`${isPublic ? 'Corporation' : 'House'} economic owner not found`);
    const clock = await readAuthoritativeGameTime(tx);
    const gameDay = clock.gameDay;
    const duration = await effectiveConstructionMinutes(tx, gameDay, input.territoryId, catalog.code, catalog.construction_minutes);
    const v5CapacityQuote = !isPublic
      ? await quoteV5HouseCapacityChange(tx, owner.house_id, BigInt(catalog.slot_footprint), gameDay)
      : null;
    if (!isPublic && v5CapacityQuote?.available === true) {
      const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [owner.house_id])).rows[0];
      if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED'].includes(delinquency?.status ?? '')) {
        throw new Error('House capacity delinquency blocks new private capacity');
      }
    }
    const territoryRight = !isPublic
      ? (await tx.query<{ id: string; slot_quantity: string }>(
        `SELECT id, slot_quantity::TEXT
           FROM territory_rights
          WHERE territory_id = $1 AND holder_type = 'HOUSE' AND holder_id = $2
            AND slot_class = 'PRIVATE' AND status IN ('ACTIVE','HOLDOVER')
            AND effective_from_game_day <= $3
            AND (effective_to_game_day IS NULL OR effective_to_game_day >= $3)
          ORDER BY effective_to_game_day NULLS LAST, id
          LIMIT 1 FOR UPDATE`, [input.territoryId, owner.house_id, gameDay],
      )).rows[0]
      : null;
    if (!isPublic && (!territoryRight || BigInt(territoryRight.slot_quantity) < BigInt(catalog.slot_footprint))) {
      throw new Error('An active private Territory use right with sufficient slots is required');
    }
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [input.territoryId, gameDay]);
    const projection = (await tx.query<{ private_slot_capacity: string; private_slots_used: string; public_slot_capacity: string; public_slots_used: string }>(
      'SELECT private_slot_capacity, private_slots_used, public_slot_capacity, public_slots_used FROM territory_capacity_state WHERE territory_id = $1 FOR UPDATE', [input.territoryId],
    )).rows[0];
    if (!projection) throw new Error('Territory capacity projection is unavailable');
    const availableSlots = isPublic
      ? Number(projection.public_slot_capacity) - Number(projection.public_slots_used)
      : Number(projection.private_slot_capacity) - Number(projection.private_slots_used);
    if (availableSlots < Number(catalog.slot_footprint)) throw new Error(`Territory ${isPublic ? 'public' : 'private'} capacity exceeded`);
    const wallet = (await tx.query<{ id: string; balance_units: string }>(
      `SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a
        WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type = $2 AND a.status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, isPublic ? 'TREASURY' : 'WALLET'],
    )).rows[0];
    const constructionDestination = (await tx.query<{ id: string }>(
      `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND o.owner_type = 'SYSTEM'
          AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`,
    )).rows[0];
    const cost = BigInt(catalog.construction_credit_units);
    if (!wallet || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for construction');
    if (!constructionDestination) throw new Error('Construction settlement destination is not configured');
    const constructionRequirements = await loadConstructionRequirements(tx, catalog.id, ownerEconomicId, isPublic);
    const missing = constructionRequirements.find((item) => BigInt(item.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for construction; missing ${missing.missing_units}`);
    const resourceAccounts = await Promise.all(constructionRequirements.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>(
        `SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, item.asset_id])).rows[0],
      sink: (await tx.query<{ id: string }>(
        `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
          WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'`, [item.asset_id])).rows[0],
    })));
    if (resourceAccounts.some((item) => !item.account || !item.sink)) throw new Error('Construction resource settlement accounts are not provisioned');
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'ASSET_TRANSFER',
      sourceType: isPublic ? 'PUBLIC_INFRASTRUCTURE_CONSTRUCTION' : 'PRIVATE_CONSTRUCTION',
      sourceId: buildingId,
      rulesVersion: 'construction-credit-v1',
      entries: [
        { account_id: wallet.id, delta_units: (-cost).toString(), asset_id: 1 },
        { account_id: constructionDestination.id, delta_units: cost.toString(), asset_id: 1 },
      ],
    }, clock);
    if (resourceAccounts.length) {
      await postEconomicTransaction(tx, {
        correlationId: `construction:${input.correlationId}:resources`,
        kind: 'RESOURCE_CONSUMPTION',
        sourceType: 'SYSTEM_CONSUMPTION',
        sourceId: buildingId,
        rulesVersion: 'building-territory-v3',
        entries: resourceAccounts.flatMap((item) => [
          { account_id: item.account!.id, asset_id: item.asset_id, delta_units: (-BigInt(item.required_units)).toString(), reason_code: 'private_construction_resource_input' },
          { account_id: item.sink!.id, asset_id: item.asset_id, delta_units: BigInt(item.required_units).toString(), reason_code: 'private_construction_resource_input' },
        ]),
      }, clock);
    }
    await tx.query(
      `INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, started_game_day, commissioned_game_day, territory_right_id)
       VALUES ($1, $2, $3, $4, 'UNDER_CONSTRUCTION', $5, NULL, $6)`, [buildingId, ownerEconomicId, input.territoryId, catalog.id, gameDay, territoryRight?.id ?? null],
    );
    if (!isPublic) await refreshV5SettlementProfilesForHouse(tx, owner.house_id, gameDay);
    const expectedCompletionGameDay = gameDay + Math.max(1, Math.ceil(duration.minutes / 1440));
    await tx.query(
      `INSERT INTO construction_projects
        (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,$9,'IN_PROGRESS',$10,$11)`,
      [`PROJECT-${buildingId.slice(4)}`, buildingId, ownerEconomicId, input.territoryId, catalog.id, cost.toString(), JSON.stringify(Object.fromEntries(constructionRequirements.map((item) => [item.code, item.required_units]))), gameDay, expectedCompletionGameDay, input.correlationId, territoryRight?.id ?? null],
    );
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [input.territoryId, gameDay]);
    await createGameEvent(tx, {
      id: `BUILDING-ACQUIRED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_ACQUIRED', gameDay,
      actorHumanId: input.ownerId, subjectType: 'BUILDING', subjectId: buildingId,
      title: `${catalog.code} acquired in Territory`,
      details: { buildingId, catalogId: catalog.id, territoryId: input.territoryId, ownerEconomicId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE', constructionIndexModifiersBps: duration.modifiersBps, conditionModifiers: duration.modifierDetails, effectiveConstructionMinutes: duration.minutes },
      correlationId: input.correlationId,
    });
    return { ok: true, status: 'UNDER_CONSTRUCTION', project: (await tx.query('SELECT * FROM construction_projects WHERE building_id = $1', [buildingId])).rows[0], building: (await tx.query('SELECT * FROM buildings WHERE id = $1', [buildingId])).rows[0], ownerType: isPublic ? 'CORPORATION' : 'HOUSE', capacity: (await tx.query('SELECT * FROM territory_capacity_state WHERE territory_id = $1', [input.territoryId])).rows[0], v5Capacity: v5CapacityQuote, correlationId: input.correlationId };
  });
}

export async function listConstructionProjects(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT p.*, b.catalog_id, c.code, b.status AS building_status
    FROM construction_projects p JOIN buildings b ON b.id = p.building_id JOIN building_catalog c ON c.id = b.catalog_id
    WHERE p.owner_economic_id = (SELECT o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id WHERE h.id = $1)
    ORDER BY p.started_game_day DESC, p.id`, [humanId]);
  return { projects: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function cancelConstructionProject(repository: PostgresRepository, humanId: string, projectId: string, correlationId: string): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const project = (await tx.query<{ id: string; building_id: string; owner_economic_id: string; credit_cost_units: string; cancellation_refund_bps: number; status: string }>(
      `SELECT p.id, p.building_id, p.owner_economic_id, p.credit_cost_units::TEXT, p.cancellation_refund_bps, p.status
         FROM construction_projects p JOIN humans h ON h.house_id = (SELECT id FROM owner_registry WHERE economic_id = p.owner_economic_id)
        WHERE p.id = $1 AND h.id = $2 AND h.status = 'ACTIVE' FOR UPDATE`, [projectId, humanId],
    )).rows[0];
    if (!project) throw new Error('Construction project not found');
    if (project.status !== 'IN_PROGRESS') return { ok: true, alreadyProcessed: true, status: project.status, projectId, correlationId };
    const day = clock.gameDay;
    const refund = BigInt(project.credit_cost_units) * BigInt(project.cancellation_refund_bps) / 10_000n;
    if (refund > 0n) {
      const source = (await tx.query<{ id: string }>(`SELECT a.id::TEXT AS id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
      const destination = (await tx.query<{ id: string }>(`SELECT a.id::TEXT AS id FROM economic_accounts a WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' LIMIT 1`, [project.owner_economic_id])).rows[0];
      if (!source || !destination) throw new Error('Construction refund accounts are not provisioned');
      await postEconomicTransaction(tx, {
        correlationId,
        kind: 'ASSET_TRANSFER',
        sourceType: 'CONSTRUCTION_CANCEL',
        sourceId: projectId,
        rulesVersion: 'construction-project-v1',
        entries: [
          { account_id: source.id, asset_id: 1, delta_units: (-refund).toString() },
          { account_id: destination.id, asset_id: 1, delta_units: refund.toString() },
        ],
      }, clock);
    }
    await tx.query(`UPDATE construction_projects SET status='CANCELLED', cancelled_game_day=$2, updated_at=CURRENT_TIMESTAMP WHERE id=$1`, [projectId, day]);
    await tx.query(`UPDATE buildings SET status='INACTIVE' WHERE id=$1`, [project.building_id]);
    const owner = (await tx.query<{ id: string; owner_type: 'HOUSE' | 'CORPORATION' }>(
      'SELECT id, owner_type FROM owner_registry WHERE economic_id = $1', [project.owner_economic_id],
    )).rows[0];
    if (owner?.owner_type === 'HOUSE') await refreshV5SettlementProfilesForHouse(tx, owner.id, day);
    await createGameEvent(tx, { id: `PROJECT-CANCELLED-${correlationId}`, category: 'BUILDING', eventType: 'CONSTRUCTION_CANCELLED', gameDay: day, actorHumanId: humanId, subjectType: 'CONSTRUCTION_PROJECT', subjectId: projectId, title: 'Construction project cancelled', details: { projectId, refundUnits: refund.toString() }, correlationId });
    return { ok: true, status: 'CANCELLED', projectId, refundUnits: refund.toString(), correlationId };
  });
}
