import type { PostgresRepository } from './repository.ts';
import { spendBudget } from './institution-spending.ts';

export type GrantApprovalInput = {
  grantorInstitutionId: string;
  recipientInstitutionId: string;
  budgetLineId: string;
  amountUnits: bigint;
  grantType: string;
  correlationId: string;
  gameDay: number;
  dueGameDay?: number;
};

export async function approveInstitutionGrant(tx: PostgresRepository, input: GrantApprovalInput): Promise<Record<string, unknown>> {
  const existing = await tx.query('SELECT * FROM institution_grants WHERE correlation_id = $1', [input.correlationId]);
  if (existing.rows[0]) return existing.rows[0];
  if (input.grantorInstitutionId === input.recipientInstitutionId || input.amountUnits <= 0n) throw new Error('Invalid institutional grant');
  const commitment = await tx.query<{ id: string }>(
    'SELECT earth_create_budget_commitment($1,$2,\'GRANT\',\'institution_grant\',$3,$4,$5,$6) AS id',
    [input.grantorInstitutionId, input.budgetLineId, input.correlationId, input.amountUnits, input.gameDay, input.dueGameDay ?? input.gameDay],
  );
  const result = await tx.query(
    `INSERT INTO institution_grants
      (grantor_institution_id, recipient_institution_id, budget_line_id, commitment_id, amount_units, grant_type, correlation_id, created_game_day)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING *`,
    [input.grantorInstitutionId, input.recipientInstitutionId, input.budgetLineId, commitment.rows[0].id, input.amountUnits, input.grantType, input.correlationId, input.gameDay],
  );
  return result.rows[0];
}

export async function payInstitutionGrant(
  tx: PostgresRepository,
  input: { grantId: string; sourceAccountId: string; recipientAccountId: string; correlationId: string; gameDay: number },
): Promise<Record<string, unknown>> {
  const grant = await tx.query<{ grantor_institution_id: string; budget_line_id: string; commitment_id: string | null; recipient_institution_id: string; amount_units: string; status: string }>(
    'SELECT grantor_institution_id, budget_line_id, commitment_id, recipient_institution_id, amount_units, status FROM institution_grants WHERE id = $1 FOR UPDATE',
    [input.grantId],
  );
  if (!grant.rows[0] || grant.rows[0].status !== 'APPROVED' || !grant.rows[0].commitment_id) throw new Error('Grant is not payable');
  const posting = await spendBudget(tx, {
    institutionId: grant.rows[0].grantor_institution_id,
    budgetLineId: grant.rows[0].budget_line_id,
    sourceAccountId: input.sourceAccountId,
    recipientAccountId: input.recipientAccountId,
    amountUnits: BigInt(grant.rows[0].amount_units),
    purpose: 'INSTITUTION_GRANT',
    sourceType: 'institution_grant',
    sourceId: input.grantId,
    correlationId: input.correlationId,
    gameDay: input.gameDay,
    commitmentId: grant.rows[0].commitment_id,
  });
  await tx.query('UPDATE institution_grants SET status = \'PAID\', paid_game_day = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [input.gameDay, input.grantId]);
  await tx.query(`SELECT earth_record_institution_financial_event($1,$2,'GRANT_SENT',$3,$4,$5::bigint,$6,NULL,NULL,$7), earth_record_institution_financial_event($8,$2,'GRANT_RECEIVED',$3,NULL,$5::bigint,$6,NULL,NULL,$7)`, [grant.rows[0].grantor_institution_id, input.gameDay, BigInt(grant.rows[0].amount_units), grant.rows[0].budget_line_id, posting.transactionId, input.grantId, input.correlationId, grant.rows[0].recipient_institution_id]);
  return { ...posting, grantId: input.grantId, recipientInstitutionId: grant.rows[0].recipient_institution_id };
}

export async function restrictInstitutionGrant(
  tx: PostgresRepository,
  input: { grantId: string; recipientInstitutionId: string; budgetLineId: string; categoryId: string; amountUnits: bigint; gameDay: number },
): Promise<Record<string, unknown>> {
  const grant = await tx.query<{ recipient_institution_id: string; amount_units: string; status: string }>('SELECT recipient_institution_id, amount_units, status FROM institution_grants WHERE id = $1 FOR UPDATE', [input.grantId]);
  if (!grant.rows[0] || grant.rows[0].status !== 'PAID' || grant.rows[0].recipient_institution_id !== input.recipientInstitutionId) throw new Error('Grant is not eligible for restriction');
  if (input.amountUnits <= 0n || input.amountUnits > BigInt(grant.rows[0].amount_units)) throw new Error('Invalid grant restriction amount');
  const result = await tx.query(
    `INSERT INTO grant_restrictions (grant_id, recipient_institution_id, budget_line_id, category_id, original_units, remaining_units, created_game_day)
     VALUES ($1,$2,$3,$4,$5,$5,$6)
     ON CONFLICT (grant_id, budget_line_id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
     RETURNING *`,
    [input.grantId, input.recipientInstitutionId, input.budgetLineId, input.categoryId, input.amountUnits, input.gameDay],
  );
  return result.rows[0];
}
