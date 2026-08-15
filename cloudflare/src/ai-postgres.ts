import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';

export async function listAssistants(repository: PostgresRepository, ownerId: string): Promise<Record<string, unknown>> {
  return { assistants: (await repository.query('SELECT id, tier, policy, enabled, created_at FROM ai_assistants WHERE owner_id = $1 ORDER BY id', [ownerId])).rows };
}

export async function updateAssistantPolicy(repository: PostgresRepository, input: { ownerId: string; assistantId: string; policy: string; enabled: boolean }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const result = await tx.query("UPDATE ai_assistants SET policy = $1, enabled = $2 WHERE id = $3 AND owner_id = $4 AND tier IN ('basic','business')", [input.policy, input.enabled, input.assistantId, input.ownerId]);
    if (result.rowCount !== 1) throw new Error('AI assistant not found');
    return { ok: true, assistant: (await tx.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE id = $1', [input.assistantId])).rows[0] };
  });
}

export async function upgradeAssistant(repository: PostgresRepository, input: { ownerId: string; assistantId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const assistant = await tx.query<{ id: string; tier: string }>('SELECT id, tier FROM ai_assistants WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.assistantId, input.ownerId]);
    if (!assistant.rows[0]) throw new Error('AI assistant not found');
    if (assistant.rows[0].tier === 'business') return { ok: true, alreadyUpgraded: true, assistant: assistant.rows[0] };
    const cost = 2400;
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    if (!account.rows[0] || Number(account.rows[0].balance) < cost) throw new Error('Insufficient Credits for Business AI upgrade');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const correlationId = `AI-UPGRADE-${assistant.rows[0].id}`;
    const prior = await tx.query("SELECT id FROM ledger_entries WHERE reason_type = 'ai_upgrade' AND correlation_id = $1", [correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, cost, correlationId, assistant: (await tx.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE id = $1', [input.assistantId])).rows[0] };
    const transfer = await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay,
      debitAccount: account.rows[0].account_id,
      creditAccount: 'account-ouc-treasury',
      amount: cost,
      reasonType: 'ai_upgrade',
      reasonId: input.assistantId,
      ruleVersion: 'ai-v1',
      correlationId,
    });
    if (transfer.status === 'already_processed') return { ok: true, alreadyProcessed: true, cost, correlationId, assistant: (await tx.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE id = $1', [input.assistantId])).rows[0] };
    await tx.query("UPDATE ai_assistants SET tier = 'business' WHERE id = $1 AND owner_id = $2", [input.assistantId, input.ownerId]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Business AI activated', 'Your AI assistant now supports bounded business maintenance automation and recommendation policies.', input.assistantId]);
    return { ok: true, cost, correlationId, assistant: (await tx.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE id = $1', [input.assistantId])).rows[0] };
  });
}
