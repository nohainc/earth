import type { PostgresRepository } from './repository.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';
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

function researchCost(baseCost: number, tier: number): number {
  return Math.max(1000, Math.round(Math.max(1000, baseCost) * 0.35 * Math.pow(1.7, Math.max(0, tier - 2)) * 100) / 100);
}

export async function startCorporationBuildingResearch(repository: PostgresRepository, input: ResearchInput): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
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
    const previous = await tx.query<{ id: string; tier: number; cost_credits: string; construction_days: number }>(
      'SELECT id, tier, cost_credits, construction_days FROM building_catalog WHERE building_type = $1 AND tier = $2 LIMIT 1',
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
    const cost = researchCost(Number(previous.rows[0].cost_credits), targetTier);
    const durationMinutes = Math.max(3 * 1440, Math.round(Number(previous.rows[0].construction_days ?? 1) * 1440 * 1.5));
    const world = await tx.query<{ genesis_at: string | null; simulated_day_offset: number | null }>("SELECT genesis_at, simulated_day_offset FROM world_state WHERE id = 'WORLD'");
    const time = getAuthoritativeGameTime({ genesisAt: world.rows[0]?.genesis_at, simulatedDayOffset: world.rows[0]?.simulated_day_offset });
    const projectId = `CBR-${crypto.randomUUID().slice(0, 10).toUpperCase()}`;

    const corporation = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [`account-corporation-${corporationId}`],
    );
    if (!corporation.rows[0] || moneyToCents(corporation.rows[0].balance) < moneyToCents(cost)) throw new Error(`Corporation Treasury requires ${cost} Credits for this research`);

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
        SELECT $1, building_type, name || ' · Tier ' || $2, $2, id, category, ownership_class, slot_footprint,
          cost_credits * 1.70, cost_energy * 1.70, cost_food * 1.70, cost_materials * 1.70, cost_components * 1.70, cost_compute * 1.70,
          output_credits * 1.25, output_energy * 1.25, output_food * 1.25, output_materials * 1.25, output_components * 1.25, output_compute * 1.25,
          upkeep_credits * 1.12, upkeep_energy * 1.12, upkeep_food * 1.12, upkeep_materials * 1.12, upkeep_components * 1.12, upkeep_compute * 1.12,
          operating_credits * 1.12, operating_energy * 1.12, operating_food * 1.12, operating_materials * 1.12, operating_components * 1.12, operating_compute * 1.12,
          COALESCE(description, '') || ' Researched Tier ' || $2 || ' generation.', GREATEST(1, CEIL(construction_days * 1.15)), GREATEST(1440, CEIL(COALESCE(construction_minutes, construction_days * 1440) * 1.15)), false, $3
        FROM building_catalog WHERE id = $4`,
        [targetCatalogId, targetTier, projectId, previous.rows[0].id],
      );
      await tx.query('UPDATE building_catalog SET next_catalog_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [targetCatalogId, previous.rows[0].id]);
    }

    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: time.gameDay, debitAccount: corporation.rows[0].account_id, creditAccount: 'account-research-registry', amount: centsToMoney(moneyToCents(cost)), reasonType: 'corporation_building_research', reasonId: projectId, ruleVersion: 'corporation-building-research-v1', correlationId: input.correlationId });
    await tx.query(
      `INSERT INTO corporation_building_research_projects (id, corporation_id, building_type, catalog_id, target_tier, research_cost_credits, duration_minutes, started_game_day, started_game_minute, correlation_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [projectId, corporationId, input.buildingType, targetCatalogId, targetTier, cost, durationMinutes, time.gameDay, time.gameMinute, input.correlationId],
    );
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_building_research_projects WHERE id = $1', [projectId])).rows[0], catalogId: targetCatalogId, correlationId: input.correlationId };
  });
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
  const world = await repository.query<{ genesis_at: string | null; simulated_day_offset: number | null }>("SELECT genesis_at, simulated_day_offset FROM world_state WHERE id = 'WORLD'");
  const time = getAuthoritativeGameTime({ genesisAt: world.rows[0]?.genesis_at, simulatedDayOffset: world.rows[0]?.simulated_day_offset });
  const active = await repository.query<{ id: string; corporation_id: string; catalog_id: string; started_game_day: number; started_game_minute: number; duration_minutes: number }>("SELECT id, corporation_id, catalog_id, started_game_day, started_game_minute, duration_minutes FROM corporation_building_research_projects WHERE status = 'active' FOR UPDATE");
  let completed = 0;
  for (const project of active.rows) {
    const elapsed = Math.max(0, time.totalGameMinutes - ((Number(project.started_game_day) - 1) * 1440 + Number(project.started_game_minute)));
    const progress = Math.min(100, Math.round(elapsed / Math.max(1, Number(project.duration_minutes)) * 100000) / 1000);
    if (progress < 100) {
      await repository.query('UPDATE corporation_building_research_projects SET progress = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [progress, project.id]);
      continue;
    }
    await repository.query("UPDATE corporation_building_research_projects SET progress = 100, status = 'completed', completed_game_day = $1, completed_game_minute = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3", [time.gameDay, time.gameMinute, project.id]);
    await repository.query('UPDATE building_catalog SET is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1', [project.catalog_id]);
    await repository.query("INSERT INTO corporation_building_unlocks (corporation_id, catalog_id, research_project_id, unlocked_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT (corporation_id, catalog_id) DO UPDATE SET status = 'unlocked', research_project_id = EXCLUDED.research_project_id", [project.corporation_id, project.catalog_id, project.id, time.gameDay]);
    completed += 1;
  }
  return completed;
}
