import type { PostgresRepository } from './repository.ts';

export type InstitutionAction =
  | 'SET_BUDGET'
  | 'CREATE_COMMITMENT'
  | 'APPROVE_SPENDING'
  | 'TRANSFER_TO_RESERVE'
  | 'AUTHORIZE_GRANT'
  | 'CHANGE_TAX_RULE'
  | 'DECLARE_DIVIDEND';

export async function canPerformInstitutionAction(
  tx: PostgresRepository,
  humanId: string,
  institutionId: string,
  action: InstitutionAction,
  gameDay?: number,
): Promise<boolean> {
  const result = await tx.query<{ allowed: boolean }>(
    'SELECT earth_can_perform_institution_action($1, $2, $3, $4) AS allowed',
    [humanId, institutionId, action, gameDay ?? null],
  );
  return Boolean(result.rows[0]?.allowed);
}
