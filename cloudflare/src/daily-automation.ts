import type { PostgresRepository } from './repository.ts';
import { executeProposal, resolveProposalsInTransaction } from './governance-postgres.ts';

/**
 * Applies only state changes due after one already-committed game day. Every
 * mutation is idempotent, so a retry cannot duplicate an unlock or completion.
 */
export async function processEndOfDayAutomation(repository: PostgresRepository, completedDay: number): Promise<void> {
  await repository.transaction(async (tx) => {
    // A proposal submitted during D starts at the opening of D + 1.
    await tx.query(
      "UPDATE proposals SET status = 'open' WHERE status = 'scheduled' AND voting_start_day <= $1",
      [completedDay + 1],
    );

    const buildings = await tx.query<{ id: string; name: string; city_id: string | null; owner_id: string | null }>(
      `UPDATE buildings
       SET status = 'active', construction_progress = 100, construction_completed_day = $1, updated_at = CURRENT_TIMESTAMP
       WHERE status = 'under_construction' AND construction_due_end_day <= $1
       RETURNING id, name, city_id, owner_id`,
      [completedDay],
    );
    for (const building of buildings.rows) {
      await tx.query(
        `INSERT INTO world_events (id, game_day, event_type, title, details)
         VALUES ($1,$2,'building.constructed',$3,jsonb_build_object('buildingId',$4::text,'cityId',$5::text,'ownerId',$6::text)::text)
         ON CONFLICT (id) DO NOTHING`,
        [`BLD-CONSTRUCTED-${building.id}-${completedDay}`, completedDay, `Facility ${building.name} construction completed`, building.id, building.city_id, building.owner_id],
      );
    }

    const completedResearch = await tx.query<{ corporation_id: string; catalog_id: string; id: string }>(
      `UPDATE corporation_building_research_projects
       SET status = 'completed', progress = 100, research_completed_day = $1, completed_game_day = $1, updated_at = CURRENT_TIMESTAMP
       WHERE status = 'active' AND research_due_end_day <= $1
       RETURNING corporation_id, catalog_id, id`,
      [completedDay],
    );
    for (const project of completedResearch.rows) {
      await tx.query('UPDATE building_catalog SET is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1', [project.catalog_id]);
      await tx.query(
        `INSERT INTO corporation_building_unlocks (corporation_id, catalog_id, research_project_id, unlocked_game_day)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (corporation_id, catalog_id) DO UPDATE
           SET status = 'unlocked', research_project_id = EXCLUDED.research_project_id, unlocked_game_day = EXCLUDED.unlocked_game_day`,
        [project.corporation_id, project.catalog_id, project.id, completedDay],
      );
    }

    await tx.query(
      `UPDATE corporation_technology_projects
       SET status = 'completed', progress = 100, completed_game_day = $1, updated_at = CURRENT_TIMESTAMP
       WHERE status = 'active' AND research_due_end_day <= $1`,
      [completedDay],
    );
    await resolveProposalsInTransaction(tx, completedDay);
  });

  const dueProposals = await repository.query<{ id: string; proposal_id: string }>(
    `SELECT a.id, a.payload->>'proposalId' AS proposal_id
     FROM scheduled_actions a
     JOIN proposals p ON p.id = a.payload->>'proposalId'
     WHERE a.action_type = 'proposal_execution' AND a.status = 'pending'
       AND a.due_end_game_day <= $1
       AND p.outcome = 'passed' AND p.executed_at IS NULL
       AND p.execution_status IN ('ready', 'awaiting_funding')
       AND (p.funding_start_day IS NULL OR p.funding_start_day <= $1)
     ORDER BY a.priority, a.due_end_game_day, a.created_at
     FOR UPDATE SKIP LOCKED`,
    [completedDay],
  );
  for (const action of dueProposals.rows) {
    try {
      const result = await executeProposal(repository, { proposalId: action.proposal_id, humanId: 'SYSTEM', systemExecution: true, completedDay });
      const finished = ['executed', 'skipped', 'expired_unfunded', 'blocked'].includes(String(result.executionStatus));
      await repository.query(
        `UPDATE scheduled_actions
         SET status = CASE WHEN $2::boolean THEN 'completed' ELSE 'pending' END,
             completed_at = CASE WHEN $2::boolean THEN CURRENT_TIMESTAMP ELSE NULL END,
             attempt_count = attempt_count + 1, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [action.id, finished],
      );
    } catch (error) {
      await repository.query(
        `INSERT INTO settlement_anomalies (game_day, severity, anomaly_type, details)
         VALUES ($1, 'warning', 'proposal_automation_deferred', jsonb_build_object('proposalId',$2::text,'message',$3::text))`,
        [completedDay, action.proposal_id, error instanceof Error ? error.message.slice(0, 1000) : 'Unknown error'],
      );
    }
  }
}
