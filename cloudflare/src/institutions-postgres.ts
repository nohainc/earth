import type { PostgresRepository } from './repository.ts';
import { moneyToCents } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';
import { createNotification } from './notifications-postgres.ts';
import { createAffiliationEvent } from './game-events-postgres.ts';

async function day(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

async function uniqueInstitutionName(repository: PostgresRepository, name: string): Promise<void> {
  const result = await repository.query('SELECT id FROM institutions WHERE lower(name) = lower($1) LIMIT 1', [name]);
  if (result.rows[0]) throw new Error('Institution name already exists');
}

async function activeHumanHouse(tx: PostgresRepository, humanId: string): Promise<{ id: string; house_id: string; display_name: string }> {
  const result = await tx.query<{ id: string; house_id: string; display_name: string }>(
    "SELECT id, house_id, display_name FROM humans WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE",
    [humanId],
  );
  if (!result.rows[0]) throw new Error('Human not found or inactive');
  return result.rows[0];
}

async function provisionCorporationTreasury(tx: PostgresRepository, corporationId: string): Promise<string> {
  const economicId = `ECON-${corporationId}`;
  await tx.query(
    "INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)",
    [corporationId, economicId],
  );
  await tx.query(
    `INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type)
     SELECT $1, id, 'TREASURY'
       FROM economic_assets
      WHERE asset_kind = 'CREDIT'
     ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING`,
    [economicId],
  );
  await tx.query(
    `INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type)
     SELECT $1, id, 'OPERATIONS'
       FROM economic_assets
      WHERE asset_kind = 'CREDIT'
     ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING`,
    [economicId],
  );
  return economicId;
}

export async function listCorporations(repository: PostgresRepository, search = ''): Promise<Record<string, unknown>> {
  const term = `%${search.trim().replace(/[%_]/g, '')}%`;
  const result = await repository.query(`
    SELECT c.id, i.name, i.status, c.status AS corporation_status,
           c.admission_policy,
           (SELECT COUNT(*)::integer FROM territories t WHERE t.corporation_id = c.id AND t.status = 'ACTIVE') AS territory_count,
           (SELECT COUNT(*)::integer FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_count,
           (SELECT t.id FROM territories t WHERE t.corporation_id = c.id AND t.is_primary = TRUE AND t.status = 'ACTIVE' LIMIT 1) AS primary_territory_id
      FROM corporations c
      JOIN institutions i ON i.id = c.id
     WHERE i.status = 'ACTIVE' AND ($1 = '%%' OR i.name ILIKE $1)
     ORDER BY i.name ASC
     LIMIT 100`, [term]);
  return { corporations: result.rows };
}

export async function listCorporationTerritories(repository: PostgresRepository, corporationId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(
    `SELECT t.id, t.corporation_id, t.name, t.territory_type, t.status, t.is_primary, t.created_game_day
       FROM territories t
      WHERE t.corporation_id = $1
      ORDER BY t.is_primary DESC, t.id`,
    [corporationId],
  );
  return { territories: result.rows };
}

export async function createCorporation(
  repository: PostgresRepository,
  input: { founderId: string; name: string; territoryName?: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const name = input.name.trim();
    const territoryName = (input.territoryName?.trim() || `${name} Territory`).trim();
    if (name.length < 3 || name.length > 80) throw new Error('Corporation name is required');
    if (territoryName.length < 2 || territoryName.length > 80) throw new Error('Territory name is required');

    const founder = await activeHumanHouse(tx, input.founderId);
    const existing = await tx.query("SELECT id FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE' FOR UPDATE", [founder.house_id]);
    if (existing.rows[0]) throw new Error('House already belongs to an active Corporation');
    await uniqueInstitutionName(tx, name);
    await uniqueInstitutionName(tx, territoryName);

    const suffix = crypto.randomUUID().slice(0, 8).toUpperCase();
    const corporationId = `CORP-${suffix}`;
    const territoryId = `TERR-${suffix}`;
    const gameDay = await day(tx);

    await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corporationId, name]);
    await tx.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v1', 'OPEN', 'ACTIVE', $2)", [corporationId, gameDay]);
    await tx.query(
      `INSERT INTO territories (id, corporation_id, name, territory_type, status, is_primary, created_game_day)
       VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', TRUE, $4)`,
      [territoryId, corporationId, territoryName, gameDay],
    );
    await provisionCorporationTreasury(tx, corporationId);
    await tx.query(
      `INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status)
       VALUES ($1, $2, 'CORPORATION_EXECUTIVE', 'ACTIVE'), ($1, $2, 'CORPORATION_TREASURER', 'ACTIVE')`,
      [corporationId, input.founderId],
    );
    await tx.query(
      `INSERT INTO governance_rules
        (id, institution_id, name, category, quorum_threshold, approval_threshold,
         voting_period_days, implementation_delay_days, version, status, created_by,
         effective_from_game_day)
       VALUES ($1, $2, $3, 'governance', 0.25, 0.50, 3, 1, 1, 'ACTIVE', $4, $5)`,
      [`GOV-${corporationId}-BASELINE-V1`, corporationId, `${name} Governance Baseline`, input.founderId, gameDay],
    );
    await tx.query(
      `INSERT INTO comm_channels (id, scope, scope_id, name, description)
       VALUES ($1, 'corporation', $2, $3, $4)`,
      [`channel-corporation-${corporationId}`, corporationId, name, `Private conversation for members of ${name}.`],
    );
    await tx.query(
      `INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status)
       VALUES ($1, $2, $3, $4, 'ACTIVE')`,
      [founder.house_id, corporationId, territoryId, gameDay],
    );
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [territoryId, gameDay]);
    await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.founderId, institutionType: 'CORPORATION', institutionId: corporationId, action: 'joined', gameDay, reason: 'corporation_genesis' });
    await createNotification(tx, {
      id: `CORP-GENESIS-${founder.house_id}-${corporationId}`, humanId: input.founderId,
      notificationType: 'institution', title: 'Corporation founded',
      body: `Your House founded ${name} and its primary Territory was provisioned.`,
      entityType: 'corporation', entityId: corporationId, gameDay,
      correlationId: `CORP-GENESIS:${founder.house_id}:${corporationId}`,
    });
    await tx.query(
      `INSERT INTO game_events
        (id, category, event_type, game_day, actor_human_id, subject_type, subject_id, title, details)
       VALUES ($1, 'INSTITUTION', 'CORPORATION_FORMED', $2, $3, 'CORPORATION', $4, $5, $6)`,
      [crypto.randomUUID(), gameDay, input.founderId, corporationId, `${name} was founded`, toNanoMarkup({ corporationId, territoryId, founderHouseId: founder.house_id })],
    );
    return {
      ok: true,
      corporation: (await tx.query('SELECT * FROM corporations WHERE id = $1', [corporationId])).rows[0],
      territory: (await tx.query('SELECT * FROM territories WHERE id = $1', [territoryId])).rows[0],
      affiliation: (await tx.query('SELECT * FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2', [founder.house_id, corporationId])).rows[0],
    };
  });
}

export async function corporationQualification(repository: PostgresRepository, corporationId: string): Promise<Record<string, unknown>> {
  const corporation = await repository.query<Record<string, unknown>>(
    'SELECT c.*, i.name, i.status AS institution_status FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1', [corporationId],
  );
  if (!corporation.rows[0]) throw new Error('Corporation not found');
  const [territories, governance, treasury] = await Promise.all([
    repository.query("SELECT id, name, status, is_primary FROM territories WHERE corporation_id = $1 AND status = 'ACTIVE' ORDER BY is_primary DESC, id", [corporationId]),
    repository.query("SELECT id FROM governance_rules WHERE institution_id = $1 AND status = 'ACTIVE' LIMIT 1", [corporationId]),
    repository.query<{ balance: string }>(`SELECT COALESCE(SUM(a.balance_units), 0)::TEXT AS balance
      FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      JOIN economic_assets e ON e.id = a.asset_id AND e.code = 'CREDIT'
      WHERE o.id = $1 AND o.owner_type = 'CORPORATION' AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE'`, [corporationId]),
  ]);
  const requirements = { primaryTerritory: territories.rows.some((item) => item.is_primary), governance: Boolean(governance.rows[0]), treasury: treasury.rows[0]?.balance !== undefined };
  return { ok: true, corporation: corporation.rows[0], territories: territories.rows, treasury: treasury.rows[0]?.balance ?? '0', requirements, qualified: Object.values(requirements).every(Boolean) };
}

async function currentAffiliation(tx: PostgresRepository, houseId: string): Promise<{ id: string; corporation_id: string; primary_territory_id: string | null } | null> {
  const result = await tx.query<{ id: string; corporation_id: string; primary_territory_id: string | null }>(
    "SELECT id, corporation_id, primary_territory_id FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE' FOR UPDATE", [houseId],
  );
  return result.rows[0] ?? null;
}

export async function changeCorporationMembership(
  repository: PostgresRepository,
  input: { humanId: string; corporationId: string; action: 'join' | 'leave' },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const human = await activeHumanHouse(tx, input.humanId);
    const corporation = await tx.query<{ id: string; name: string; admission_policy: string }>(
      "SELECT c.id, i.name, c.admission_policy FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1 AND c.status = 'ACTIVE' FOR UPDATE", [input.corporationId],
    );
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const current = await currentAffiliation(tx, human.house_id);
    const gameDay = await day(tx);
    const refreshTerritoryIds = new Set<string>();
    if (input.action === 'leave') {
      if (!current || current.corporation_id !== input.corporationId) throw new Error('House is not a member of this Corporation');
      if (current.primary_territory_id) refreshTerritoryIds.add(current.primary_territory_id);
      await tx.query("UPDATE house_affiliations SET status = 'LEFT', left_game_day = $1 WHERE id = $2", [gameDay, current.id]);
      await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.humanId, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'left', gameDay, reason: 'voluntary_departure' });
      await createNotification(tx, { id: `CORP-LEFT-${human.house_id}-${input.corporationId}-${gameDay}`, humanId: input.humanId, notificationType: 'institution', title: 'Corporation left', body: `Your House left ${corporation.rows[0].name}.`, entityType: 'corporation', entityId: input.corporationId, gameDay, correlationId: `CORP-LEFT:${human.house_id}:${input.corporationId}:${gameDay}` });
    } else {
      if (current?.corporation_id === input.corporationId) return { ok: true, alreadyMember: true, affiliation: current };
      if (corporation.rows[0].admission_policy.toUpperCase() !== 'OPEN') throw new Error('Corporation admission is not open');
      const territory = await tx.query<{ id: string }>("SELECT id FROM territories WHERE corporation_id = $1 AND is_primary = TRUE AND status = 'ACTIVE' FOR UPDATE", [input.corporationId]);
      if (!territory.rows[0]) throw new Error('Corporation primary Territory is unavailable');
      if (current) {
        if (current.primary_territory_id) refreshTerritoryIds.add(current.primary_territory_id);
        await tx.query("UPDATE house_affiliations SET status = 'LEFT', left_game_day = $1 WHERE id = $2", [gameDay, current.id]);
        await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.humanId, institutionType: 'CORPORATION', institutionId: current.corporation_id, action: 'left', gameDay, reason: 'corporation_transfer' });
      }
      await tx.query(
        `INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status)
         VALUES ($1, $2, $3, $4, 'ACTIVE')`, [human.house_id, input.corporationId, territory.rows[0].id, gameDay],
      );
      refreshTerritoryIds.add(territory.rows[0].id);
      await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.humanId, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'joined', gameDay, reason: 'voluntary_membership' });
      await createNotification(tx, { id: `CORP-JOINED-${human.house_id}-${input.corporationId}-${gameDay}`, humanId: input.humanId, notificationType: 'institution', title: 'Corporation joined', body: `Your House joined ${corporation.rows[0].name}.`, entityType: 'corporation', entityId: input.corporationId, gameDay, correlationId: `CORP-JOINED:${human.house_id}:${input.corporationId}:${gameDay}` });
    }
    for (const territoryId of refreshTerritoryIds) {
      await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [territoryId, gameDay]);
    }
    return { ok: true, affiliation: (await tx.query("SELECT * FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE'", [human.house_id])).rows[0] ?? null };
  });
}

export async function setCorporationAdmissionPolicy(repository: PostgresRepository, input: { humanId: string; corporationId: string; policy: 'open' | 'approval' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const human = await activeHumanHouse(tx, input.humanId);
    const membership = await tx.query("SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [human.house_id, input.corporationId]);
    if (!membership.rows[0]) throw new Error('Corporation membership is required');
    const policy = input.policy === 'open' ? 'OPEN' : 'APPROVAL';
    const result = await tx.query('UPDATE corporations SET admission_policy = $1 WHERE id = $2 RETURNING id, admission_policy', [policy, input.corporationId]);
    if (!result.rows[0]) throw new Error('Corporation not found');
    return { ok: true, corporation: result.rows[0] };
  });
}

export async function contributeToCorporation(repository: PostgresRepository, input: { humanId: string; corporationId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const human = await activeHumanHouse(tx, input.humanId);
    const membership = await tx.query("SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [human.house_id, input.corporationId]);
    if (!membership.rows[0]) throw new Error('Corporation membership is required');
    const amountUnits = moneyToCents(input.amount);
    if (amountUnits <= 0) throw new Error('Contribution amount must be positive');
    const accounts = await tx.query<{ house_account_id: string; corporation_account_id: string }>(
      `SELECT MAX(house_account.id::TEXT) FILTER (WHERE house_account.account_type = 'WALLET') AS house_account_id,
              MAX(corporation_account.id::TEXT) FILTER (WHERE corporation_account.account_type = 'TREASURY') AS corporation_account_id
         FROM owner_registry house_owner
         JOIN economic_accounts house_account ON house_account.owner_economic_id = house_owner.economic_id AND house_account.asset_id = 1 AND house_account.status = 'ACTIVE'
         JOIN owner_registry corporation_owner ON corporation_owner.id = $2 AND corporation_owner.owner_type = 'CORPORATION'
         JOIN economic_accounts corporation_account ON corporation_account.owner_economic_id = corporation_owner.economic_id AND corporation_account.asset_id = 1 AND corporation_account.status = 'ACTIVE'
        WHERE house_owner.id = $1 AND house_owner.owner_type = 'HOUSE'`,
      [human.house_id, input.corporationId],
    );
    const account = accounts.rows[0];
    if (!account?.house_account_id || !account.corporation_account_id) throw new Error('Contribution accounts are unavailable');
    const gameDay = await day(tx);
    const result = await tx.query<{ transaction_id: string }>(
      `SELECT transaction_id FROM earth_post_transaction($1, $2, 0, 'CORPORATION_CONTRIBUTION', 'CORPORATION', $3, 'corp-finance-v3', $4::jsonb)`,
      [input.correlationId, gameDay, input.corporationId, JSON.stringify([
        { account_id: account.house_account_id, delta_units: -amountUnits, asset_id: 1 },
        { account_id: account.corporation_account_id, delta_units: amountUnits, asset_id: 1 },
      ])],
    );
    return { ok: true, amount: input.amount, transactionId: result.rows[0]?.transaction_id ?? null, corporationId: input.corporationId, correlationId: input.correlationId };
  });
}

export async function setCorporationTaxCharter(repository: PostgresRepository, input: { humanId: string; corporationId: string; incomeTaxBps: number; salesTaxBps: number; corporateTaxBps: number; propertyTaxBps: number; correlationId: string }): Promise<Record<string, unknown>> {
  const charter = {
    incomeTaxBps: Math.max(0, Math.min(5000, Math.round(Number(input.incomeTaxBps ?? 0)))),
    salesTaxBps: Math.max(0, Math.min(2500, Math.round(Number(input.salesTaxBps ?? 0)))),
    corporateTaxBps: Math.max(0, Math.min(5000, Math.round(Number(input.corporateTaxBps ?? 0)))),
    propertyTaxBps: Math.max(0, Math.min(3000, Math.round(Number(input.propertyTaxBps ?? 0)))),
  };
  return { ok: true, corporationId: input.corporationId, charter, correlationId: input.correlationId };
}
