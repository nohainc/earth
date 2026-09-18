import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { assessBuildingAge } from './building-age.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { rebuildV5CorporationSettlementProfile, refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { assertEarthTechnologyFrontier } from './earth-technology-frontier-postgres.ts';

async function startCorporationCapitalProject(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; projectKind: 'OVERHAUL' | 'GENERATION_RETROFIT'; targetGenerationId?: string; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, buildingId: input.buildingId, correlationId: input.correlationId };
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const building = (await tx.query<{ id: string; corporation_id: string; owner_economic_id: string; catalog_id: string; construction_credit_units: string; definition_version: number; status: string }>(
      `SELECT b.id, owner.id AS corporation_id, b.owner_economic_id, b.catalog_id, c.construction_credit_units::TEXT,
              c.definition_version, b.status
         FROM buildings b
         JOIN building_catalog c ON c.id = b.catalog_id
         JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id AND owner.owner_type = 'CORPORATION'
         JOIN humans h ON h.id = $2 AND h.status = 'ACTIVE'
         JOIN house_affiliations affiliation ON affiliation.house_id = h.house_id
           AND affiliation.corporation_id = owner.id AND affiliation.status = 'ACTIVE'
        WHERE b.id = $1 FOR UPDATE`, [input.buildingId, input.humanId],
    )).rows[0];
    if (!building) throw new Error('Building not found or not owned by the active Corporation');
    const authorized = await tx.query(
      `SELECT 1 FROM institution_governance_roles
        WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
          AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`, [building.corporation_id, input.humanId],
    );
    if (!authorized.rows[0]) throw new Error('Corporation governance authorization is required');
    if (building.status !== 'ACTIVE') throw new Error('Only an active building can start a capital project');
    if ((await tx.query('SELECT id FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0]) throw new Error('This building already has a capital project in progress');
    if (input.projectKind === 'GENERATION_RETROFIT') {
      if (!input.targetGenerationId) throw new Error('A target technology generation is required for retrofit');
      const target = (await tx.query<{ effective_from_game_day: number }>(`SELECT d.effective_from_game_day FROM technology_generations g JOIN technology_discoveries d ON d.generation_id = g.id WHERE g.id = $1`, [input.targetGenerationId])).rows[0];
      if (!target || Number(target.effective_from_game_day) > day) throw new Error('Technology generation is not discovered and effective');
      const targetGeneration = (await tx.query<{ domain_id: string; generation_number: number }>('SELECT domain_id, generation_number FROM technology_generations WHERE id = $1', [input.targetGenerationId])).rows[0];
      if (!targetGeneration) throw new Error('Technology generation does not exist');
      await assertEarthTechnologyFrontier(tx, targetGeneration.domain_id, Number(targetGeneration.generation_number), day);
    }
    const multiplier = input.projectKind === 'OVERHAUL' ? 7500n : 4000n;
    const cost = BigInt(building.construction_credit_units) * multiplier / 10000n;
    const treasury = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE' FOR UPDATE`, [building.owner_economic_id])).rows[0];
    const sink = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND o.owner_type = 'SYSTEM' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
    if (!treasury || !sink || BigInt(treasury.balance_units) < cost) throw new Error('Insufficient Corporation Treasury for capital project');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER',$3,$4,'capital-project-v5',$5::JSONB)`, [input.correlationId, day, input.projectKind, input.buildingId, JSON.stringify([{ account_id: treasury.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    const projectId = `PROJECT-CAPITAL-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind, target_generation_id) VALUES ($1,$2,$3,NULL,$4,$5,'{}'::JSONB,$6,$7,'IN_PROGRESS',$8,NULL,$9,$10)`, [projectId, building.id, building.owner_economic_id, building.catalog_id, cost.toString(), day, day + 1, input.correlationId, input.projectKind, input.targetGenerationId ?? null]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await rebuildV5CorporationSettlementProfile(tx, building.corporation_id, day);
    await createGameEvent(tx, { id: `CAPITAL-PROJECT-STARTED-${input.correlationId}`, category: 'BUILDING', eventType: 'CAPITAL_PROJECT_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `${input.projectKind === 'OVERHAUL' ? 'Building overhaul' : 'Technology retrofit'} started`, details: { projectId, buildingId: building.id, projectKind: input.projectKind, targetGenerationId: input.targetGenerationId ?? null, creditCostUnits: cost.toString(), expectedCompletionGameDay: day + 1, ownerType: 'CORPORATION', capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, projectId, ownerType: 'CORPORATION', projectKind: input.projectKind, targetGenerationId: input.targetGenerationId ?? null, creditCostUnits: cost.toString(), expectedCompletionGameDay: day + 1, correlationId: input.correlationId };
  });
}

export async function getBuildingCapitalOptions(repository: PostgresRepository, buildingId: string): Promise<Record<string, unknown>> {
  const day = (await readAuthoritativeGameTime(repository)).gameDay;
  const row = (await repository.query<any>(`SELECT b.id, b.catalog_id, b.started_game_day, COALESCE(b.last_major_rebuild_game_day, b.started_game_day) AS last_major_rebuild_game_day, c.code, c.family_code, c.tier, c.construction_credit_units::TEXT, c.operating_credit_units::TEXT, r.design_life_days, r.overdue_burden_bps_per_day, r.maximum_burden_bps, COALESCE(jsonb_agg(jsonb_build_object('domainId', i.domain_id, 'generationId', i.generation_id, 'installedGameDay', i.installed_game_day)) FILTER (WHERE i.id IS NOT NULL), '[]'::jsonb) AS installed_generations FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN building_design_life_rules r ON r.catalog_id = b.catalog_id LEFT JOIN building_generation_installations i ON i.building_id = b.id AND i.status = 'ACTIVE' WHERE b.id = $1 GROUP BY b.id, c.code, c.family_code, c.tier, c.construction_credit_units, c.operating_credit_units, r.design_life_days, r.overdue_burden_bps_per_day, r.maximum_burden_bps`, [buildingId])).rows[0];
  if (!row) throw new Error('Building not found');
  const age = assessBuildingAge({ currentGameDay: BigInt(day), lastMajorRebuildGameDay: BigInt(row.last_major_rebuild_game_day), designLifeDays: BigInt(row.design_life_days), overdueBurdenBpsPerDay: BigInt(row.overdue_burden_bps_per_day), maximumBurdenBps: BigInt(row.maximum_burden_bps) });
  const next = (await repository.query<any>(`SELECT id, code, construction_credit_units::TEXT, operating_credit_units::TEXT FROM building_catalog WHERE family_code = $1 AND tier = $2 LIMIT 1`, [row.family_code, Number(row.tier) + 1])).rows[0];
  const flowRows = (await repository.query<any>(`SELECT f.catalog_id, ea.code, f.operating_input_units::TEXT, f.operating_output_units::TEXT,
          COALESCE(s.last_clearing_price_units, i.genesis_reference_price_units)::TEXT AS price_units
     FROM building_catalog_resource_flows f
     JOIN economic_assets ea ON ea.id = f.asset_id
     LEFT JOIN market_instruments i ON i.symbol = 'SPOT-' || UPPER(ea.code) AND i.status = 'ACTIVE'
     LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
    WHERE f.catalog_id = ANY($1::TEXT[])
    ORDER BY f.catalog_id, ea.code`, [[row.catalog_id, next?.id].filter(Boolean)])).rows;
  const valueForCatalog = (catalogId: string, operatingCreditUnits: string) => {
    const flows = flowRows.filter((flow) => flow.catalog_id === catalogId);
    let gross = 0n;
    let inputs = 0n;
    for (const flow of flows) {
      const price = BigInt(flow.price_units ?? '0');
      gross += BigInt(flow.operating_output_units ?? '0') * price / 1000000n;
      inputs += BigInt(flow.operating_input_units ?? '0') * price / 1000000n;
    }
    const operating = inputs + BigInt(operatingCreditUnits ?? '0');
    return { gross: gross.toString(), operating: operating.toString(), net: (gross - operating).toString() };
  };
  const currentEconomics = valueForCatalog(row.catalog_id, row.operating_credit_units);
  const nextEconomics = next ? valueForCatalog(next.id, next.operating_credit_units) : null;
  const project = (type: string, cost: bigint, economics: { gross: string; operating: string; net: string }, effect: string, targetCatalogCode: string | null = null) => {
    const net = BigInt(economics.net);
    return {
      type, effect, targetCatalogCode,
      creditCostUnits: cost.toString(),
      projectedDailyGrossValueUnits: economics.gross,
      projectedDailyOperatingCostUnits: economics.operating,
      projectedDailyNetValueUnits: economics.net,
      paybackGameDays: cost > 0n && net > 0n ? Math.ceil(Number(cost) / Number(net)) : null,
    };
  };
  const options = [
    project('CONTINUE', 0n, currentEconomics, 'retain_current_age', row.code),
    project('OVERHAUL', BigInt(row.construction_credit_units) * 7500n / 10000n, currentEconomics, 'reset_major_rebuild_day', row.code),
    ...(next && nextEconomics ? [project('TIER_UPGRADE', BigInt(next.construction_credit_units) - BigInt(row.construction_credit_units), nextEconomics, 'replace_physical_scale', next.code)] : []),
    project('GENERATION_RETROFIT', BigInt(row.construction_credit_units) * 4000n / 10000n, currentEconomics, 'install_generation_without_resetting_age', row.code),
  ];
  return { building: { id: row.id, code: row.code, familyCode: row.family_code, tier: Number(row.tier), ageDays: age.ageDays.toString(), designLifeDays: age.designLifeDays.toString(), overdueDays: age.overdueDays.toString(), burdenMultiplierBps: age.burdenMultiplierBps.toString(), operable: age.operable, installedGenerations: row.installed_generations }, options, generatedFrom: 'postgres-canonical-facts' };
}

export async function startBuildingCapitalProject(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; projectKind: 'OVERHAUL' | 'GENERATION_RETROFIT'; targetGenerationId?: string; correlationId: string },
): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return startCorporationCapitalProject(repository, input);
  return repository.transaction(async (tx) => {
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const building = (await tx.query<{ id: string; owner_economic_id: string; catalog_id: string; construction_credit_units: string; definition_version: number; status: string; house_id: string }>(
      `SELECT b.id, b.owner_economic_id, b.catalog_id, c.construction_credit_units::TEXT,
              c.definition_version, b.status, h.house_id
         FROM buildings b
         JOIN building_catalog c ON c.id = b.catalog_id
         JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE'
         JOIN humans h ON h.id = $2 AND h.house_id = o.id AND h.status = 'ACTIVE'
        WHERE b.id = $1
        FOR UPDATE`, [input.buildingId, input.humanId],
    )).rows[0];
    if (!building) throw new Error('Building not found or not owned by the active House');
    if (building.status !== 'ACTIVE') throw new Error('Only an active building can start a capital project');
    const existing = (await tx.query('SELECT id FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0];
    if (existing) throw new Error('This building already has a capital project in progress');

    let targetGeneration: { domain_id: string; effective_from_game_day: number } | undefined;
    if (input.projectKind === 'GENERATION_RETROFIT') {
      if (!input.targetGenerationId) throw new Error('A target technology generation is required for retrofit');
      targetGeneration = (await tx.query<{ domain_id: string; effective_from_game_day: number }>(
        `SELECT g.domain_id, d.effective_from_game_day
           FROM technology_generations g
           JOIN technology_discoveries d ON d.generation_id = g.id
          WHERE g.id = $1`, [input.targetGenerationId],
      )).rows[0];
      if (!targetGeneration || Number(targetGeneration.effective_from_game_day) > day) throw new Error('Technology generation is not discovered and effective');
      await assertEarthTechnologyFrontier(tx, targetGeneration.domain_id, Number((await tx.query<{ generation_number: number }>('SELECT generation_number FROM technology_generations WHERE id = $1', [input.targetGenerationId])).rows[0]?.generation_number ?? 0), day);
    }

    const multiplier = input.projectKind === 'OVERHAUL' ? 7500n : 4000n;
    const cost = BigInt(building.construction_credit_units) * multiplier / 10000n;
    const wallet = (await tx.query<{ id: string; balance_units: string }>(
      `SELECT id::TEXT, balance_units::TEXT FROM economic_accounts
        WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`, [building.owner_economic_id],
    )).rows[0];
    const sink = (await tx.query<{ id: string }>(
      `SELECT a.id::TEXT FROM economic_accounts a
        JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND o.owner_type = 'SYSTEM'
         AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`,
    )).rows[0];
    if (!wallet || !sink || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient CREDIT for capital project');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER',$3,$4,'capital-project-v5',$5::JSONB)`, [input.correlationId, day, input.projectKind, input.buildingId, JSON.stringify([
      { account_id: wallet.id, asset_id: 1, delta_units: (-cost).toString() },
      { account_id: sink.id, asset_id: 1, delta_units: cost.toString() },
    ])]);
    const projectId = `PROJECT-CAPITAL-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO construction_projects
      (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units,
       started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind, target_generation_id)
      VALUES ($1,$2,$3,NULL,$4,$5,'{}'::JSONB,$6,$7,'IN_PROGRESS',$8,NULL,$9,$10)`, [
      projectId, building.id, building.owner_economic_id, building.catalog_id, cost.toString(), day, day + 1,
      input.correlationId, input.projectKind, input.targetGenerationId ?? null,
    ]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await refreshV5SettlementProfilesForHouse(tx, building.house_id, day);
    await createGameEvent(tx, {
      id: `CAPITAL-PROJECT-STARTED-${input.correlationId}`,
      category: 'BUILDING', eventType: 'CAPITAL_PROJECT_STARTED', gameDay: day,
      actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id,
      title: `${input.projectKind === 'OVERHAUL' ? 'Building overhaul' : 'Technology retrofit'} started`,
      details: { projectId, buildingId: building.id, projectKind: input.projectKind, targetGenerationId: input.targetGenerationId ?? null, creditCostUnits: cost.toString(), expectedCompletionGameDay: day + 1, capacityModel: 'V5_POOLED', territoryPlacement: null },
      correlationId: input.correlationId,
    });
    return { ok: true, projectId, projectKind: input.projectKind, targetGenerationId: input.targetGenerationId ?? null, creditCostUnits: cost.toString(), expectedCompletionGameDay: day + 1, correlationId: input.correlationId };
  });
}
