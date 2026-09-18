import type { PostgresRepository } from './repository.ts';

// @mutation-boundary caller-owned-transaction

export async function resolveTechnologyDomain(
  tx: PostgresRepository,
  domainCodeOrId: string,
): Promise<{ id: string; code: string; name: string }> {
  const row = (await tx.query<{ id: string; code: string; name: string }>(
    `SELECT id, code, name FROM technology_domains
      WHERE id = $1 OR code = $1 OR lower(code) = lower($1) LIMIT 1`,
    [domainCodeOrId],
  )).rows[0];
  if (!row) throw new Error(`Unknown technology domain: ${domainCodeOrId}`);
  return row;
}

export type AvailableGenerationsResult = {
  domainId: string;
  domainCode: string;
  earthFrontierGeneration: number;
  maxAccessibleGeneration: number;
  availableGenerations: number[];
};

export async function getAvailableGenerations(
  tx: PostgresRepository,
  domainCodeOrId: string,
  ownerEconomicId: string,
  ownerType: 'HOUSE' | 'CORPORATION',
  affiliatedCorpEconomicId?: string | null,
  gameDay = 1,
): Promise<AvailableGenerationsResult> {
  const domain = await resolveTechnologyDomain(tx, domainCodeOrId);

  // 1. Earth Technology Frontier max generation effective on gameDay
  const frontierRow = (await tx.query<{ max_generation: number }>(
    `SELECT COALESCE(
       (SELECT generation_number
          FROM earth_technology_frontier_versions
         WHERE domain_id = $1 AND status = 'ACTIVE' AND effective_from_game_day <= $2
         ORDER BY effective_from_game_day DESC, generation_number DESC LIMIT 1),
       (SELECT max_generation_number FROM earth_technology_frontier WHERE domain_id = $1),
       1
     ) AS max_generation`,
    [domain.id, gameDay],
  )).rows[0];
  const earthFrontierGen = Math.max(1, Number(frontierRow?.max_generation ?? 1));

  // Generation 1 is universally available to all entities
  const generations = new Set<number>([1]);

  // 2. Corporation-specific technology generation adoptions
  const targetCorpEconId = ownerType === 'CORPORATION' ? ownerEconomicId : affiliatedCorpEconomicId;
  if (targetCorpEconId) {
    // Check direct corporation_technology_generations table
    const corpGens = await tx.query<{ generation_number: number }>(
      `SELECT generation_number FROM corporation_technology_generations
        WHERE corporation_economic_id = $1 AND domain_id = $2 AND unlocked_game_day <= $3`,
      [targetCorpEconId, domain.id, gameDay],
    );
    for (const row of corpGens.rows) {
      const g = Number(row.generation_number);
      if (g <= earthFrontierGen) generations.add(g);
    }

    // Also check organization_technology_adoptions if applicable
    const orgAdoptions = await tx.query<{ generation_number: number }>(
      `SELECT g.generation_number
         FROM organization_technology_adoptions a
         JOIN technology_generations g ON g.id = a.generation_id
        WHERE a.organization_id = (SELECT id FROM owner_registry WHERE economic_id = $1 LIMIT 1)
          AND a.status = 'ADOPTED'
          AND (a.effective_from_game_day IS NULL OR a.effective_from_game_day <= $2)
          AND g.domain_id = $3`,
      [targetCorpEconId, gameDay, domain.id],
    );
    for (const row of orgAdoptions.rows) {
      const g = Number(row.generation_number);
      if (g <= earthFrontierGen) generations.add(g);
    }
  }

  // Filter so no generation exceeds Earth frontier
  const validGenerations = Array.from(generations)
    .filter((g) => g <= earthFrontierGen)
    .sort((a, b) => a - b);
  const maxAccessible = validGenerations.length > 0 ? Math.max(...validGenerations) : 1;

  return {
    domainId: domain.id,
    domainCode: domain.code,
    earthFrontierGeneration: earthFrontierGen,
    maxAccessibleGeneration: maxAccessible,
    availableGenerations: validGenerations,
  };
}

export async function assertGenerationAuthorized(
  tx: PostgresRepository,
  domainCodeOrId: string,
  generationNumber: number,
  ownerEconomicId: string,
  ownerType: 'HOUSE' | 'CORPORATION',
  affiliatedCorpEconomicId?: string | null,
  gameDay = 1,
): Promise<{ authorized: boolean; reason?: string }> {
  if (!Number.isInteger(generationNumber) || generationNumber < 1) {
    return { authorized: false, reason: `Generation number must be a positive integer: ${generationNumber}` };
  }

  const info = await getAvailableGenerations(tx, domainCodeOrId, ownerEconomicId, ownerType, affiliatedCorpEconomicId, gameDay);

  if (generationNumber > info.earthFrontierGeneration) {
    return {
      authorized: false,
      reason: `Technology generation ${generationNumber} exceeds the Earth frontier (${info.earthFrontierGeneration}) for domain ${info.domainCode}`,
    };
  }

  if (!info.availableGenerations.includes(generationNumber)) {
    return {
      authorized: false,
      reason: `Missing required technology generation ${generationNumber} for domain ${info.domainCode}`,
    };
  }

  return { authorized: true };
}

export async function grantCorporationTechnologyGeneration(
  tx: PostgresRepository,
  corpEconomicId: string,
  domainCodeOrId: string,
  generationNumber: number,
  gameDay = 1,
): Promise<void> {
  const domain = await resolveTechnologyDomain(tx, domainCodeOrId);
  await tx.query(
    `INSERT INTO corporation_technology_generations (corporation_economic_id, domain_id, generation_number, unlocked_game_day)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (corporation_economic_id, domain_id, generation_number) DO NOTHING`,
    [corpEconomicId, domain.id, generationNumber, gameDay],
  );
}

export async function grantEarthBaselineTechnologyGeneration(
  tx: PostgresRepository,
  domainCodeOrId: string,
  generationNumber: number,
  gameDay = 1,
  governanceProposalId?: string,
): Promise<void> {
  if (generationNumber > 1 && !governanceProposalId) {
    throw new Error('Earth frontier advancement requires an Earth governance proposal');
  }
  const domain = await resolveTechnologyDomain(tx, domainCodeOrId);
  const id = `EARTH-FRONTIER-${domain.id}-${generationNumber}`;
  const effectiveDay = generationNumber === 1 ? 1 : Math.max(2, Number(gameDay));
  await tx.query(
    `INSERT INTO earth_technology_frontier_versions
       (id, domain_id, generation_number, effective_from_game_day, correlation_id, authorization_proposal_id)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (domain_id, generation_number) DO UPDATE SET
       effective_from_game_day = LEAST(earth_technology_frontier_versions.effective_from_game_day, EXCLUDED.effective_from_game_day),
       authorization_proposal_id = COALESCE(EXCLUDED.authorization_proposal_id, earth_technology_frontier_versions.authorization_proposal_id)`,
    [id, domain.id, generationNumber, effectiveDay, `earth-frontier-grant:${domain.id}:${generationNumber}`, governanceProposalId ?? null],
  );
  await tx.query(
    `INSERT INTO earth_technology_frontier (domain_id, max_generation_number, updated_game_day)
     VALUES ($1, $2, $3)
     ON CONFLICT (domain_id) DO UPDATE SET
       max_generation_number = GREATEST(earth_technology_frontier.max_generation_number, EXCLUDED.max_generation_number),
       updated_game_day = $3`,
    [domain.id, generationNumber, effectiveDay],
  );
}
