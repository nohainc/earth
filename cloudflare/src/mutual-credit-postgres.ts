import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

const NETWORK_UNIT_RE = /^[A-Z][A-Z0-9_]{2,15}$/;

async function currentDay(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

async function houseForHuman(tx: PostgresRepository, humanId: string): Promise<string> {
  const row = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!row) throw new Error('Active Human not found');
  return row.house_id;
}

async function requireNetworkMember(tx: PostgresRepository, networkId: string, houseId: string, lock = false) {
  const row = (await tx.query<any>(`SELECT n.id, n.organization_id, n.status AS network_status, n.credit_enabled,
                                           m.house_id, m.credit_limit_units, m.position_units, m.status
                                      FROM mutual_credit_networks n
                                      JOIN mutual_credit_members m ON m.network_id = n.id AND m.house_id = $2
                                     WHERE n.id = $1 AND m.status = 'ACTIVE'${lock ? ' FOR UPDATE OF n, m' : ''}`, [networkId, houseId])).rows[0];
  if (!row) throw new Error('Active mutual-credit membership not found');
  return row;
}

export async function listMutualCreditNetworks(repository: PostgresRepository, houseId?: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT n.id, n.organization_id, o.name AS organization_name, n.name, n.unit_code,
                                                n.status, n.credit_enabled, n.max_member_limit_units::TEXT,
                                                n.reserve_target_units::TEXT, n.created_game_day,
                                                COUNT(m.house_id)::INTEGER AS member_count,
                                                ${houseId ? 'MAX(CASE WHEN m.house_id = $1 THEN m.credit_limit_units::TEXT END)' : 'NULL'} AS my_credit_limit_units,
                                                ${houseId ? 'MAX(CASE WHEN m.house_id = $1 THEN m.position_units::TEXT END)' : 'NULL'} AS my_position_units
                                           FROM mutual_credit_networks n
                                           JOIN organizations o ON o.id = n.organization_id
                                           LEFT JOIN mutual_credit_members m ON m.network_id = n.id AND m.status = 'ACTIVE'
                                          WHERE n.status IN ('ACTIVE','PAUSED')
                                          GROUP BY n.id, o.name
                                          ORDER BY n.name, n.id`, houseId ? [houseId] : []);
  return { networks: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function createMutualCreditNetwork(repository: PostgresRepository, input: { humanId: string; organizationId: string; name: string; unitCode: string; maxMemberLimitUnits: bigint; reserveTargetUnits?: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM mutual_credit_networks WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, networkId: prior.id, correlationId: input.correlationId };
    const houseId = await houseForHuman(tx, input.humanId);
    const org = (await tx.query<{ id: string }>(`SELECT o.id FROM organizations o JOIN organization_memberships m ON m.organization_id = o.id AND m.house_id = $2 AND m.status = 'ACTIVE' LEFT JOIN organization_capabilities c ON c.organization_id = o.id AND c.capability_code = 'BANKING' AND c.status = 'ACTIVE' WHERE o.id = $1 AND o.status = 'ACTIVE' AND (o.archetype = 'BANK' OR c.organization_id IS NOT NULL) AND m.role_code IN ('FOUNDER','ADMIN','GOVERNOR') LIMIT 1`, [input.organizationId, houseId])).rows[0];
    if (!org) throw new Error('Mutual-credit network authority denied');
    const name = input.name.trim(); const unitCode = input.unitCode.trim().toUpperCase();
    if (name.length < 3 || name.length > 80) throw new Error('Network name must be 3–80 characters');
    if (!NETWORK_UNIT_RE.test(unitCode)) throw new Error('Unit code must be 3–16 uppercase characters');
    if (input.maxMemberLimitUnits <= 0n || input.maxMemberLimitUnits > 10_000_000_000_000n) throw new Error('Member credit limit is outside network bounds');
    const day = await currentDay(tx); const id = `MCN-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO mutual_credit_networks (id, organization_id, name, unit_code, max_member_limit_units, reserve_target_units, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [id, input.organizationId, name, unitCode, input.maxMemberLimitUnits.toString(), (input.reserveTargetUnits ?? 0n).toString(), day, input.correlationId]);
    await tx.query(`INSERT INTO mutual_credit_members (network_id, house_id, credit_limit_units, joined_game_day) VALUES ($1,$2,$3,$4)`, [id, houseId, input.maxMemberLimitUnits.toString(), day]);
    return { ok: true, networkId: id, unitCode, correlationId: input.correlationId };
  });
}

export async function joinMutualCreditNetwork(repository: PostgresRepository, input: { humanId: string; networkId: string; creditLimitUnits?: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const houseId = await houseForHuman(tx, input.humanId); const network = (await tx.query<any>("SELECT * FROM mutual_credit_networks WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.networkId])).rows[0];
    if (!network) throw new Error('Active mutual-credit network not found');
    const existing = (await tx.query<any>('SELECT status FROM mutual_credit_members WHERE network_id = $1 AND house_id = $2', [input.networkId, houseId])).rows[0];
    if (existing?.status === 'ACTIVE') return { ok: true, alreadyMember: true, networkId: input.networkId };
    const limit = input.creditLimitUnits ?? BigInt(network.max_member_limit_units); if (limit <= 0n || limit > BigInt(network.max_member_limit_units)) throw new Error('Requested credit limit exceeds network policy');
    const day = await currentDay(tx);
    await tx.query(`INSERT INTO mutual_credit_members (network_id, house_id, credit_limit_units, joined_game_day, status) VALUES ($1,$2,$3,$4,'ACTIVE') ON CONFLICT (network_id, house_id) DO UPDATE SET credit_limit_units = EXCLUDED.credit_limit_units, status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP`, [input.networkId, houseId, limit.toString(), day]);
    return { ok: true, joined: true, networkId: input.networkId, creditLimitUnits: limit.toString(), correlationId: input.correlationId };
  });
}

export async function transferMutualCredit(repository: PostgresRepository, input: { humanId: string; networkId: string; toHouseId: string; amountUnits: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM mutual_credit_transfers WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, transferId: prior.id, correlationId: input.correlationId };
    if (input.amountUnits <= 0n) throw new Error('Transfer amount must be positive');
    const fromHouseId = await houseForHuman(tx, input.humanId); if (fromHouseId === input.toHouseId) throw new Error('A House cannot transfer to itself');
    const network = await requireNetworkMember(tx, input.networkId, fromHouseId, true);
    if (network.network_status !== 'ACTIVE' || !network.credit_enabled) throw new Error('Network is not accepting new credit');
    const recipient = await requireNetworkMember(tx, input.networkId, input.toHouseId, true);
    const senderPosition = BigInt(network.position_units); const limit = BigInt(network.credit_limit_units);
    if (senderPosition - input.amountUnits < -limit) throw new Error('Transfer exceeds member credit limit');
    const day = await currentDay(tx); const id = `MCT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query('UPDATE mutual_credit_members SET position_units = position_units - $1, updated_at = CURRENT_TIMESTAMP WHERE network_id = $2 AND house_id = $3', [input.amountUnits.toString(), input.networkId, fromHouseId]);
    await tx.query('UPDATE mutual_credit_members SET position_units = position_units + $1, updated_at = CURRENT_TIMESTAMP WHERE network_id = $2 AND house_id = $3', [input.amountUnits.toString(), input.networkId, recipient.house_id]);
    await tx.query(`INSERT INTO mutual_credit_transfers (id, network_id, from_house_id, to_house_id, amount_units, game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7)`, [id, input.networkId, fromHouseId, input.toHouseId, input.amountUnits.toString(), day, input.correlationId]);
    return { ok: true, transferId: id, networkId: input.networkId, unitCode: network.unit_code, amountUnits: input.amountUnits.toString(), fromPositionUnits: (senderPosition - input.amountUnits).toString(), correlationId: input.correlationId };
  });
}

export async function addMutualCreditGuarantee(repository: PostgresRepository, input: { humanId: string; networkId: string; memberHouseId: string; guaranteedUnits: bigint; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM mutual_credit_guarantees WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, guaranteeId: prior.id, correlationId: input.correlationId };
    if (input.guaranteedUnits <= 0n) throw new Error('Guarantee amount must be positive');
    const guarantorHouseId = await houseForHuman(tx, input.humanId);
    if (guarantorHouseId === input.memberHouseId) throw new Error('A House cannot guarantee itself');
    const guarantor = await requireNetworkMember(tx, input.networkId, guarantorHouseId, true);
    const member = await requireNetworkMember(tx, input.networkId, input.memberHouseId, true);
    if (guarantor.network_status !== 'ACTIVE' || !guarantor.credit_enabled) throw new Error('Network is not accepting new guarantees');
    if (input.guaranteedUnits > BigInt(guarantor.credit_limit_units)) throw new Error('Guarantee exceeds guarantor policy limit');
    const day = await currentDay(tx); const id = `MCG-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO mutual_credit_guarantees (id, network_id, guarantor_house_id, member_house_id, guaranteed_units, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7)`, [id, input.networkId, guarantorHouseId, member.house_id, input.guaranteedUnits.toString(), day, input.correlationId]);
    return { ok: true, guaranteeId: id, networkId: input.networkId, memberHouseId: input.memberHouseId, guaranteedUnits: input.guaranteedUnits.toString(), correlationId: input.correlationId };
  });
}

export async function getMutualCreditNetwork(repository: PostgresRepository, networkId: string): Promise<Record<string, unknown>> {
  const [network, members, transfers, guarantees, defaults] = await Promise.all([
    repository.query(`SELECT n.*, o.name AS organization_name FROM mutual_credit_networks n JOIN organizations o ON o.id = n.organization_id WHERE n.id = $1`, [networkId]),
    repository.query(`SELECT m.network_id, m.house_id, h.house_name, m.credit_limit_units::TEXT, m.position_units::TEXT, m.status, m.joined_game_day FROM mutual_credit_members m JOIN houses h ON h.id = m.house_id WHERE m.network_id = $1 ORDER BY m.position_units ASC, h.house_name`, [networkId]),
    repository.query(`SELECT id, from_house_id, to_house_id, amount_units::TEXT, game_day, status, correlation_id FROM mutual_credit_transfers WHERE network_id = $1 ORDER BY game_day DESC, id DESC LIMIT 100`, [networkId]),
    repository.query(`SELECT id, guarantor_house_id, member_house_id, guaranteed_units::TEXT, status, created_game_day, correlation_id FROM mutual_credit_guarantees WHERE network_id = $1 ORDER BY created_game_day DESC, id DESC LIMIT 100`, [networkId]),
    repository.query(`SELECT id, member_house_id, claim_units::TEXT, recovered_units::TEXT, game_day, resolution FROM mutual_credit_defaults WHERE network_id = $1 ORDER BY game_day DESC, id DESC LIMIT 100`, [networkId]),
  ]);
  if (!network.rows[0]) throw new Error('Mutual-credit network not found');
  const positions = members.rows.reduce((sum: bigint, row: any) => sum + BigInt(row.position_units), 0n);
  const debt = members.rows.reduce((sum: bigint, row: any) => sum + (BigInt(row.position_units) < 0n ? -BigInt(row.position_units) : 0n), 0n);
  const guaranteesUnits = guarantees.rows.reduce((sum: bigint, row: any) => sum + BigInt(row.guaranteed_units), 0n);
  return { network: network.rows[0], members: members.rows, transfers: transfers.rows, guarantees: guarantees.rows, defaults: defaults.rows, health: { positionsReconcile: positions === 0n, aggregateDebtUnits: debt.toString(), guaranteedExposureUnits: guaranteesUnits.toString(), memberCount: members.rows.length }, generatedFrom: 'postgres-canonical-facts' };
}
