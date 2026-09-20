import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

// @mutation-boundary caller-owned-transaction

export type FrontierAdvanceInput = {
  domainId: string;
  generationNumber: number;
  effectiveFromGameDay: number;
  researchCreditCostUnits?: bigint;
  researchResourceCosts?: Record<string, string>;
  proposalId: string;
  humanId?: string;
  correlationId: string;
};

async function currentFrontier(tx: PostgresRepository, domainId: string): Promise<number> {
  const row = (await tx.query<{ max_generation_number: number }>(
    'SELECT max_generation_number FROM earth_technology_frontier WHERE domain_id = $1 FOR UPDATE', [domainId],
  )).rows[0];
  if (!row) throw new Error(`Technology domain is not on the Earth frontier: ${domainId}`);
  return Number(row.max_generation_number);
}

export async function getEarthTechnologyFrontier(repository: PostgresRepository, gameDay?: number): Promise<Record<string, unknown>> {
  const day = gameDay ?? (await readAuthoritativeGameTime(repository)).gameDay;
  const result = await repository.query(`
    SELECT d.id AS domain_id, d.code AS domain_code, d.name AS domain_name,
           COALESCE(v.generation_number, 1) AS max_generation_number,
           COALESCE(v.effective_from_game_day, 1) AS effective_from_game_day,
           v.authorization_proposal_id, v.rules_version,
           next_generation.generation_number AS next_generation_number,
           next_generation.minimum_game_day AS next_generation_minimum_game_day
      FROM technology_domains d
      LEFT JOIN LATERAL (
        SELECT generation_number, effective_from_game_day,
               authorization_proposal_id, rules_version
          FROM earth_technology_frontier_versions
         WHERE domain_id = d.id AND status = 'ACTIVE'
           AND effective_from_game_day <= $1
         ORDER BY effective_from_game_day DESC
         LIMIT 1
     ) v ON TRUE
     LEFT JOIN LATERAL (
       SELECT g.generation_number, g.minimum_game_day
         FROM technology_generations g
        WHERE g.domain_id = d.id
          AND g.generation_number > COALESCE(v.generation_number, 1)
        ORDER BY g.generation_number
        LIMIT 1
     ) next_generation ON TRUE
     WHERE d.status = 'ACTIVE' AND d.code <> 'FOUNDATIONAL'
     ORDER BY d.code`, [day]);
  return { gameDay: day, frontier: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function assertEarthTechnologyFrontier(
  tx: PostgresRepository,
  domainId: string,
  generationNumber: number,
  gameDay: number,
): Promise<void> {
  const row = (await tx.query<{ max_generation_number: number }>(`
    SELECT COALESCE((SELECT generation_number
                       FROM earth_technology_frontier_versions
                      WHERE domain_id = $1 AND status = 'ACTIVE'
                        AND effective_from_game_day <= $2
                      ORDER BY effective_from_game_day DESC LIMIT 1), 1) AS max_generation_number`,
  [domainId, gameDay])).rows[0];
  if (!row || Number(row.max_generation_number) < generationNumber) {
    throw new Error(`Technology generation exceeds the Earth frontier: ${domainId}:${generationNumber}`);
  }
}

/** Apply one passed Earth governance action at its scheduled effective day. */
export async function advanceEarthTechnologyFrontier(
  tx: PostgresRepository,
  input: FrontierAdvanceInput,
  executionGameDay: number,
): Promise<Record<string, unknown>> {
  const prior = await tx.query<{ id: string }>(
    'SELECT id FROM earth_technology_frontier_versions WHERE correlation_id = $1', [input.correlationId],
  );
  if (prior.rows[0]) return { ok: true, alreadyProcessed: true, frontierVersionId: prior.rows[0].id, correlationId: input.correlationId };
  if (!Number.isInteger(input.generationNumber) || input.generationNumber < 1) throw new Error('Frontier generation must be a positive integer');
  if (!Number.isInteger(input.effectiveFromGameDay) || input.effectiveFromGameDay < executionGameDay) throw new Error('Frontier effective day is invalid');
  const domain = (await tx.query<{ id: string }>(
    "SELECT id FROM technology_domains WHERE id = $1 AND status = 'ACTIVE'", [input.domainId],
  )).rows[0];
  if (!domain) throw new Error(`Unknown active technology domain: ${input.domainId}`);
  const frontier = await currentFrontier(tx, input.domainId);
  if (input.generationNumber !== frontier + 1) throw new Error('Earth frontier can advance only one generation at a time');
  const generation = (await tx.query<{ predecessor_id: string | null; generation_number: number }>(
    'SELECT predecessor_id, generation_number FROM technology_generations WHERE domain_id = $1 AND generation_number = $2',
    [input.domainId, input.generationNumber],
  )).rows[0];
  if (!generation) throw new Error('Technology generation does not exist for this domain');
  if (generation.predecessor_id) {
    const predecessor = (await tx.query<{ generation_number: number }>(
      'SELECT generation_number FROM technology_generations WHERE id = $1', [generation.predecessor_id],
    )).rows[0];
    if (!predecessor || Number(predecessor.generation_number) !== frontier) throw new Error('Frontier predecessor does not match the current generation');
  }
  const id = `EARTH-FRONTIER-${input.domainId}-${input.generationNumber}`;
  await tx.query(`INSERT INTO earth_technology_frontier_versions
    (id, domain_id, generation_number, predecessor_generation_number, effective_from_game_day,
     research_credit_cost_units, research_resource_costs, authorization_proposal_id,
     created_by_human_id, correlation_id)
    VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,$9,$10)`, [
    id, input.domainId, input.generationNumber, frontier, input.effectiveFromGameDay,
    (input.researchCreditCostUnits ?? 0n).toString(), JSON.stringify(input.researchResourceCosts ?? {}),
    input.proposalId, input.humanId ?? null, input.correlationId,
  ]);
  await tx.query(`UPDATE earth_technology_frontier
                     SET max_generation_number = $2, updated_game_day = $3::BIGINT, updated_at = CURRENT_TIMESTAMP
                   WHERE domain_id = $1 AND $3::BIGINT >= $4::BIGINT`, [input.domainId, input.generationNumber, executionGameDay, input.effectiveFromGameDay]);
  return { ok: true, frontierVersionId: id, domainId: input.domainId, generationNumber: input.generationNumber, effectiveFromGameDay: input.effectiveFromGameDay, correlationId: input.correlationId };
}
