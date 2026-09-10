import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';

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
    const prior = await tx.query('SELECT * FROM corporation_building_research_projects WHERE corporation_id = $1 AND correlation_id = $2', [corporationId, input.correlationId]);
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
    const targetCatalogId = `${input.buildingType}-t${targetTier}`;
    // Serialize global catalog creation across corporations. Each corporation
    // still has its own research project, but only one shared blueprint row
    // may ever be created for a building type and tier.
    await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`building-catalog:${input.buildingType}:${targetTier}`]);
    const existingCatalog = await tx.query('SELECT * FROM building_catalog WHERE id = $1', [targetCatalogId]);
    const existingProject = await tx.query(
      "SELECT * FROM corporation_building_research_projects WHERE corporation_id = $1 AND catalog_id = $2 AND status IN ('active','paused','completed') LIMIT 1",
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
    let debitAccountId: string;

    if (isPrivate) {
      const personalAccount = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [input.humanId],
      );
      if (!personalAccount.rows[0] || moneyToCents(personalAccount.rows[0].balance) < moneyToCents(cost)) {
        throw new Error(`Personal account requires ${cost} Credits for this research`);
      }
      debitAccountId = personalAccount.rows[0].account_id;
    } else {
      const corporation = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [`account-corporation-${corporationId}`],
      );
      if (!corporation.rows[0] || moneyToCents(corporation.rows[0].balance) < moneyToCents(cost)) {
        throw new Error(`Corporation Treasury requires ${cost} Credits for this research`);
      }
      debitAccountId = corporation.rows[0].account_id;
    }

    if (!existingCatalog.rows[0]) {
      await tx.query(
        `INSERT INTO building_catalog (
          id, building_type, name, tier, prev_catalog_id, category, ownership_class, slot_footprint,
          cost_credits, cost_energy, cost_food, cost_materials, cost_components, cost_compute,
          output_credits, output_energy, output_food, output_materials, output_components, output_compute,
          upkeep_credits, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
          operating_credits, operating_energy, operating_food, operating_materials, operating_components, operating_compute,
          description, construction_days, construction_minutes, is_active, research_project_id
        )
        SELECT $1, building_type, name || ' · Tier ' || $2::text, $2::integer, id, category, ownership_class, slot_footprint,
          cost_credits * 1.70, cost_energy * 1.70, cost_food * 1.70, cost_materials * 1.70, cost_components * 1.70, cost_compute * 1.70,
          output_credits * 1.25, output_energy * 1.25, output_food * 1.25, output_materials * 1.25, output_components * 1.25, output_compute * 1.25,
          upkeep_credits * 1.12, upkeep_energy * 1.12, upkeep_food * 1.12, upkeep_materials * 1.12, upkeep_components * 1.12, upkeep_compute * 1.12,
          operating_credits * 1.12, operating_energy * 1.12, operating_food * 1.12, operating_materials * 1.12, operating_components * 1.12, operating_compute * 1.12,
          COALESCE(description, '') || ' Researched Tier ' || $2::text || ' generation.', GREATEST(1, slot_footprint * $2::integer), GREATEST(1440, slot_footprint * $2::integer * 1440), false, $3
        FROM building_catalog WHERE id = $4`,
        [targetCatalogId, targetTier, projectId, previous.rows[0].id],
      );
      await tx.query('UPDATE building_catalog SET next_catalog_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [targetCatalogId, previous.rows[0].id]);
    }

    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: time.game_day, debitAccount: debitAccountId, creditAccount: 'account-research-registry', amount: centsToMoney(moneyToCents(cost)), reasonType: 'corporation_building_research', reasonId: projectId, ruleVersion: 'corporation-building-research-v1', correlationId: input.correlationId });
    await tx.query(
      `INSERT INTO corporation_building_research_projects (id, corporation_id, building_type, catalog_id, target_tier, research_cost_credits, duration_minutes, started_game_day, started_game_minute, research_start_day, research_duration_days, research_due_end_day, correlation_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,$9,$10,$11,$12)`,
      [projectId, corporationId, input.buildingType, targetCatalogId, targetTier, cost, durationDays * 1440, time.game_day, time.game_day + 1, durationDays, time.game_day + durationDays, input.correlationId],
    );
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_building_research_projects WHERE id = $1', [projectId])).rows[0], catalogId: targetCatalogId, correlationId: input.correlationId };
}

export async function startCorporationBuildingResearch(repository: PostgresRepository, input: ResearchInput): Promise<Record<string, unknown>> {
  return repository.transaction((tx) => startCorporationBuildingResearchInTransaction(tx, input));
}

export async function listCorporationBuildingResearch(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const membership = await repository.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1 LIMIT 1', [humanId]);
  const corporationId = membership.rows[0]?.corporation_id;
  if (!corporationId) return { corporationId: null, projects: [], unlocks: [] };
  const [projects, unlocks] = await Promise.all([
    repository.query('SELECT p.*, c.name AS catalog_name FROM corporation_building_research_projects p JOIN building_catalog c ON c.id = p.catalog_id WHERE p.corporation_id = $1 ORDER BY p.created_at DESC', [corporationId]),
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
