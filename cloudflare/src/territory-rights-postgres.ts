import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

const MAX_RIGHT_DAYS = 365;
const BASE_RENT_UNITS = 10n;

type LeaseInput = { humanId: string; territoryId: string; slotClass: 'PRIVATE' | 'PUBLIC'; slotQuantity: bigint; termDays: number; correlationId: string };

async function houseForHuman(tx: PostgresRepository, humanId: string) {
  return (await tx.query<{ house_id: string; economic_id: string }>(
    `SELECT h.house_id, o.economic_id
       FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
      WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId],
  )).rows[0];
}

async function worldDay(tx: PostgresRepository) {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

async function beneficiaryAccount(tx: PostgresRepository, territoryId: string) {
  return (await tx.query<{ economic_id: string; account_id: string }>(
    `SELECT o.economic_id, a.id::TEXT AS account_id
       FROM territories t
       LEFT JOIN territory_governance g ON g.territory_id = t.id AND g.status = 'ACTIVE'
       JOIN owner_registry o ON o.id = COALESCE(g.governing_institution_id, t.corporation_id)
                            AND o.owner_type IN ('CORPORATION','ORGANIZATION')
       JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
                              AND a.asset_id = 1 AND a.account_type IN ('OPERATIONS','TREASURY') AND a.status = 'ACTIVE'
      WHERE t.id = $1
      ORDER BY CASE a.account_type WHEN 'OPERATIONS' THEN 0 ELSE 1 END
      LIMIT 1`, [territoryId],
  )).rows[0];
}

export async function listTerritoryRights(repository: PostgresRepository, input: { territoryId?: string; humanId?: string } = {}) {
  const params: unknown[] = [];
  const predicates = ["r.status IN ('ACTIVE','HOLDOVER')"];
  if (input.territoryId) { params.push(input.territoryId); predicates.push(`r.territory_id = $${params.length}`); }
  if (input.humanId) { params.push(input.humanId); predicates.push(`r.holder_type = 'HOUSE' AND r.holder_id = (SELECT house_id FROM humans WHERE id = $${params.length})`); }
  const result = await repository.query(
    `SELECT r.*, t.name AS territory_name
       FROM territory_rights r JOIN territories t ON t.id = r.territory_id
      WHERE ${predicates.join(' AND ')}
      ORDER BY r.territory_id, r.slot_class, r.id`, params,
  );
  return { rights: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function acquireTerritoryRight(repository: PostgresRepository, input: LeaseInput) {
  if (input.slotQuantity < 1n || input.slotQuantity > 1000n) throw new Error('slotQuantity must be between 1 and 1000');
  if (!Number.isInteger(input.termDays) || input.termDays < 1 || input.termDays > MAX_RIGHT_DAYS) throw new Error(`termDays must be between 1 and ${MAX_RIGHT_DAYS}`);
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM territory_rights WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, right: (await tx.query('SELECT * FROM territory_rights WHERE id = $1', [prior.id])).rows[0], correlationId: input.correlationId };
    const house = await houseForHuman(tx, input.humanId);
    if (!house) throw new Error('Active House is required');
    const day = await worldDay(tx);
    const territory = (await tx.query<{ id: string; corporation_id: string }>("SELECT id, corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    if (input.slotClass !== 'PRIVATE') throw new Error('Only private House rights are currently available');
    const capacity = (await tx.query<{ private_slot_capacity: string }>('SELECT private_slot_capacity::TEXT FROM territory_capacity_state WHERE territory_id = $1 FOR UPDATE', [input.territoryId])).rows[0];
    if (!capacity) throw new Error('Territory capacity projection is unavailable');
    const used = (await tx.query<{ units: string }>(`SELECT COALESCE(SUM(slot_quantity),0)::TEXT AS units FROM territory_rights WHERE territory_id = $1 AND slot_class = 'PRIVATE' AND status IN ('ACTIVE','HOLDOVER') AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)`, [input.territoryId, day])).rows[0]?.units ?? '0';
    if (BigInt(used) + input.slotQuantity > BigInt(capacity.private_slot_capacity)) throw new Error('Territory private right capacity exceeded');
    const beneficiary = await beneficiaryAccount(tx, input.territoryId);
    const wallet = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`, [house.economic_id])).rows[0];
    const rent = BASE_RENT_UNITS * input.slotQuantity;
    if (!wallet || BigInt(wallet.balance_units) < rent) throw new Error('Insufficient CREDIT for Territory right rent');
    if (!beneficiary) throw new Error('Territory commons beneficiary account is not configured');
    const rightId = `RIGHT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','COMMONS_LEASE_RENT',$3,'territory-lease-v1',$4::JSONB)`, [input.correlationId, day, rightId, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-rent).toString() }, { account_id: beneficiary.account_id, asset_id: 1, delta_units: rent.toString() }])]);
    const endDay = day + input.termDays - 1;
    await tx.query(`INSERT INTO territory_rights (id, territory_id, holder_type, holder_id, slot_class, slot_quantity, rent_per_game_day_units, effective_from_game_day, effective_to_game_day, acquired_transaction_id, correlation_id) VALUES ($1,$2,'HOUSE',$3,$4,$5,$6,$7,$8,(SELECT id FROM economic_transactions WHERE correlation_id=$9),$9)`, [rightId, input.territoryId, house.house_id, input.slotClass, input.slotQuantity.toString(), rent.toString(), day, endDay, input.correlationId]);
    await tx.query(`INSERT INTO territory_right_events (id,right_id,event_type,game_day,previous_status,next_status,correlation_id) VALUES ($1,$2,'ACQUIRED',$3,NULL,'ACTIVE',$4)`, [`RIGHT-EVENT-${rightId}`, rightId, day, `right-event:${input.correlationId}`]);
    await createGameEvent(tx, { id: `TERRITORY-RIGHT-${input.correlationId}`, category: 'TERRITORY', eventType: 'TERRITORY_RIGHT_ACQUIRED', gameDay: day, actorHumanId: input.humanId, subjectType: 'TERRITORY_RIGHT', subjectId: rightId, title: 'Territory use right acquired', details: { rightId, territoryId: input.territoryId, slotQuantity: input.slotQuantity.toString(), rentPerGameDayUnits: rent.toString(), effectiveToGameDay: endDay }, correlationId: input.correlationId });
    return { ok: true, right: (await tx.query('SELECT * FROM territory_rights WHERE id = $1', [rightId])).rows[0], rentPaidUnits: rent.toString(), correlationId: input.correlationId };
  });
}

export async function releaseTerritoryRight(repository: PostgresRepository, input: { humanId: string; rightId: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const house = await houseForHuman(tx, input.humanId);
    const right = (await tx.query<{ id: string; holder_id: string; status: string; territory_id: string }>(`SELECT id, holder_id, status, territory_id FROM territory_rights WHERE id = $1 AND holder_type = 'HOUSE' FOR UPDATE`, [input.rightId])).rows[0];
    if (!house || !right || right.holder_id !== house.house_id) throw new Error('Territory right not found');
    if (right.status === 'RELEASED' || right.status === 'EXPIRED') return { ok: true, alreadyProcessed: true, rightId: input.rightId, correlationId: input.correlationId };
    const day = await worldDay(tx);
    await tx.query(`UPDATE territory_rights SET status='RELEASED', released_game_day=$2, effective_to_game_day=LEAST(COALESCE(effective_to_game_day,$2),$2) WHERE id=$1`, [input.rightId, day]);
    await tx.query(`INSERT INTO territory_right_events (id,right_id,event_type,game_day,previous_status,next_status,correlation_id) VALUES ($1,$2,'RELEASED',$3,$4,'RELEASED',$5)`, [`RIGHT-EVENT-${input.correlationId}`, input.rightId, day, right.status, `right-event:${input.correlationId}`]);
    return { ok: true, status: 'RELEASED', rightId: input.rightId, correlationId: input.correlationId };
  });
}

export async function settleTerritoryLeases(repository: PostgresRepository, day: number, shard = 0, shardCount = 1) {
  const rights = await repository.query<{ id: string; territory_id: string; holder_id: string; holder_type: string; rent_per_game_day_units: string; effective_to_game_day: string | null }>(
    `SELECT id, territory_id, holder_id, holder_type, rent_per_game_day_units::TEXT, effective_to_game_day::TEXT
       FROM territory_rights
      WHERE status IN ('ACTIVE','HOLDOVER')
        AND effective_from_game_day <= $1
        AND MOD(ABS(hashtextextended(holder_id, 0)), $2) = $3
      ORDER BY id`, [day, shardCount, shard],
  );
  let paid = 0;
  let arrears = 0;
  let expired = 0;
  for (const right of rights.rows) {
    {
      const tx = repository;
      const locked = (await tx.query<{ status: string; effective_to_game_day: string | null }>('SELECT status, effective_to_game_day::TEXT FROM territory_rights WHERE id = $1 FOR UPDATE', [right.id])).rows[0];
      if (!locked || locked.status === 'RELEASED' || locked.status === 'EXPIRED') return;
      if (locked.effective_to_game_day && Number(locked.effective_to_game_day) < day) {
        await tx.query("UPDATE territory_rights SET status = 'EXPIRED' WHERE id = $1", [right.id]);
        await tx.query(`INSERT INTO territory_right_events (id,right_id,event_type,game_day,previous_status,next_status,correlation_id) VALUES ($1,$2,'EXPIRED',$3,$4,'EXPIRED',$5) ON CONFLICT (correlation_id) DO NOTHING`, [`RIGHT-EVENT-EXPIRED-${right.id}-${day}`, right.id, day, locked.status, `right-expired:${right.id}:${day}`]);
        expired += 1;
        return;
      }
      const existing = (await tx.query('SELECT 1 FROM territory_lease_payments WHERE right_id = $1 AND game_day = $2', [right.id, day])).rows[0];
      if (existing) return;
      const house = right.holder_type === 'HOUSE' ? (await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'HOUSE'", [right.holder_id])).rows[0] : null;
      const beneficiary = await beneficiaryAccount(tx, right.territory_id);
      const wallet = house ? (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`, [house.economic_id])).rows[0] : null;
      const rent = BigInt(right.rent_per_game_day_units);
      const paymentCorrelation = `lease-payment:${right.id}:${day}`;
      if (!house || !beneficiary || !wallet || BigInt(wallet.balance_units) < rent) {
        await tx.query(`INSERT INTO territory_lease_payments (id,right_id,territory_id,holder_type,holder_id,game_day,amount_units,beneficiary_economic_id,economic_transaction_id,status,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NULL,'ARREARS',$9)`, [`LEASE-PAYMENT-${right.id}-${day}`, right.id, right.territory_id, right.holder_type, right.holder_id, day, rent.toString(), beneficiary?.economic_id ?? 'ECON-CONSTRUCTION-SETTLEMENT', paymentCorrelation]);
        await tx.query("UPDATE territory_rights SET status = 'HOLDOVER' WHERE id = $1 AND status = 'ACTIVE'", [right.id]);
        arrears += 1;
        return;
      }
      await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','COMMONS_LEASE_RENT',$3,'territory-lease-v1',$4::JSONB)`, [paymentCorrelation, day, right.id, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-rent).toString() }, { account_id: beneficiary.account_id, asset_id: 1, delta_units: rent.toString() }])]);
      await tx.query(`INSERT INTO territory_lease_payments (id,right_id,territory_id,holder_type,holder_id,game_day,amount_units,beneficiary_economic_id,economic_transaction_id,status,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,(SELECT id FROM economic_transactions WHERE correlation_id=$9),'PAID',$9)`, [`LEASE-PAYMENT-${right.id}-${day}`, right.id, right.territory_id, right.holder_type, right.holder_id, day, rent.toString(), beneficiary.economic_id, paymentCorrelation, paymentCorrelation]);
      paid += 1;
    }
  }
  return { ok: true, day, paid, arrears, expired, shard, shardCount };
}
