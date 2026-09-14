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
             JOIN house_affiliations m ON m.house_id = h.house_id AND m.status = 'ACTIVE'
             JOIN institutions i ON i.id = p.institution_id
             WHERE h.status = 'ACTIVE'
               AND i.kind IN ('EARTH', 'CORPORATION')
               AND (i.kind = 'EARTH' OR m.corporation_id = p.institution_id)
           )
       WHERE p.status = 'OPEN'`,
      [completedDay + 1],
    );

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
