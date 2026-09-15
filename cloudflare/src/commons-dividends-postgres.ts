import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';

export type CommonsEligibleHolder = { houseId: string; slotQuantity: bigint };

/** Deterministic integer allocation; the final sorted holder receives the remainder. */
export function allocateCommonsDividend(totalUnits: bigint, holders: readonly CommonsEligibleHolder[]) {
  if (totalUnits < 0n) throw new Error('Dividend total cannot be negative');
  const ordered = [...holders].sort((a, b) => a.houseId.localeCompare(b.houseId));
  const totalSlots = ordered.reduce((sum, holder) => sum + holder.slotQuantity, 0n);
  if (totalSlots <= 0n || totalUnits === 0n) return ordered.map((holder) => ({ ...holder, amountUnits: 0n, remainderUnits: 0n }));
  let allocated = 0n;
  return ordered.map((holder, index) => {
    const base = totalUnits * holder.slotQuantity / totalSlots;
    const amountUnits = index === ordered.length - 1 ? totalUnits - allocated : base;
    allocated += amountUnits;
    return { ...holder, amountUnits, remainderUnits: index === ordered.length - 1 ? amountUnits - base : 0n };
  });
}

async function currentDay(tx: PostgresRepository) {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

async function houseForHuman(tx: PostgresRepository, humanId: string) {
  return (await tx.query<{ house_id: string; economic_id: string }>(`SELECT h.house_id, o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE' WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId])).rows[0];
}

async function beneficiary(tx: PostgresRepository, territoryId: string) {
  return (await tx.query<{ institution_id: string; economic_id: string; account_id: string }>(
    `SELECT COALESCE(g.governing_institution_id, t.corporation_id) AS institution_id, o.economic_id, a.id::TEXT AS account_id
       FROM territories t
       LEFT JOIN territory_governance g ON g.territory_id = t.id AND g.status = 'ACTIVE'
       JOIN owner_registry o ON o.id = COALESCE(g.governing_institution_id, t.corporation_id)
       JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1
        AND a.account_type IN ('OPERATIONS','TREASURY') AND a.status = 'ACTIVE'
      WHERE t.id = $1
      ORDER BY CASE a.account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END LIMIT 1`, [territoryId],
  )).rows[0];
}

async function requireAuthority(tx: PostgresRepository, institutionId: string, humanId: string, houseId: string) {
  const kind = (await tx.query<{ owner_type: string }>('SELECT owner_type FROM owner_registry WHERE id = $1', [institutionId])).rows[0]?.owner_type;
  if (kind === 'ORGANIZATION') {
    await resolveOrganizationAuthority(tx, { organizationId: institutionId, humanId, action: 'GOVERNANCE' });
    return;
  }
  const allowed = await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code IN ('CORPORATION_EXECUTIVE','CORPORATION_TREASURER','CORPORATION_GOVERNOR')`, [institutionId, humanId]);
  if (!allowed.rows[0]) throw new Error('Commons dividend governance authority is required');
  void houseId;
}

export async function getCommonsStatement(repository: PostgresRepository, territoryId: string) {
  const [policy, declarations, revenue] = await Promise.all([
    repository.query('SELECT * FROM commons_dividend_policies WHERE territory_id = $1 AND status = \'ACTIVE\'', [territoryId]),
    repository.query('SELECT * FROM commons_dividend_declarations WHERE territory_id = $1 ORDER BY game_day DESC LIMIT 30', [territoryId]),
    repository.query(`SELECT game_day, COALESCE(SUM(amount_units),0)::TEXT AS lease_revenue_units FROM territory_lease_payments WHERE territory_id = $1 AND status = 'PAID' GROUP BY game_day ORDER BY game_day DESC LIMIT 30`, [territoryId]),
  ]);
  return { territoryId, policy: policy.rows[0] ?? null, declarations: declarations.rows, leaseRevenue: revenue.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function declareCommonsDividend(repository: PostgresRepository, input: { humanId: string; territoryId: string; gameDay?: number; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const house = await houseForHuman(tx, input.humanId);
    if (!house) throw new Error('Active House is required');
    const territory = (await tx.query<{ corporation_id: string }>("SELECT corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    const authority = await beneficiary(tx, input.territoryId);
    if (!authority) throw new Error('Territory commons beneficiary is not configured');
    await requireAuthority(tx, authority.institution_id, input.humanId, house.house_id);
    const day = input.gameDay ?? await currentDay(tx);
    if (!Number.isInteger(day) || day < 1) throw new Error('gameDay must be a positive integer');
    const policy = (await tx.query<{ reserve_bps: number; dividend_bps: number; effective_from_game_day: number; rules_version: string }>(`SELECT reserve_bps, dividend_bps, effective_from_game_day, rules_version FROM commons_dividend_policies WHERE territory_id = $1 AND status = 'ACTIVE' AND effective_from_game_day <= $2 ORDER BY effective_from_game_day DESC LIMIT 1 FOR UPDATE`, [input.territoryId, day])).rows[0];
    if (!policy) throw new Error('No active commons dividend policy is available');
    const existing = (await tx.query('SELECT * FROM commons_dividend_declarations WHERE territory_id = $1 AND game_day = $2', [input.territoryId, day])).rows[0];
    if (existing) return { ok: true, alreadyProcessed: true, declaration: existing, correlationId: input.correlationId };
    const revenue = BigInt((await tx.query<{ units: string }>(`SELECT COALESCE(SUM(amount_units),0)::TEXT AS units FROM territory_lease_payments WHERE territory_id = $1 AND game_day = $2 AND status = 'PAID'`, [input.territoryId, day])).rows[0]?.units ?? '0');
    const reserve = revenue * BigInt(policy.reserve_bps) / 10_000n;
    const distributable = revenue * BigInt(policy.dividend_bps) / 10_000n;
    const id = `COMMONS-DECL-${input.territoryId}-${day}`;
    await tx.query(`INSERT INTO commons_dividend_declarations (id,territory_id,game_day,revenue_units,reserve_units,distributable_units,policy_snapshot,beneficiary_economic_id,declared_by_human_id,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,$9,$10)`, [id, input.territoryId, day, revenue.toString(), reserve.toString(), distributable.toString(), JSON.stringify(policy), authority.economic_id, input.humanId, input.correlationId]);
    await createGameEvent(tx, { id: `COMMONS-DECL-EVENT-${input.correlationId}`, category: 'TERRITORY', eventType: 'COMMONS_DIVIDEND_DECLARED', gameDay: day, actorHumanId: input.humanId, subjectType: 'TERRITORY', subjectId: input.territoryId, title: 'Commons dividend declared', details: { declarationId: id, revenueUnits: revenue.toString(), reserveUnits: reserve.toString(), distributableUnits: distributable.toString(), rulesVersion: policy.rules_version }, correlationId: input.correlationId });
    return { ok: true, declaration: (await tx.query('SELECT * FROM commons_dividend_declarations WHERE id = $1', [id])).rows[0], correlationId: input.correlationId };
  });
}

export async function settleCommonsDividends(repository: PostgresRepository, day: number) {
  const declarations = await repository.query<{ id: string; territory_id: string; game_day: number; distributable_units: string; beneficiary_economic_id: string }>(`SELECT id, territory_id, game_day, distributable_units::TEXT, beneficiary_economic_id FROM commons_dividend_declarations WHERE status = 'DECLARED' AND game_day < $1 ORDER BY id`, [day]);
  let settled = 0;
  let blocked = 0;
  for (const declaration of declarations.rows) {
    {
      const tx = repository;
      const locked = (await tx.query<{ status: string }>('SELECT status FROM commons_dividend_declarations WHERE id = $1 FOR UPDATE', [declaration.id])).rows[0];
      if (!locked || locked.status !== 'DECLARED') return;
      const holders = await tx.query<{ house_id: string; slot_quantity: string }>(`SELECT holder_id AS house_id, SUM(slot_quantity)::TEXT AS slot_quantity FROM territory_rights WHERE territory_id = $1 AND holder_type = 'HOUSE' AND status IN ('ACTIVE','HOLDOVER') AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2) GROUP BY holder_id ORDER BY holder_id`, [declaration.territory_id, declaration.game_day]);
      const totalSlots = holders.rows.reduce((sum, row) => sum + BigInt(row.slot_quantity), 0n);
      const distributable = BigInt(declaration.distributable_units);
      const source = (await tx.query<{ id: string; balance_units: string }>(`SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type IN ('OPERATIONS','TREASURY') AND a.status = 'ACTIVE' ORDER BY CASE a.account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END LIMIT 1 FOR UPDATE`, [declaration.beneficiary_economic_id])).rows[0];
      if (totalSlots === 0n || !source || BigInt(source.balance_units) < distributable) {
        await tx.query("UPDATE commons_dividend_declarations SET status = 'BLOCKED' WHERE id = $1", [declaration.id]);
        blocked += 1;
        return;
      }
      const allocations = allocateCommonsDividend(distributable, holders.rows.map((holder) => ({ houseId: holder.house_id, slotQuantity: BigInt(holder.slot_quantity) })));
      for (const allocation of allocations) {
        const holder = holders.rows.find((candidate) => candidate.house_id === allocation.houseId)!;
        const amount = allocation.amountUnits;
        const wallet = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' FOR UPDATE`, [holder.house_id])).rows[0];
        if (!wallet) continue;
        const paymentCorrelation = `commons-payment:${declaration.id}:${holder.house_id}`;
        await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','COMMONS_DIVIDEND',$3,'commons-dividend-v1',$4::JSONB)`, [paymentCorrelation, day, declaration.id, JSON.stringify([{ account_id: source.id, asset_id: 1, delta_units: (-amount).toString() }, { account_id: wallet.id, asset_id: 1, delta_units: amount.toString() }])]);
        await tx.query(`INSERT INTO commons_dividend_payments (id,declaration_id,territory_id,house_id,eligible_slot_quantity,amount_units,remainder_units,economic_transaction_id,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,(SELECT id FROM economic_transactions WHERE correlation_id=$8),$8) ON CONFLICT (correlation_id) DO NOTHING`, [`COMMONS-PAYMENT-${declaration.id}-${holder.house_id}`, declaration.id, declaration.territory_id, holder.house_id, holder.slot_quantity, amount.toString(), allocation.remainderUnits.toString(), paymentCorrelation, paymentCorrelation]);
      }
      await tx.query("UPDATE commons_dividend_declarations SET status = 'SETTLED' WHERE id = $1", [declaration.id]);
      settled += 1;
    }
  }
  return { ok: true, day, settled, blocked };
}
