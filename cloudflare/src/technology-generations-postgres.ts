import type { PostgresRepository } from './repository.ts';
import { evaluateGeneration } from './technology-generations.ts';

export async function getTechnologyGenerations(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const day = Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
  const result = await repository.query(`SELECT g.id, d.code AS domain_code, g.generation_number, g.name, g.predecessor_id, g.minimum_game_day, g.research_points_required::TEXT, g.status, (p.id IS NOT NULL) AS predecessor_discovered, (x.id IS NOT NULL) AS discovered FROM technology_generations g JOIN technology_domains d ON d.id = g.domain_id LEFT JOIN technology_discoveries p ON p.generation_id = g.predecessor_id LEFT JOIN technology_discoveries x ON x.generation_id = g.id ORDER BY d.code, g.generation_number`);
  const generations = result.rows.map((row) => ({ ...row, eligibility: evaluateGeneration({ generationId: row.id, minimumGameDay: Number(row.minimum_game_day), currentGameDay: day, predecessorId: row.predecessor_id, predecessorDiscovered: Boolean(row.predecessor_discovered) }) }));
  return { gameDay: day, generations, generatedFrom: 'postgres-canonical-facts' };
}

// @mutation-boundary deterministic-settlement: program progress is advanced once per finalized day.
// @mutation-boundary caller-owned-transaction: each program advancement owns one explicit transaction.
export async function advanceTechnologyGenerationPrograms(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const result = await repository.query<{ id: string }>("SELECT id FROM technology_research_programs WHERE status = 'ACTIVE' ORDER BY id LIMIT 100");
  let completed = 0;
  for (const row of result.rows) await repository.transaction(async (tx) => {
    const program = (await tx.query<{ id: string; generation_id: string; progress_points: string; required_points: string }>("SELECT id, generation_id, progress_points::TEXT, required_points::TEXT FROM technology_research_programs WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [row.id])).rows[0];
    if (!program) return;
    const generation = (await tx.query<{ predecessor_id: string | null; minimum_game_day: number }>('SELECT predecessor_id, minimum_game_day FROM technology_generations WHERE id = $1', [program.generation_id])).rows[0];
    if (!generation || Number(generation.minimum_game_day) > gameDay || generation.predecessor_id && !(await tx.query('SELECT 1 FROM technology_discoveries WHERE generation_id = $1', [generation.predecessor_id])).rows[0]) return;
    const next = BigInt(program.progress_points) + 1n;
    await tx.query('UPDATE technology_research_programs SET progress_points = LEAST($1, required_points) WHERE id = $2', [next.toString(), program.id]);
    if (next >= BigInt(program.required_points)) {
      await tx.query("UPDATE technology_research_programs SET status = 'COMPLETED' WHERE id = $1", [program.id]);
      await tx.query(`INSERT INTO technology_discoveries (id, generation_id, research_program_id, discovered_game_day, effective_from_game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (generation_id) DO NOTHING`, [`DISCOVERY-${program.generation_id}`, program.generation_id, program.id, gameDay, gameDay + 1]);
      await tx.query("UPDATE technology_generations SET status = 'DISCOVERED' WHERE id = $1", [program.generation_id]);
      completed += 1;
    }
  });
  return { ok: true, gameDay, programsScanned: result.rows.length, completed };
}
