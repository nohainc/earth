import type { PostgresRepository } from './repository.ts';
import { formatCreditUnits } from './money.ts';

type ResearchInput = { humanId: string; buildingType: string; correlationId: string };

async function corporationForHuman(tx: PostgresRepository, humanId: string): Promise<string> {
  const membership = await tx.query<{ corporation_id: string | null }>(
    "SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' AND ha.corporation_id IS NOT NULL LIMIT 1",
    [humanId],
  );
  const corporationId = membership.rows[0]?.corporation_id;
  if (!corporationId) throw new Error('Building research is available only to corporation members');
  return corporationId;
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
    // Building unlocks are represented by completed, corporation-owned
    // research projects.  The retired corporation_building_unlocks mirror was
    // never part of the canonical V4 schema.
    const unlocked = await tx.query<{ tier: string }>(
      `SELECT COALESCE(MAX(c.tier), 1)::text AS tier
       FROM corporation_research_projects p
       JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
       JOIN building_catalog c ON c.id = p.target_id
       WHERE o.id = $1
         AND p.target_type = 'BUILDING_BLUEPRINT'
         AND p.status = 'COMPLETED'
         AND c.family_code = $2`,
      [corporationId, input.buildingType],
    );
    const priorTier = Number(unlocked.rows[0]?.tier ?? 1);
    const previous = await tx.query<{ id: string; tier: number; slot_footprint: number; ownership_scope: string }>(
      'SELECT id, tier, slot_footprint, ownership_scope FROM building_catalog WHERE family_code = $1 AND tier = $2 LIMIT 1',
      [input.buildingType, priorTier],
    );
    if (!previous.rows[0]) throw new Error('Building blueprint not found');
    const targetTier = priorTier + 1;
    if (targetTier > 5) throw new Error(`No predefined building tier remains after Tier ${priorTier}`);
    const targetCatalogId = `${input.buildingType}-t${targetTier}`;
    // Tiers are authored in the catalog. Research unlocks a predefined
    // blueprint; it never generates or mutates shared catalog economics.
    const targetCatalog = await tx.query<{ research_credit_units: string; research_duration_game_days: number }>(
      'SELECT * FROM building_catalog WHERE id = $1 AND family_code = $2 AND tier = $3 AND tier BETWEEN 1 AND 5',
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
    const costUnits = BigInt(targetCatalog.rows[0]?.research_credit_units ?? '100000');
    const durationDays = Number(targetCatalog.rows[0]?.research_duration_game_days ?? 5);
    // The database clock is the sole source of time. Do not derive or submit
    // a client/server timestamp for research start or completion.
    const timeRes = await tx.query<{ game_day: number }>(
      'SELECT earth_game_day_from_total_minutes(total_game_minutes) AS game_day FROM earth_get_current_game_time()',
    );
    const time = timeRes.rows[0];
    if (!time) throw new Error('Authoritative game clock is unavailable');
    const projectId = `CBR-${crypto.randomUUID().slice(0, 10).toUpperCase()}`;

    const fundingAccounts = await tx.query<{ debit_account_id: string; research_account_id: string }>(`SELECT payer.id::TEXT AS debit_account_id, service.id::TEXT AS research_account_id
      FROM economic_accounts payer
      JOIN owner_registry payer_owner ON payer_owner.economic_id = payer.owner_economic_id AND payer_owner.id = $1 AND payer_owner.owner_type = 'CORPORATION'
      JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
      JOIN economic_accounts service ON service.owner_economic_id = system_owner.economic_id
        AND service.asset_id = 1 AND service.account_type = 'SYSTEM_ACCOUNT' AND service.status = 'ACTIVE'
      WHERE payer.asset_id = 1
        AND payer.account_type = 'OPERATIONS'
        AND payer.status = 'ACTIVE'
      ORDER BY payer.id
      LIMIT 1`, [corporationId]);
    if (!fundingAccounts.rows[0]) throw new Error(`CREDIT funding account requires ${formatCreditUnits(costUnits)} Credits for this research`);

    const budget = (await tx.query<{ id: string }>(`SELECT l.id FROM institution_budget_lines l JOIN budget_categories c ON c.id=l.category_id
      WHERE l.institution_id=$1 AND c.institution_kind='CORPORATION' AND c.category_code='RESEARCH'
        AND l.fiscal_period_id=(SELECT id FROM fiscal_periods WHERE start_game_day <= $2 AND end_game_day >= $2 AND status='ACTIVE' LIMIT 1)
        AND l.authorized_units-l.committed_units-l.spent_units >= $3 FOR UPDATE`, [corporationId, time.game_day, costUnits.toString()])).rows[0];
    if (!budget) throw new Error('Corporation research budget authority is unavailable');
    const commitmentId = `COMMIT-RESEARCH-${projectId}`;
    await tx.query(`INSERT INTO institution_budget_commitments
      (id,institution_id,budget_line_id,source_type,source_id,original_units,remaining_units,status,due_game_day)
      VALUES ($1,$2,$3,'CORPORATION_RESEARCH',$4,$5,$5,'OPEN',$6)`, [commitmentId, corporationId, budget.id, projectId, costUnits.toString(), time.game_day + durationDays]);
    await tx.query('UPDATE institution_budget_lines SET committed_units=committed_units+$1 WHERE id=$2', [costUnits.toString(), budget.id]);

    const corporationOwner = await tx.query<{ economic_id: string }>('SELECT economic_id::TEXT FROM owner_registry WHERE id = $1', [corporationId]);
    if (!corporationOwner.rows[0]) throw new Error('Corporation economic owner is not provisioned');
    const funding = await tx.query<{ transaction_id: string }>(
      `SELECT transaction_id FROM earth_post_transaction($1,$2,1439,'RESEARCH_FUNDING','CORPORATION_RESEARCH',$3,'building-catalog-v1',$4::jsonb)`,
      [input.correlationId, time.game_day, projectId, JSON.stringify([
        { account_id: fundingAccounts.rows[0].debit_account_id, delta_units: (-costUnits).toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
        { account_id: fundingAccounts.rows[0].research_account_id, delta_units: costUnits.toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
      ])],
    );
    if (!funding.rows[0]?.transaction_id) throw new Error('Research funding transaction was not created');
    await tx.query(`UPDATE institution_budget_commitments SET remaining_units=0,status='PAID' WHERE id=$1`, [commitmentId]);
    await tx.query('UPDATE institution_budget_lines SET committed_units=committed_units-$1, spent_units=spent_units+$1 WHERE id=$2', [costUnits.toString(), budget.id]);
    await tx.query(`INSERT INTO corporation_research_projects
      (id, corporation_economic_id, target_type, target_id, definition_version,
       required_research_points, progress_research_points, credit_cost_units,
       priority, status, started_game_day, funding_transaction_id, correlation_id)
      VALUES ($1,$2,'BUILDING_BLUEPRINT',$3,'building-catalog-v1',$4,0,$5,100,'ACTIVE',$6,$7,$8)
      ON CONFLICT (id) DO NOTHING`,
      [projectId, corporationOwner.rows[0].economic_id, targetCatalogId, durationDays * 100, costUnits.toString(), time.game_day, funding.rows[0].transaction_id, input.correlationId]);
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_research_projects WHERE id = $1', [projectId])).rows[0], catalogId: targetCatalogId, correlationId: input.correlationId };
}

export async function startCorporationBuildingResearch(repository: PostgresRepository, input: ResearchInput): Promise<Record<string, unknown>> {
  return repository.transaction((tx) => startCorporationBuildingResearchInTransaction(tx, input));
}

/** Server-authoritative preview for the next Corporation building blueprint tier. */
export async function quoteCorporationBuildingResearch(repository: PostgresRepository, input: { humanId: string; buildingType: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const corporationId = await corporationForHuman(tx, input.humanId);
    await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`corp-building-research-quote:${corporationId}:${input.buildingType}`]);
    const unlocked = await tx.query<{ tier: string }>(
      `SELECT COALESCE(MAX(c.tier), 1)::text AS tier
       FROM corporation_research_projects p
       JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
       JOIN building_catalog c ON c.id = p.target_id
       WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' AND p.status = 'COMPLETED' AND c.family_code = $2`,
      [corporationId, input.buildingType],
    );
    const currentTier = Number(unlocked.rows[0]?.tier ?? 1);
    const previous = (await tx.query(`SELECT * FROM building_catalog WHERE family_code = $1 AND tier = $2 LIMIT 1`, [input.buildingType, currentTier])).rows[0];
    if (!previous) throw new Error('Building blueprint not found');
    const targetTier = currentTier + 1;
    if (targetTier > 5) throw new Error(`No predefined building tier remains after Tier ${currentTier}`);
    const target = (await tx.query(`SELECT * FROM building_catalog WHERE family_code = $1 AND tier = $2 LIMIT 1`, [input.buildingType, targetTier])).rows[0];
    if (!target) throw new Error(`Predefined Tier ${targetTier} blueprint is missing from the building catalog`);
    const existing = (await tx.query<{ id: string; status: string }>(
      `SELECT p.id, p.status FROM corporation_research_projects p
       JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
       WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' AND p.target_id = $2
         AND p.status IN ('QUEUED','ACTIVE','COMPLETED') LIMIT 1`,
      [corporationId, target.id],
    )).rows[0] ?? null;
    const costUnits = BigInt(target.research_credit_units);
    const durationDays = Number(target.research_duration_game_days);
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    return {
      ok: true,
      corporationId,
      currentTier,
      targetTier,
      currentBlueprint: previous,
      targetBlueprint: target,
      quote: {
        researchCostUnits: costUnits.toString(),
        durationDays,
        startsGameDay: day + 1,
        completesGameDay: day + 1 + durationDays,
        alreadyActive: existing,
      },
      generatedFrom: 'postgres-canonical-building-catalog-v5',
    };
  });
}

export async function listCorporationBuildingResearch(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const membership = await repository.query<{ corporation_id: string | null }>(
    'SELECT corporation_id FROM house_affiliations WHERE house_id = (SELECT house_id FROM humans WHERE id = $1) AND status = \'ACTIVE\' AND corporation_id IS NOT NULL LIMIT 1',
    [humanId],
  );
  const corporationId = membership.rows[0]?.corporation_id;
  if (!corporationId) return { corporationId: null, projects: [], unlocks: [] };
  const projects = await repository.query(`SELECT p.*, c.code AS catalog_name FROM corporation_research_projects p
      JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
      JOIN building_catalog c ON c.id = p.target_id
      WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' ORDER BY p.created_at DESC`, [corporationId]);
  const unlocks = await repository.query(`SELECT p.id AS project_id, p.target_id AS catalog_id,
      c.code AS catalog_name, c.family_code, c.tier, p.completed_game_day
    FROM corporation_research_projects p
    JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
    JOIN building_catalog c ON c.id = p.target_id
    WHERE o.id = $1 AND p.target_type = 'BUILDING_BLUEPRINT' AND p.status = 'COMPLETED'
    ORDER BY c.family_code, c.tier`, [corporationId]);
  return { corporationId, projects: projects.rows, unlocks: unlocks.rows };
}

export async function advanceCorporationBuildingResearch(repository: PostgresRepository): Promise<number> {
  const advanced = await repository.query<{ completed: number }>(
    'SELECT earth_advance_corporation_building_research() AS completed',
  );
  return Number(advanced.rows[0]?.completed ?? 0);
}
