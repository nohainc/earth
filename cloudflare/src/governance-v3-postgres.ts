import type { PostgresRepository } from './repository.ts';

type ProposalInput = {
  humanId: string;
  institutionId: string;
  title: string;
  body: string;
  targetCategory: string | null;
  targetValue: Record<string, unknown> | null;
  correlationId: string;
};

const TARGET_CATEGORIES = new Set(['market', 'finance', 'services', 'technology', 'territory']);

async function authorize(tx: PostgresRepository, humanId: string, institutionId: string): Promise<{ kind: string }> {
  const institution = (await tx.query<{ kind: string }>(
    "SELECT kind FROM institutions WHERE id = $1 AND status = 'ACTIVE' AND kind IN ('EARTH', 'CORPORATION') FOR SHARE", [institutionId],
  )).rows[0];
  if (!institution) throw new Error('Only EARTH and Corporation may govern');
  const human = (await tx.query("SELECT 1 FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Human is not active');
  if (institution.kind === 'CORPORATION') {
    const member = (await tx.query("SELECT 1 FROM house_affiliations ha JOIN humans h ON h.house_id = ha.house_id WHERE h.id = $1 AND ha.corporation_id = $2 AND ha.status = 'ACTIVE'", [humanId, institutionId])).rows[0];
    if (!member) throw new Error('Corporation membership is required');
  }
  return institution;
}

export async function createProposalV3(repository: PostgresRepository, input: ProposalInput): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query('SELECT * FROM proposals WHERE institution_id = $1 AND target_value->>\'correlationId\' = $2', [input.institutionId, input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, proposal: prior, correlationId: input.correlationId };
    const institution = await authorize(tx, input.humanId, input.institutionId);
    if (input.targetCategory && !TARGET_CATEGORIES.has(input.targetCategory)) throw new Error('Unsupported proposal target category');
    const value = input.targetValue ?? {};
    const targetType = input.targetCategory === 'territory' ? 'TERRITORY' : 'INSTITUTION';
    const targetId = targetType === 'TERRITORY' ? String(value.territoryId ?? '') : null;
    if (targetType === 'TERRITORY' && !targetId) throw new Error('Territory-targeted proposals require territoryId');
    if (targetId) {
      const territory = (await tx.query<{ corporation_id: string }>('SELECT corporation_id FROM territories WHERE id = $1 AND status = \'ACTIVE\'', [targetId])).rows[0];
      if (!territory) throw new Error('Territory not found or inactive');
      if (institution.kind === 'CORPORATION' && territory.corporation_id !== input.institutionId) throw new Error('Corporation may only target its own Territory');
    }
    const gameDay = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const proposalId = `P-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const targetValue = { ...value, correlationId: input.correlationId, category: input.targetCategory };
    await tx.query(`INSERT INTO proposals
      (id, institution_id, created_by_human_id, action_type, target_type, target_id, target_value, status, created_game_day)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'OPEN', $8)`,
      [proposalId, input.institutionId, input.humanId, input.targetCategory ?? 'generic', targetType, targetId, JSON.stringify(targetValue), gameDay]);
    return { ok: true, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [proposalId])).rows[0], politicalArena: institution.kind, correlationId: input.correlationId };
  });
}

export async function castVoteV3(repository: PostgresRepository, input: { proposalId: string; humanId: string; choice: 'support' | 'oppose' | 'abstain' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<{ institution_id: string }>('SELECT institution_id FROM proposals WHERE id = $1 AND status = \'OPEN\' FOR UPDATE', [input.proposalId])).rows[0];
    if (!proposal) throw new Error('Open proposal not found');
    await authorize(tx, input.humanId, proposal.institution_id);
    const house = (await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1', [input.humanId])).rows[0];
    if (!house) throw new Error('House not found');
    await tx.query(`INSERT INTO ballots (proposal_id, house_id, cast_by_human_id, choice)
      VALUES ($1, $2, $3, $4) ON CONFLICT (proposal_id, house_id) DO UPDATE SET cast_by_human_id = EXCLUDED.cast_by_human_id, choice = EXCLUDED.choice`, [input.proposalId, house.house_id, input.humanId, input.choice]);
    return { ok: true, proposalId: input.proposalId, choice: input.choice };
  });
}
