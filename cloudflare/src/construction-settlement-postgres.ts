import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

// @mutation-boundary caller-owned-transaction: invoked by the settlement worker inside its phase transaction.
export async function completeDueConstructionProjects(repository: PostgresRepository, day: number, shard = 0, shardCount = 1): Promise<{ completed: number }> {
  const projects = await repository.query<{ id: string; building_id: string; owner_economic_id: string; territory_id: string; project_kind: string; target_generation_id: string | null }>(
    `SELECT id, building_id, owner_economic_id, territory_id
       FROM construction_projects
      WHERE status = 'IN_PROGRESS' AND expected_completion_game_day <= $1
        AND MOD(ABS(hashtextextended(owner_economic_id, 0)), $2) = $3
      ORDER BY expected_completion_game_day, id`, [day, shardCount, shard],
  );
  let completed = 0;
  for (const project of projects.rows) {
    const updated = await repository.query<{ id: string }>(
      `UPDATE construction_projects SET status = 'COMPLETED', completed_game_day = $2, updated_at = CURRENT_TIMESTAMP
        WHERE id = $1 AND status = 'IN_PROGRESS' RETURNING id`, [project.id, day],
    );
    if (!updated.rows[0]) continue;
    await repository.query(`UPDATE buildings SET status = 'ACTIVE', commissioned_game_day = $2 WHERE id = $1 AND status = 'UNDER_CONSTRUCTION'`, [project.building_id, day]);
    if (project.project_kind === 'OVERHAUL') await repository.query('UPDATE buildings SET last_major_rebuild_game_day = $2 WHERE id = $1', [project.building_id, day]);
    if (project.project_kind === 'GENERATION_RETROFIT' && project.target_generation_id) {
      const generation = (await repository.query<{ domain_id: string; effective_from_game_day: number }>('SELECT domain_id, COALESCE((SELECT effective_from_game_day FROM technology_discoveries WHERE generation_id = $1), 0) AS effective_from_game_day FROM technology_generations WHERE id = $1', [project.target_generation_id])).rows[0];
      if (!generation || Number(generation.effective_from_game_day) > day) throw new Error('Generation retrofit completed before discovery became effective');
      await repository.query(`INSERT INTO building_generation_installations (id, building_id, domain_id, generation_id, installed_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (building_id, domain_id, status) DO UPDATE SET generation_id = EXCLUDED.generation_id, installed_game_day = EXCLUDED.installed_game_day, correlation_id = EXCLUDED.correlation_id`, [`INSTALL-${project.id}`, project.building_id, generation.domain_id, project.target_generation_id, day, `retrofit-install:${project.id}`]);
    }
    await repository.query('SELECT earth_refresh_territory_capacity($1, $2)', [project.territory_id, day]);
    await createGameEvent(repository, {
      id: `PROJECT-COMPLETED-${project.id}`,
      category: 'BUILDING', eventType: 'CONSTRUCTION_COMPLETED', gameDay: day,
      subjectType: 'BUILDING', subjectId: project.building_id,
      title: 'Construction project completed',
      details: { projectId: project.id, ownerEconomicId: project.owner_economic_id, territoryId: project.territory_id },
      correlationId: `construction-complete:${project.id}:${day}`,
    });
    completed += 1;
  }
  return { completed };
}
