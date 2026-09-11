import type { PostgresRepository } from './repository.ts';
import { executeProposal, resolveProposalsInTransaction } from './governance-postgres.ts';

/**
 * Applies only state changes due after one already-committed game day. Every
 * mutation is idempotent, so a retry cannot duplicate an unlock or completion.
 */
export async function processEndOfDayAutomation(repository: PostgresRepository, completedDay: number, completedMinute = 1439): Promise<number> {
  await repository.transaction(async (tx) => {
    // A proposal submitted during D starts at the opening of D + 1.
    await tx.query(
      `UPDATE proposals p
       SET status = 'open', decision_status = 'voting',
           eligible_voter_count = (
             SELECT COUNT(*)
             FROM humans h
             JOIN memberships m ON m.human_id = h.id
             JOIN institutions i ON i.id = p.institution_id
             WHERE h.life_status = 'active'
               AND m.joined_game_day <= p.voting_start_day
               AND ((i.kind = 'CITY' AND m.city_id = p.institution_id)
                 OR (i.kind = 'CORPORATION' AND m.corporation_id = p.institution_id))
           ),
           eligibility_cutoff_game_day = p.voting_start_day
       WHERE p.status = 'scheduled' AND p.voting_start_day <= $1`,
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
        'SELECT earth_economic_state_changed($1, $2, $3, $4, $5)',
        [building.owner_id ?? building.city_id, building.id, 'construction_completed', completedDay, 0],
      );
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
      await tx.query(
        'SELECT earth_economic_state_changed($1, $2, $3, $4, $5)',
        [project.corporation_id, project.id, 'building_technology_upgrade', completedDay, 0],
      );
    }

    const completedTechnologies = await tx.query<{ corporation_id: string; id: string; technology_key: string }>(
      `UPDATE corporation_technology_projects
       SET status = 'completed', progress = 100, completed_game_day = $1, updated_at = CURRENT_TIMESTAMP
       WHERE status = 'active' AND research_due_end_day <= $1
       RETURNING corporation_id, id, technology_key`,
      [completedDay],
    );
    for (const technology of completedTechnologies.rows) {
      await tx.query(
        'SELECT earth_economic_state_changed($1, $2, $3, $4, $5)',
        [technology.corporation_id, technology.id, 'technology_upgrade', completedDay, 0],
      );
    }
    await resolveProposalsInTransaction(tx, completedDay);
  });

  const dueProposals = await repository.query<{ id: string; proposal_id: string; attempt_count: number }>(
    'SELECT id, payload->>\'proposalId\' AS proposal_id, attempt_count FROM earth_claim_scheduled_actions($1,$2,$3,$4,$5,$6)',
    [completedDay, completedMinute, `scheduler-actions:${crypto.randomUUID()}`, 100, 300, 'proposal_execution'],
  );
  for (const action of dueProposals.rows) {
    try {
      const result = await executeProposal(repository, { proposalId: action.proposal_id, humanId: 'SYSTEM', systemExecution: true, completedDay });
      const finished = ['started', 'executed', 'skipped', 'expired_unfunded', 'blocked'].includes(String(result.executionStatus));
      await repository.query(
        `UPDATE scheduled_actions
         SET status = CASE WHEN $2::boolean THEN 'completed' ELSE 'pending' END,
             completed_at = CASE WHEN $2::boolean THEN CURRENT_TIMESTAMP ELSE NULL END,
             lease_owner = NULL, lease_expires_at = NULL, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [action.id, finished],
      );
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 1000) : 'Unknown error';
      await repository.query(
        `UPDATE scheduled_actions
         SET status = CASE WHEN attempt_count >= 5 THEN 'failed' ELSE 'pending' END,
             error_message = $2, lease_owner = NULL, lease_expires_at = NULL, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [action.id, message],
      );
      await repository.query(
        `INSERT INTO settlement_anomalies (game_day, severity, anomaly_type, details)
         VALUES ($1, CASE WHEN (SELECT attempt_count >= 5 FROM scheduled_actions WHERE id = $2) THEN 'error' ELSE 'warning' END,
                 CASE WHEN (SELECT attempt_count >= 5 FROM scheduled_actions WHERE id = $2) THEN 'scheduled_action_failed' ELSE 'proposal_automation_deferred' END,
                 jsonb_build_object('actionId',$2::text,'proposalId',$3::text,'message',$4::text))`,
        [completedDay, action.id, action.proposal_id, message],
      );
    }
  }
  return dueProposals.rows.length;
}
