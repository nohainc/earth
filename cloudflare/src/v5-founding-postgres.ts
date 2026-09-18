import type { PostgresRepository } from './repository.ts';
import { createAffiliationEvent } from './game-events-postgres.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { getActiveV5StandardCapacity } from './v5-capacity-postgres.ts';
import { refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

type FoundingPolicy = { id: string; version: number; fee: bigint; reserve: bigint; rulesVersion: string };

async function foundingPolicy(tx: PostgresRepository, day: number): Promise<FoundingPolicy> {
  const row = (await tx.query<{ id: string; version: number; founding_fee_units: string; initial_treasury_reserve_units: string; rules_version: string }>(`SELECT id, version, founding_fee_units::TEXT, initial_treasury_reserve_units::TEXT, rules_version
    FROM v5_corporation_founding_policy_versions WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
      AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day])).rows[0];
  if (!row) throw new Error('No active V5 Corporation founding policy is available');
  return { id: row.id, version: Number(row.version), fee: BigInt(row.founding_fee_units), reserve: BigInt(row.initial_treasury_reserve_units), rulesVersion: row.rules_version };
}

async function founder(tx: PostgresRepository, humanId: string) {
  const row = (await tx.query<{ house_id: string; economic_id: string }>(`SELECT h.house_id, o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE' WHERE h.id = $1 AND h.status = 'ACTIVE' FOR UPDATE`, [humanId])).rows[0];
  if (!row) throw new Error('Active founding House is required');
  const affiliation = (await tx.query('SELECT 1 FROM house_affiliations WHERE house_id = $1 AND status = \'ACTIVE\'', [row.house_id])).rows[0];
  if (affiliation) throw new Error('House already belongs to an active Corporation');
  return { ...row };
}

export async function quoteV5CorporationFounding(repository: PostgresRepository, humanId: string, name: string) {
  return repository.transaction(async (tx) => {
    const normalized = name.trim();
    if (normalized.length < 3 || normalized.length > 80) throw new Error('Corporation name must be between 3 and 80 characters');
    const founderContext = await founder(tx, humanId);
    const world = (await readAuthoritativeGameTime(tx)).gameDay;
    const policy = await foundingPolicy(tx, world);
    const existing = (await tx.query('SELECT 1 FROM institutions WHERE lower(name) = lower($1) AND status = \'ACTIVE\'', [normalized])).rows[0];
    const earthCapacityPolicy = await getActiveV5StandardCapacity(tx, world);
    return { ok: true, eligible: !existing, blockers: existing ? ['Corporation name is already in use'] : [], name: normalized, foundingPolicyVersion: policy.version, foundingFeeUnits: policy.fee.toString(), initialTreasuryReserveUnits: policy.reserve.toString(), initialHouseBaseCapacityRateUnits: earthCapacityPolicy.earthBaseRate.toString(), firstResidentialCapacityUnits: '1', earthCapacityPolicy: { ...earthCapacityPolicy, standardTerritoryCapacity: earthCapacityPolicy.standardTerritoryCapacity.toString(), earthBaseRate: earthCapacityPolicy.earthBaseRate.toString() }, founderHouseId: founderContext.house_id, effectiveGameDay: world };
  });
}

export async function foundV5Corporation(repository: PostgresRepository, input: { humanId: string; name: string; admissionPolicy: 'OPEN' | 'APPROVAL' | 'INVITE_ONLY'; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ corporation_id: string }>('SELECT corporation_id FROM v5_corporation_founding_commands WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, corporationId: prior.corporation_id, correlationId: input.correlationId };
    const normalized = input.name.trim();
    if (normalized.length < 3 || normalized.length > 80) throw new Error('Corporation name must be between 3 and 80 characters');
    const house = await founder(tx, input.humanId);
    const duplicate = (await tx.query('SELECT 1 FROM institutions WHERE lower(name) = lower($1) AND status = \'ACTIVE\'', [normalized])).rows[0];
    if (duplicate) throw new Error('Corporation name already exists');
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const policy = await foundingPolicy(tx, day);
    const earthCapacityPolicy = await getActiveV5StandardCapacity(tx, day);
    const id = `CORP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const economicId = `ECON-${id}`;
    await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1,'CORPORATION',$2,'ACTIVE')`, [id, normalized]);
    await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1,'corporation-charter-v5',$2,'ACTIVE',$3)`, [id, input.admissionPolicy, day]);
    await tx.query(`INSERT INTO constitutional_rule_versions_v5
      (id, rule_code, authority_type, authority_id, version, value_json,
       effective_from_game_day, status)
      VALUES ($1, 'CORPORATION.ADMISSION_POLICY', 'CORPORATION', $2, 1,
              $3::JSONB, $4, 'ACTIVE')`,
      [`V5-CONST-CORP-ADMISSION-${id}-1`, id, JSON.stringify({ value: input.admissionPolicy }), day]);
    await tx.query(`INSERT INTO constitutional_rule_versions_v5
      (id, rule_code, authority_type, authority_id, version, value_json,
       effective_from_game_day, status)
      VALUES ($1, 'CORPORATION.HOUSE_CAPACITY.BASE_RATE', 'CORPORATION', $2, 1,
              $3::JSONB, $4, 'ACTIVE')`,
      [`V5-CONST-CORP-HOUSE-RATE-${id}-1`, id, JSON.stringify({ value: earthCapacityPolicy.earthBaseRate.toString() }), day]);
    await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1,'CORPORATION',$2)`, [id, economicId]);
    await tx.query('SELECT earth_provision_corporation_economy($1)', [economicId]);
    await tx.query(
      `INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status)
       VALUES ($1, $2, 'CORPORATION_EXECUTIVE', 'ACTIVE'), ($1, $2, 'CORPORATION_TREASURER', 'ACTIVE')`,
      [id, input.humanId],
    );
    await tx.query(
      `INSERT INTO comm_channels (id, scope, scope_id, name, description)
       VALUES ($1, 'corporation', $2, $3, $4)`,
      [`channel-corporation-${id}`, id, normalized, `Private conversation for members of ${normalized}.`],
    );
    await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1,$2,NULL,$3,'ACTIVE')`, [house.house_id, id, day]);
    await refreshV5SettlementProfilesForHouse(tx, house.house_id, day, [id]);
    const requiredFounderFunds = policy.fee + policy.reserve;
    if (requiredFounderFunds > 0n) {
      const wallet = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`, [house.economic_id])).rows[0];
      const earth = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a WHERE a.owner_economic_id = 'ECON-EARTH-001' AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
      const treasury = (await tx.query<{ id: string }>(`SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE' LIMIT 1`, [economicId])).rows[0];
      if (!wallet || (policy.fee > 0n && !earth) || !treasury || BigInt(wallet.balance_units) < requiredFounderFunds) throw new Error('Insufficient CREDIT for Corporation founding fee and reserve');
      const entries = [
        { account_id: wallet.id, asset_id: 1, delta_units: (-requiredFounderFunds).toString() },
      ];
      if (policy.fee > 0n) {
        entries.push({ account_id: earth!.id, asset_id: 1, delta_units: policy.fee.toString() });
      }
      if (policy.reserve > 0n) {
        entries.push({ account_id: treasury.id, asset_id: 1, delta_units: policy.reserve.toString() });
      }
      await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','CORPORATION_FOUNDING_FEE',$3,$4,$5::JSONB)`, [input.correlationId, day, id, earthCapacityPolicy.policyVersion, JSON.stringify(entries)]);
    }
    await tx.query(`INSERT INTO v5_corporation_founding_commands (correlation_id, corporation_id, created_game_day) VALUES ($1,$2,$3)`, [input.correlationId, id, day]);
    await createAffiliationEvent(tx, { id: `V5-FOUND-AFF-${input.correlationId}`, humanId: input.humanId, institutionType: 'CORPORATION', institutionId: id, action: 'joined', gameDay: day, reason: 'v5_foundation' });
    await enqueueOutbox(tx, { eventKey: `v5-founding:${input.correlationId}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: id, payload: { type: 'CORPORATION_FOUNDED', corporationId: id, founderHouseId: house.house_id, gameDay: day } });
    return { ok: true, corporationId: id, admissionPolicy: input.admissionPolicy, founderHouseId: house.house_id, residentialCapacityUnits: '1', correlationId: input.correlationId };
  });
}
