import type { PostgresRepository } from './repository.ts';
import { moneyToCents } from './money.ts';

type ResearchInput = { humanId: string; buildingType: string; correlationId: string };

async function corporationForHuman(tx: PostgresRepository, humanId: string): Promise<string> {
  const membership = await tx.query<{ corporation_id: string | null }>(
    "SELECT corporation_id FROM memberships WHERE human_id = $1 AND corporation_id IS NOT NULL LIMIT 1",
    [humanId],
  );
  const corporationId = membership.rows[0]?.corporation_id;
  if (!corporationId) throw new Error('Building research is available only to corporation members');
  return corporationId;
}

function getScopeMultiplier(ownershipClass?: string): number {
  if (ownershipClass === 'public_investment') return 3.5;
  if (ownershipClass === 'civic') return 2.5;
  return 2.0;
}

function getBaseDurationDays(constructionDays: number, ownershipClass?: string): number {
  const days = Math.max(1, constructionDays);
  if (ownershipClass === 'public_investment') {
    return Math.max(14, Math.round(6 + days * 3.0));
  }
  if (ownershipClass === 'civic') {
    return Math.max(8, Math.round(5 + days * 2.2));
  }
  return Math.max(5, Math.round(3 + days * 1.8));
}

function researchCost(baseCost: number, tier: number, ownershipClass?: string): number {
  const scopeMul = getScopeMultiplier(ownershipClass);
  const tierMul = Math.pow(2.0, Math.max(0, tier - 2));
  return Math.max(1000, Math.round(Math.max(1000, baseCost) * scopeMul * tierMul));
}

function researchDurationDays(slotFootprint: number, tier: number, _ownershipClass?: string): number {
  const slots = Math.max(1, slotFootprint || 1);
  const days = (tier + 3) * slots;
  return days;
}

export async function startCorporationBuildingResearchInTransaction(tx: PostgresRepository, input: ResearchInput): Promise<Record<string, unknown>> {
    const corporationId = await corporationForHuman(tx, input.humanId);
    const prior = await tx.query(`SELECT p.* FROM corporation_research_projects p
      JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
      WHERE o.id = $1 AND p.correlation_id = $2`, [corporationId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, project: prior.rows[0], correlationId: input.correlationId };
    await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`corp-building-research:${corporationId}:${input.buildingType}`]);

    // Research progression is corporation-specific. The global catalog may
    // contain tiers researched by another corporation, but those tiers do
    // not advance this corporation's own research path.
    const unlocked = await tx.query<{ tier: string }>(
      `SELECT COALESCE(MAX(c.tier), 1)::text AS tier
       FROM corporation_building_unlocks u
       JOIN building_catalog c ON c.id = u.catalog_id
       WHERE u.corporation_id = $1
         AND u.status = 'unlocked'
         AND c.building_type = $2`,
      [corporationId, input.buildingType],
    );
    const priorTier = Number(unlocked.rows[0]?.tier ?? 1);
    const previous = await tx.query<{ id: string; tier: number; cost_credits: string; construction_days: number; slot_footprint: number; ownership_class: string }>(
      'SELECT id, tier, cost_credits, construction_days, slot_footprint, ownership_class FROM building_catalog WHERE building_type = $1 AND tier = $2 LIMIT 1',
      [input.buildingType, priorTier],
    );
    if (!previous.rows[0]) throw new Error('Building blueprint not found');
    const targetTier = priorTier + 1;
    if (targetTier > 5) throw new Error(`No predefined building tier remains after Tier ${priorTier}`);
    const targetCatalogId = `${input.buildingType}-t${targetTier}`;
    // Tiers are authored in the catalog. Research unlocks a predefined
    // blueprint; it never generates or mutates shared catalog economics.
    const targetCatalog = await tx.query(
      'SELECT * FROM building_catalog WHERE id = $1 AND building_type = $2 AND tier = $3 AND tier BETWEEN 1 AND 5',
      [targetCatalogId, input.buildingType, targetTier],
    );
    if (!targetCatalog.rows[0]) throw new Error(`Predefined Tier ${targetTier} blueprint is missing from the building catalog`);
    const existingProject = await tx.query(
      "SELECT p.* FROM corporation_research_projects p JOIN owner_registry o ON o.economic_id = p.corporation_economic_id WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' AND p.target_id = $2 AND p.status IN ('QUEUED','ACTIVE','COMPLETED') LIMIT 1",
      [corporationId, targetCatalogId],
    );
    if (existingProject.rows[0]) {
      throw new Error(`Your corporation has already researched or is researching Tier ${targetTier} for this building`);
    }
    const cost = researchCost(Number(previous.rows[0].cost_credits), targetTier, previous.rows[0].ownership_class);
    const durationDays = researchDurationDays(Number(previous.rows[0].slot_footprint ?? 1), targetTier, previous.rows[0].ownership_class);
    // The database clock is the sole source of time. Do not derive or submit
    // a client/server timestamp for research start or completion.
    const timeRes = await tx.query<{ game_day: number }>(
      'SELECT earth_game_day_from_total_minutes(total_game_minutes) AS game_day FROM earth_get_current_game_time()',
    );
    const time = timeRes.rows[0];
    if (!time) throw new Error('Authoritative game clock is unavailable');
    const projectId = `CBR-${crypto.randomUUID().slice(0, 10).toUpperCase()}`;

    const isPrivate = previous.rows[0].ownership_class === 'private';
    const payerOwnerId = isPrivate ? input.humanId : corporationId;
    const fundingAccounts = await tx.query<{ debit_account_id: string; research_account_id: string }>(`SELECT payer.id::TEXT AS debit_account_id, service.id::TEXT AS research_account_id
      FROM economic_accounts payer
      JOIN owner_registry payer_owner ON payer_owner.economic_id = payer.owner_economic_id AND payer_owner.id = $1
      JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
      JOIN economic_accounts service ON service.owner_economic_id = system_owner.economic_id
        AND service.asset_id = 1 AND service.account_type = 4 AND service.status = 'active'
      WHERE payer.asset_id = 1 AND payer.account_type IN (1, 3, 4)
        AND payer.status = 'active'
      ORDER BY payer.is_default_settlement DESC, payer.account_type, payer.id
      LIMIT 1`, [payerOwnerId]);
    if (!fundingAccounts.rows[0]) throw new Error(`V2 funding account requires ${cost} Credits for this research`);

    const corporationOwner = await tx.query<{ economic_id: string }>('SELECT economic_id::TEXT FROM owner_registry WHERE id = $1', [corporationId]);
    if (!corporationOwner.rows[0]) throw new Error('Corporation economic owner is not provisioned');
    const funding = await tx.query<{ transaction_id: string }>(
      `SELECT transaction_id FROM earth_post_transaction($1,$2,1439,'RESEARCH_FUNDING','CORPORATION_RESEARCH',$3,'building-catalog-v1',$4::jsonb)`,
      [input.correlationId, time.game_day, projectId, JSON.stringify([
        { account_id: fundingAccounts.rows[0].debit_account_id, delta: (-BigInt(Math.round(cost * 100))).toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
        { account_id: fundingAccounts.rows[0].research_account_id, delta: BigInt(Math.round(cost * 100)).toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
      ])],
    );
    if (!funding.rows[0]?.transaction_id) throw new Error('Research funding transaction was not created');
    await tx.query(`INSERT INTO corporation_research_projects
      (id, corporation_economic_id, target_type, target_id, definition_version,
       required_research_points, progress_research_points, credit_cost_units,
       priority, status, started_game_day, funding_transaction_id, correlation_id)
      VALUES ($1,$2,'BUILDING_BLUEPRINT',$3,'building-catalog-v1',$4,0,$5,100,'ACTIVE',$6,$7,$8)
      ON CONFLICT (id) DO NOTHING`,
      [projectId, corporationOwner.rows[0].economic_id, targetCatalogId, durationDays * 100, Math.round(cost * 100), time.game_day, funding.rows[0].transaction_id, input.correlationId]);
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_research_projects WHERE id = $1', [projectId])).rows[0], catalogId: targetCatalogId, correlationId: input.correlationId };
}

export async function startCorporationBuildingResearch(repository: PostgresRepository, input: ResearchInput): Promise<Record<string, unknown>> {
  return repository.transaction((tx) => startCorporationBuildingResearchInTransaction(tx, input));
}

export async function listCorporationBuildingResearch(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const membership = await repository.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1 LIMIT 1', [humanId]);
  const corporationId = membership.rows[0]?.corporation_id;
  if (!corporationId) return { corporationId: null, projects: [], unlocks: [] };
  const [projects, unlocks] = await Promise.all([
    repository.query(`SELECT p.*, c.name AS catalog_name FROM corporation_research_projects p
      JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
      JOIN building_catalog c ON c.id = p.target_id
      WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' ORDER BY p.created_at DESC`, [corporationId]),
    repository.query('SELECT u.*, c.name AS catalog_name, c.building_type, c.tier FROM corporation_building_unlocks u JOIN building_catalog c ON c.id = u.catalog_id WHERE u.corporation_id = $1 AND u.status = \'unlocked\' ORDER BY c.building_type, c.tier', [corporationId]),
  ]);
  return { corporationId, projects: projects.rows, unlocks: unlocks.rows };
}

export async function advanceCorporationBuildingResearch(repository: PostgresRepository): Promise<number> {
  const advanced = await repository.query<{ completed: number }>(
    'SELECT earth_advance_corporation_building_research() AS completed',
  );
  return Number(advanced.rows[0]?.completed ?? 0);
}
