import type { PostgresRepository } from './repository.ts';
import { createAffiliationEvent } from './game-events-postgres.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { getActiveV5StandardCapacity } from './v5-capacity-postgres.ts';
import { calculateProgressiveCharge } from './v5-progressive.ts';
import { rebuildV5CorporationSettlementProfile, refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { resolveEffectiveConstitution } from './constitutional-kernel-postgres.ts';

type HouseContext = { houseId: string; currentCorporationId: string | null; buildingUnits: bigint };

async function hashInvite(token: string): Promise<string> {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, '0')).join('');
}

async function houseContext(tx: PostgresRepository, humanId: string): Promise<HouseContext> {
  const row = (await tx.query<{ house_id: string; corporation_id: string | null; economic_id: string }>(`SELECT h.house_id, ha.corporation_id, o.economic_id
    FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
      LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
    WHERE h.id = $1 AND h.status = 'ACTIVE' FOR UPDATE`, [humanId])).rows[0];
  if (!row) throw new Error('Active House is required');
  const buildings = await tx.query<{ units: string }>(`SELECT COALESCE(SUM(bc.slot_footprint),0)::TEXT AS units
    FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id WHERE b.owner_economic_id = $1 AND b.status = 'ACTIVE'`, [row.economic_id]);
  return { houseId: row.house_id, currentCorporationId: row.corporation_id, buildingUnits: BigInt(buildings.rows[0]?.units ?? '0') };
}

async function corporation(tx: PostgresRepository, corporationId: string, gameDay: number) {
  const row = (await tx.query<{ id: string; name: string; admission_policy: string }>(`SELECT c.id, i.name, c.admission_policy
    FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1 AND c.status = 'ACTIVE' FOR UPDATE`, [corporationId])).rows[0];
  if (!row) throw new Error('Corporation not found or inactive');
  const constitution = await resolveEffectiveConstitution(tx, { corporationId, gameDay });
  const policy = String(
    constitution.rules['CORPORATION.ADMISSION_POLICY'] ?? row.admission_policy,
  ).toUpperCase();
  if (!['OPEN', 'APPROVAL', 'INVITE_ONLY'].includes(policy)) throw new Error('Corporation has an unsupported V5 admission policy');
  return { ...row, admissionPolicy: policy as 'OPEN' | 'APPROVAL' | 'INVITE_ONLY' };
}

async function v5Pricing(tx: PostgresRepository, corporationId: string, buildingUnits: bigint, day: number) {
  let global;
  try { global = await getActiveV5StandardCapacity(tx, day); } catch (error) {
    if (error instanceof Error && error.message.includes('No active V5 capacity policy')) return { available: false, reason: error.message };
    throw error;
  }
  const rule = (await tx.query<{ rate: string; schedule_id: string }>(`SELECT house_base_capacity_rate_units::TEXT AS rate, house_schedule_id
    FROM corporation_capacity_policy_versions WHERE corporation_id = $1 AND status = 'ACTIVE'
      AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [corporationId, day])).rows[0];
  if (!rule) return { available: false, reason: 'Corporation has no active V5 capacity policy' };
  const brackets = (await tx.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [rule.schedule_id])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const current = calculateProgressiveCharge({ quantity: 1n + buildingUnits, baseRate: BigInt(rule.rate), brackets });
  const after = calculateProgressiveCharge({ quantity: 2n + buildingUnits, baseRate: BigInt(rule.rate), brackets });
  return { available: true, gameDay: day, residentialDelta: 1, currentUsage: current.quantity.toString(), afterUsage: after.quantity.toString(), currentCharge: current.totalCharge.toString(), afterCharge: after.totalCharge.toString(), incrementalCharge: (after.totalCharge - current.totalCharge).toString(), scheduleId: rule.schedule_id, policyVersion: global.policyVersion };
}

export async function quoteV5CorporationMembership(repository: PostgresRepository, humanId: string, corporationId: string) {
  return repository.transaction(async (tx) => {
    const house = await houseContext(tx, humanId);
    const world = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const corp = await corporation(tx, corporationId, world);
    return { ok: true, corporationId, corporationName: corp.name, admissionPolicy: corp.admissionPolicy, currentCorporationId: house.currentCorporationId, eligible: house.currentCorporationId === null, capacity: await v5Pricing(tx, corporationId, house.buildingUnits, world) };
  });
}

export async function applyV5CorporationMembership(repository: PostgresRepository, input: { humanId: string; corporationId: string; correlationId: string; inviteToken?: string }) {
  return repository.transaction(async (tx) => {
    const house = await houseContext(tx, input.humanId);
    const world = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const corp = await corporation(tx, input.corporationId, world);
    if (house.currentCorporationId === input.corporationId) return { ok: true, alreadyMember: true, corporationId: input.corporationId };
    if (house.currentCorporationId) throw new Error('House already belongs to an active Corporation');
    if (corp.admissionPolicy === 'APPROVAL') {
      await tx.query(`INSERT INTO corporation_membership_applications_v5 (id, corporation_id, house_id, requested_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (correlation_id) DO NOTHING`, [`V5-APP-${crypto.randomUUID()}`, input.corporationId, house.houseId, world, input.correlationId]);
      return { ok: true, status: 'PENDING', corporationId: input.corporationId, capacity: await v5Pricing(tx, input.corporationId, house.buildingUnits, world) };
    }
    if (corp.admissionPolicy === 'INVITE_ONLY') {
      if (!input.inviteToken) throw new Error('A Corporation invite is required');
      const tokenHash = await hashInvite(input.inviteToken);
      const invite = (await tx.query<{ id: string; uses: number; max_uses: number }>(`SELECT id, uses, max_uses FROM corporation_invites_v5 WHERE corporation_id = $1 AND token_hash = $2 AND status = 'ACTIVE' AND issued_game_day <= $3 AND expires_game_day >= $3 AND (target_house_id IS NULL OR target_house_id = $4) FOR UPDATE`, [input.corporationId, tokenHash, world, house.houseId])).rows[0];
      if (!invite || invite.uses >= invite.max_uses) throw new Error('Invite is invalid, expired, or exhausted');
      await tx.query(`UPDATE corporation_invites_v5 SET uses = uses + 1, status = CASE WHEN uses + 1 >= max_uses THEN 'EXHAUSTED' ELSE status END WHERE id = $1`, [invite.id]);
    }
    await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1,$2,NULL,$3,'ACTIVE')`, [house.houseId, input.corporationId, world]);
    await refreshV5SettlementProfilesForHouse(tx, house.houseId, world, [input.corporationId]);
    await createAffiliationEvent(tx, { id: `V5-AFF-${input.correlationId}`, humanId: input.humanId, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'joined', gameDay: world, reason: 'v5_admission' });
    await enqueueOutbox(tx, { eventKey: `v5-membership:${input.correlationId}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: input.corporationId, payload: { type: 'HOUSE_CORPORATION_JOINED', houseId: house.houseId, corporationId: input.corporationId, gameDay: world } });
    return { ok: true, status: 'ACTIVE', corporationId: input.corporationId, residentialCapacityAdded: 1, capacity: await v5Pricing(tx, input.corporationId, house.buildingUnits, world), correlationId: input.correlationId };
  });
}

export async function leaveV5Corporation(repository: PostgresRepository, input: { humanId: string; corporationId: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const house = await houseContext(tx, input.humanId);
    const affiliation = (await tx.query<{ id: string; corporation_id: string }>(
      `SELECT id, corporation_id FROM house_affiliations
        WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE' FOR UPDATE`,
      [house.houseId, input.corporationId],
    )).rows[0];
    if (!affiliation) throw new Error('House is not an active member of this Corporation');
    const prior = (await tx.query<{ id: string }>(
      'SELECT id FROM game_events WHERE correlation_id = $1 LIMIT 1',
      [input.correlationId],
    )).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, corporationId: input.corporationId, correlationId: input.correlationId };
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    await tx.query(`UPDATE house_affiliations SET status = 'LEFT', left_game_day = $2 WHERE id = $1`, [affiliation.id, day]);
    await refreshV5SettlementProfilesForHouse(tx, house.houseId, day, [input.corporationId]);
    
    // Check if the leaving human held executive leadership roles
    const execRoles = await tx.query<{ id: number; role_code: string }>(
      `SELECT id, role_code FROM institution_governance_roles
        WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'`,
      [input.corporationId, input.humanId],
    );
    if (execRoles.rows.length > 0) {
      // Find another active member human to succeed leadership
      const successor = (await tx.query<{ id: string }>(
        `SELECT h.id FROM humans h
           JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.corporation_id = $1 AND ha.status = 'ACTIVE'
          WHERE h.status = 'ACTIVE' AND h.id <> $2
          ORDER BY ha.joined_game_day ASC, h.created_at ASC LIMIT 1`,
        [input.corporationId, input.humanId],
      )).rows[0];
      
      if (successor) {
        // Transfer roles to successor
        for (const role of execRoles.rows) {
          await tx.query(`UPDATE institution_governance_roles SET status = 'INACTIVE' WHERE id = $1`, [role.id]);
          await tx.query(
            `INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status)
             VALUES ($1, $2, $3, 'ACTIVE')`,
            [input.corporationId, successor.id, role.role_code],
          );
        }
      } else {
        // 0 members remaining - mark corporation as dissolved and release active name lock
        await tx.query(`UPDATE institution_governance_roles SET status = 'INACTIVE' WHERE institution_id = $1 AND human_id = $2`, [input.corporationId, input.humanId]);
        await tx.query(`UPDATE corporations SET status = 'DISSOLVED' WHERE id = $1`, [input.corporationId]);
        await tx.query(`UPDATE institutions SET status = 'DISSOLVED' WHERE id = $1`, [input.corporationId]);
      }
    }

    await createAffiliationEvent(tx, { id: `V5-LEAVE-${input.correlationId}`, humanId: input.humanId, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'left', gameDay: day, reason: 'v5_voluntary_departure', correlationId: input.correlationId });
    await enqueueOutbox(tx, { eventKey: `v5-membership-leave:${input.correlationId}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: input.corporationId, payload: { type: 'HOUSE_CORPORATION_LEFT', houseId: house.houseId, corporationId: input.corporationId, gameDay: day } });
    return { ok: true, status: 'LEFT', houseId: house.houseId, corporationId: input.corporationId, gameDay: day, correlationId: input.correlationId };
  });
}

export async function delegateV5CorporationLeadership(repository: PostgresRepository, input: { humanId: string; corporationId: string; targetHumanId: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code = 'CORPORATION_EXECUTIVE'`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation executive authorization is required');
    const targetMember = (await tx.query(
      `SELECT 1 FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.corporation_id = $1 AND ha.status = 'ACTIVE' WHERE h.id = $2 AND h.status = 'ACTIVE'`,
      [input.corporationId, input.targetHumanId],
    )).rows[0];
    if (!targetMember) throw new Error('Target human must be an active member of this Corporation');
    
    // Transfer executive and treasurer roles
    await tx.query(
      `UPDATE institution_governance_roles SET status = 'INACTIVE'
        WHERE institution_id = $1 AND human_id = $2 AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`,
      [input.corporationId, input.humanId],
    );
    await tx.query(
      `INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status)
       VALUES ($1, $2, 'CORPORATION_EXECUTIVE', 'ACTIVE'), ($1, $2, 'CORPORATION_TREASURER', 'ACTIVE')`,
      [input.corporationId, input.targetHumanId],
    );
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    await enqueueOutbox(tx, { eventKey: `v5-leadership-delegate:${input.correlationId}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: input.corporationId, payload: { type: 'CORPORATION_LEADERSHIP_DELEGATED', previousHumanId: input.humanId, newHumanId: input.targetHumanId, corporationId: input.corporationId, gameDay: day } });
    return { ok: true, corporationId: input.corporationId, previousHumanId: input.humanId, newHumanId: input.targetHumanId, gameDay: day };
  });
}

export async function scheduleV5CorporationDissolution(repository: PostgresRepository, input: { humanId: string; corporationId: string; reason?: string; transitionDays?: number; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code = 'CORPORATION_EXECUTIVE'`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation executive authorization is required');
    const existing = (await tx.query<{ id: string; effective_game_day: string; status: string }>(
      `SELECT id, effective_game_day::TEXT, status FROM v5_corporation_dissolution_schedules WHERE corporation_id = $1 AND status = 'PENDING'`,
      [input.corporationId],
    )).rows[0];
    if (existing) return { ok: true, alreadyScheduled: true, scheduleId: existing.id, effectiveGameDay: Number(existing.effective_game_day), status: existing.status };
    
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const transitionDays = input.transitionDays ?? 3;
    const effectiveDay = day + transitionDays;
    const id = `V5-DISSOLVE-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    
    await tx.query(
      `INSERT INTO v5_corporation_dissolution_schedules
        (id, corporation_id, initiated_by_human_id, initiated_game_day, effective_game_day, reason, status, correlation_id)
       VALUES ($1, $2, $3, $4, $5, $6, 'PENDING', $7)`,
      [id, input.corporationId, input.humanId, day, effectiveDay, input.reason ?? 'Voluntary Corporation Dissolution', input.correlationId],
    );
    await enqueueOutbox(tx, { eventKey: `v5-dissolution-schedule:${input.correlationId}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: input.corporationId, payload: { type: 'CORPORATION_DISSOLUTION_SCHEDULED', corporationId: input.corporationId, initiatedByHumanId: input.humanId, effectiveGameDay: effectiveDay, gameDay: day } });
    return { ok: true, scheduleId: id, corporationId: input.corporationId, initiatedGameDay: day, effectiveGameDay: effectiveDay, transitionDays, status: 'PENDING' };
  });
}

export async function executePendingV5CorporationDissolutionsInTransaction(tx: PostgresRepository, day: number): Promise<{ executed: number }> {
  const pending = (await tx.query<{ id: string; corporation_id: string }>(
    `SELECT id, corporation_id FROM v5_corporation_dissolution_schedules
      WHERE status = 'PENDING' AND effective_game_day <= $1 FOR UPDATE`,
    [day],
  )).rows;
  
  for (const schedule of pending) {
    // Release all active member houses
    const members = (await tx.query<{ id: string; house_id: string }>(
      `SELECT id, house_id FROM house_affiliations WHERE corporation_id = $1 AND status = 'ACTIVE' FOR UPDATE`,
      [schedule.corporation_id],
    )).rows;
    for (const member of members) {
      await tx.query(`UPDATE house_affiliations SET status = 'LEFT', left_game_day = $2 WHERE id = $1`, [member.id, day]);
      await refreshV5SettlementProfilesForHouse(tx, member.house_id, day, [schedule.corporation_id]);
    }
    await rebuildV5CorporationSettlementProfile(tx, schedule.corporation_id, day);
    // Deactivate governance roles
    await tx.query(`UPDATE institution_governance_roles SET status = 'INACTIVE' WHERE institution_id = $1`, [schedule.corporation_id]);
    // Set corporation and institution to DISSOLVED
    await tx.query(`UPDATE corporations SET status = 'DISSOLVED' WHERE id = $1`, [schedule.corporation_id]);
    await tx.query(`UPDATE institutions SET status = 'DISSOLVED' WHERE id = $1`, [schedule.corporation_id]);
    // Mark schedule as EXECUTED
    await tx.query(`UPDATE v5_corporation_dissolution_schedules SET status = 'EXECUTED', updated_at = CURRENT_TIMESTAMP WHERE id = $1`, [schedule.id]);
    await enqueueOutbox(tx, { eventKey: `v5-dissolution-executed:${schedule.id}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: schedule.corporation_id, payload: { type: 'CORPORATION_DISSOLVED', corporationId: schedule.corporation_id, gameDay: day } });
  }
  return { executed: pending.length };
}

export async function decideV5MembershipApplication(repository: PostgresRepository, input: { humanId: string; corporationId: string; applicationId: string; decision: 'APPROVED' | 'REJECTED'; reason?: string }) {
  return repository.transaction(async (tx) => {
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code IN ('CORPORATION_EXECUTIVE','CORPORATION_TREASURER')`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation authorization is required');
    const application = (await tx.query<{ id: string; house_id: string; status: string }>(`SELECT id, house_id, status FROM corporation_membership_applications_v5 WHERE id = $1 AND corporation_id = $2 FOR UPDATE`, [input.applicationId, input.corporationId])).rows[0];
    if (!application || application.status !== 'PENDING') throw new Error('Pending Corporation membership application not found');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    if (input.decision === 'APPROVED') {
      const current = (await tx.query('SELECT 1 FROM house_affiliations WHERE house_id = $1 AND status = \'ACTIVE\' FOR UPDATE', [application.house_id])).rows[0];
      if (current) throw new Error('House already belongs to an active Corporation');
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1,$2,NULL,$3,'ACTIVE')`, [application.house_id, input.corporationId, day]);
      await refreshV5SettlementProfilesForHouse(tx, application.house_id, day, [input.corporationId]);
      const applicant = (await tx.query<{ id: string }>("SELECT id FROM humans WHERE house_id = $1 AND status = 'ACTIVE' ORDER BY id LIMIT 1", [application.house_id])).rows[0];
      if (applicant) {
        await createAffiliationEvent(tx, { id: `V5-APP-AFF-${input.applicationId}`, humanId: applicant.id, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'joined', gameDay: day, reason: 'v5_admission_approved' });
      }
    }
    await tx.query(`UPDATE corporation_membership_applications_v5 SET status = $2, decided_game_day = $3, decided_by_human_id = $4, decision_reason = $5 WHERE id = $1`, [input.applicationId, input.decision, day, input.humanId, input.reason ?? null]);
    await enqueueOutbox(tx, { eventKey: `v5-application:${input.applicationId}:${input.decision}`, topic: 'institutions', aggregateType: 'CORPORATION', aggregateId: input.corporationId, payload: { type: `HOUSE_MEMBERSHIP_${input.decision}`, applicationId: input.applicationId, houseId: application.house_id, corporationId: input.corporationId, gameDay: day } });
    return { ok: true, applicationId: input.applicationId, status: input.decision, houseId: application.house_id, corporationId: input.corporationId, gameDay: day };
  });
}

export async function listV5MembershipApplications(repository: PostgresRepository, input: { humanId: string; corporationId: string; status?: 'PENDING' | 'APPROVED' | 'REJECTED' | 'WITHDRAWN' }) {
  return repository.transaction(async (tx) => {
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code IN ('CORPORATION_EXECUTIVE','CORPORATION_TREASURER')`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation authorization is required');
    const status = input.status ?? 'PENDING';
    const applications = await tx.query(`SELECT a.id, a.corporation_id, a.house_id, h.display_name AS applicant_name,
        a.status, a.requested_game_day, a.decided_game_day, a.decided_by_human_id, a.decision_reason, a.correlation_id
      FROM corporation_membership_applications_v5 a
      LEFT JOIN humans h ON h.house_id = a.house_id AND h.status = 'ACTIVE'
      WHERE a.corporation_id = $1 AND a.status = $2
      ORDER BY a.requested_game_day, a.id`, [input.corporationId, status]);
    return { ok: true, corporationId: input.corporationId, status, applications: applications.rows };
  });
}

export async function issueV5CorporationInvite(repository: PostgresRepository, input: { humanId: string; corporationId: string; targetHouseId?: string; expiresGameDay: number; maxUses: number }) {
  return repository.transaction(async (tx) => {
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code IN ('CORPORATION_EXECUTIVE','CORPORATION_TREASURER')`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation authorization is required');
    if (!Number.isInteger(input.expiresGameDay) || input.expiresGameDay < 1 || !Number.isInteger(input.maxUses) || input.maxUses < 1 || input.maxUses > 100) throw new Error('Invite expiry or use limit is invalid');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    if (input.expiresGameDay < day) throw new Error('Invite expiry must be in the future');
    if (input.targetHouseId && !(await tx.query('SELECT 1 FROM houses WHERE id = $1 AND status = \'ACTIVE\'', [input.targetHouseId])).rows[0]) throw new Error('Target House not found');
    const token = `${crypto.randomUUID()}-${crypto.randomUUID()}`;
    const id = `V5-INV-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO corporation_invites_v5 (id, corporation_id, target_house_id, token_hash, issued_by_human_id, issued_game_day, expires_game_day, max_uses) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [id, input.corporationId, input.targetHouseId ?? null, await hashInvite(token), input.humanId, day, input.expiresGameDay, input.maxUses]);
    return { ok: true, inviteId: id, token, corporationId: input.corporationId, targetHouseId: input.targetHouseId ?? null, expiresGameDay: input.expiresGameDay, maxUses: input.maxUses };
  });
}
