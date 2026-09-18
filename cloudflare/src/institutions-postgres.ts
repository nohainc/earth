import type { PostgresRepository } from './repository.ts';
import { moneyToCents } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';
import { createNotification } from './notifications-postgres.ts';
import { createAffiliationEvent } from './game-events-postgres.ts';
import { refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { postEconomicTransaction } from './economic-transaction-postgres.ts';

async function day(repository: PostgresRepository): Promise<number> {
  const clock = await readAuthoritativeGameTime(repository);
  return clock.gameDay;
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

async function provisionCorporationEconomy(tx: PostgresRepository, corporationId: string): Promise<string> {
  const economicId = `ECON-${corporationId}`;
  await tx.query(
    "INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)",
    [corporationId, economicId],
  );
  await tx.query('SELECT earth_provision_corporation_economy($1)', [economicId]);
  return economicId;
}

export async function listCorporations(repository: PostgresRepository, search = ''): Promise<Record<string, unknown>> {
  const term = `%${search.trim().replace(/[%_]/g, '')}%`;
  const result = await repository.query(`
    SELECT c.id, i.name, i.status, c.status AS corporation_status,
           c.charter_version, c.admission_policy,
           NULLIF(corp_rules.rules->>'CORPORATION.TAX.INCOME_RATE', '')::INTEGER AS income_tax_bps,
           NULLIF(corp_rules.rules->>'CORPORATION.TAX.SALES_RATE', '')::INTEGER AS sales_tax_bps,
           NULLIF(corp_rules.rules->>'CORPORATION.TAX.PROPERTY_RATE', '')::INTEGER AS property_tax_bps,
           NULLIF(corp_rules.rules->>'CORPORATION.TAX.CORPORATE_RATE', '')::INTEGER AS corporate_tax_bps,
           NULLIF(COALESCE(corp_rules.rules->>'CORPORATION.HOUSE_CAPACITY.BASE_RATE', earth_rules.rules->>'EARTH.CAPACITY.BASE_RATE'), '')::TEXT AS v5_house_capacity_base_rate,
           NULLIF(earth_rules.rules->>'EARTH.CAPACITY.BASE_RATE', '')::TEXT AS v5_earth_capacity_base_rate,
           (SELECT COUNT(*)::integer FROM territories t WHERE t.corporation_id = c.id AND t.status = 'ACTIVE') AS territory_count,
           (SELECT COUNT(*)::integer FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_count,
           (SELECT s.total_occupied_units FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_occupied_capacity,
           (SELECT s.required_territory_units FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_required_territory_units,
           (SELECT s.standard_territory_capacity_units FROM corporation_capacity_state_v5 s WHERE s.corporation_id = c.id ORDER BY s.game_day DESC LIMIT 1) AS v5_standard_territory_capacity,
           (SELECT SUM(o.assessed_units) FROM v5_capacity_obligations o WHERE o.corporation_id = c.id AND o.capacity_level = 'HOUSE' AND o.game_day = (SELECT MAX(game_day) FROM v5_capacity_obligations WHERE corporation_id = c.id AND capacity_level = 'HOUSE')) AS v5_house_capacity_revenue,
           (SELECT SUM(o.assessed_units) FROM v5_capacity_obligations o WHERE o.corporation_id = c.id AND o.capacity_level = 'CORPORATION' AND o.game_day = (SELECT MAX(game_day) FROM v5_capacity_obligations WHERE corporation_id = c.id AND capacity_level = 'CORPORATION')) AS v5_earth_capacity_expense,
           (SELECT status FROM v5_capacity_delinquency_state d WHERE d.subject_type = 'CORPORATION' AND d.subject_id = c.id) AS v5_capacity_status,
           (SELECT t.id FROM territories t WHERE t.corporation_id = c.id AND t.is_primary = TRUE AND t.status = 'ACTIVE' LIMIT 1) AS primary_territory_id,
           (SELECT t.name FROM territories t WHERE t.corporation_id = c.id AND t.is_primary = TRUE AND t.status = 'ACTIVE' LIMIT 1) AS primary_territory_name,
           (SELECT s.private_slot_capacity FROM territory_capacity_state s JOIN territories t ON t.id = s.territory_id WHERE t.corporation_id = c.id AND t.is_primary = TRUE ORDER BY s.game_day DESC LIMIT 1) AS private_slot_capacity,
           (SELECT s.private_slots_used FROM territory_capacity_state s JOIN territories t ON t.id = s.territory_id WHERE t.corporation_id = c.id AND t.is_primary = TRUE ORDER BY s.game_day DESC LIMIT 1) AS private_slots_used,
           (SELECT COUNT(*)::integer FROM organization_technology_adoptions a WHERE a.organization_id = c.id AND a.status = 'ADOPTED') AS technology_count,
           COALESCE((SELECT a.balance_units FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE'), 0)::TEXT AS treasury,
           COALESCE((SELECT a.balance_units FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 'OPERATIONS' AND a.status = 'ACTIVE'), 0)::TEXT AS operating_budget,
           COALESCE((SELECT a.balance_units FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 'RESERVE' AND a.status = 'ACTIVE'), 0)::TEXT AS reserve
      FROM corporations c
      JOIN institutions i ON i.id = c.id
      LEFT JOIN LATERAL (
        SELECT jsonb_object_agg(rule_code, value_json->'value') AS rules
          FROM (
            SELECT DISTINCT ON (v.rule_code) v.rule_code, v.value_json
              FROM constitutional_rule_versions_v5 v
             WHERE v.authority_type = 'EARTH' AND v.authority_id = 'EARTH'
               AND v.status IN ('ACTIVE', 'RETIRED')
               AND v.effective_from_game_day <= (SELECT game_day FROM earth_get_current_game_time())
               AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM earth_get_current_game_time()))
             ORDER BY v.rule_code, v.effective_from_game_day DESC, v.version DESC
          ) earth_versions
      ) earth_rules ON TRUE
      LEFT JOIN LATERAL (
        SELECT jsonb_object_agg(rule_code, value_json->'value') AS rules
          FROM (
            SELECT DISTINCT ON (v.rule_code) v.rule_code, v.value_json
              FROM constitutional_rule_versions_v5 v
             WHERE v.authority_type = 'CORPORATION' AND v.authority_id = c.id
               AND v.status IN ('ACTIVE', 'RETIRED')
               AND v.effective_from_game_day <= (SELECT game_day FROM earth_get_current_game_time())
               AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM earth_get_current_game_time()))
             ORDER BY v.rule_code, v.effective_from_game_day DESC, v.version DESC
          ) corporation_versions
      ) corp_rules ON TRUE
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
  // V5 founding provisions a Corporation Constitution and settlement
  // profiles atomically. The legacy service would create a competing
  // governance_rules baseline, so retain it only as a fail-closed symbol for
  // historical callers.
  throw new Error('Legacy Corporation founding is retired; use the V5 founding command.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
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
    await provisionCorporationEconomy(tx, corporationId);
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
    await refreshV5SettlementProfilesForHouse(tx, founder.house_id, gameDay, [corporationId]);
    await tx.query(
      `INSERT INTO house_residencies
         (id, house_id, territory_id, residency_class, effective_from_game_day, correlation_id)
       VALUES ($1, $2, $3, 'PRIMARY', $4, $5)
       ON CONFLICT DO NOTHING`,
      [`RES-${corporationId}-${founder.house_id}`, founder.house_id, territoryId, gameDay,
       `residency:corporation-genesis:${corporationId}:${founder.house_id}`],
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
    repository.query<{ balance_units: string }>(`SELECT COALESCE(SUM(a.balance_units), 0)::TEXT AS balance_units
      FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      JOIN economic_assets e ON e.id = a.asset_id AND e.code = 'CREDIT'
      WHERE o.id = $1 AND o.owner_type = 'CORPORATION' AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE'`, [corporationId]),
  ]);
  const requirements = { primaryTerritory: territories.rows.some((item) => item.is_primary), governance: Boolean(governance.rows[0]), treasury: treasury.rows[0]?.balance_units !== undefined };
  return { ok: true, corporation: corporation.rows[0], territories: territories.rows, treasury: treasury.rows[0]?.balance_units ?? '0', requirements, qualified: Object.values(requirements).every(Boolean) };
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
  // Legacy Corporation membership is not an active V5 command surface. V5
  // affiliation transitions must go through the admission-aware service so
  // capacity profiles and constitutional obligations are refreshed together.
  throw new Error('Legacy Corporation membership mutation is retired; use the V5 membership command.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
  return repository.transaction(async (tx) => {
    const human = await activeHumanHouse(tx, input.humanId);
    const corporation = await tx.query<{ id: string; name: string; admission_policy: string }>(
      "SELECT c.id, i.name, c.admission_policy FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1 AND c.status = 'ACTIVE' FOR UPDATE", [input.corporationId],
    );
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const current = await currentAffiliation(tx, human.house_id);
    const gameDay = await day(tx);
    const refreshTerritoryIds = new Set<string>();
    const affectedCorporationIds = new Set<string>();
    if (input.action === 'leave') {
      if (!current || current.corporation_id !== input.corporationId) throw new Error('House is not a member of this Corporation');
      affectedCorporationIds.add(current.corporation_id);
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
        affectedCorporationIds.add(current.corporation_id);
        if (current.primary_territory_id) refreshTerritoryIds.add(current.primary_territory_id);
        await tx.query("UPDATE house_affiliations SET status = 'LEFT', left_game_day = $1 WHERE id = $2", [gameDay, current.id]);
        await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.humanId, institutionType: 'CORPORATION', institutionId: current.corporation_id, action: 'left', gameDay, reason: 'corporation_transfer' });
      }
      await tx.query(
        `INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status)
         VALUES ($1, $2, $3, $4, 'ACTIVE')`, [human.house_id, input.corporationId, territory.rows[0].id, gameDay],
      );
      affectedCorporationIds.add(input.corporationId);
      refreshTerritoryIds.add(territory.rows[0].id);
      await createAffiliationEvent(tx, { id: crypto.randomUUID(), humanId: input.humanId, institutionType: 'CORPORATION', institutionId: input.corporationId, action: 'joined', gameDay, reason: 'voluntary_membership' });
      await createNotification(tx, { id: `CORP-JOINED-${human.house_id}-${input.corporationId}-${gameDay}`, humanId: input.humanId, notificationType: 'institution', title: 'Corporation joined', body: `Your House joined ${corporation.rows[0].name}.`, entityType: 'corporation', entityId: input.corporationId, gameDay, correlationId: `CORP-JOINED:${human.house_id}:${input.corporationId}:${gameDay}` });
    }
    for (const territoryId of refreshTerritoryIds) {
      await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [territoryId, gameDay]);
    }
    await refreshV5SettlementProfilesForHouse(tx, human.house_id, gameDay, [...affectedCorporationIds]);
    return { ok: true, affiliation: (await tx.query("SELECT * FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE'", [human.house_id])).rows[0] ?? null };
  });
}

export async function setCorporationAdmissionPolicy(repository: PostgresRepository, input: { humanId: string; corporationId: string; policy: 'open' | 'approval' }): Promise<Record<string, unknown>> {
  // Admission policy is a Corporation-local Constitution rule. Direct writes
  // would bypass proposal, electorate, activation, and rule provenance.
  throw new Error('Direct admission-policy mutation is retired; submit a V5 Constitution amendment proposal.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
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
  return runEconomicMutation(repository, async (tx, clock) => {
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
    const result = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'CORPORATION_CONTRIBUTION',
      sourceType: 'CORPORATION',
      sourceId: input.corporationId,
      rulesVersion: 'corp-finance-v3',
      entries: [
        { accountId: account.house_account_id, deltaUnits: (-amountUnits).toString(), assetId: 1 },
        { accountId: account.corporation_account_id, deltaUnits: amountUnits.toString(), assetId: 1 },
      ],
    }, clock);
    return { ok: true, amount: input.amount, transactionId: result.transactionId ?? null, corporationId: input.corporationId, correlationId: input.correlationId };
  });
}

export async function setCorporationTaxCharter(repository: PostgresRepository, input: { humanId: string; corporationId: string; incomeTaxBps: number; salesTaxBps: number; corporateTaxBps: number; propertyTaxBps: number; correlationId: string }): Promise<Record<string, unknown>> {
  // Retained as a compatibility symbol for historical tooling only. Tax
  // policy is now a typed Constitution rule and must enter through the V5
  // amendment lifecycle; never write the legacy charter from gameplay code.
  throw new Error('Direct Corporation tax mutation is retired; submit a V5 Constitution amendment proposal.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
  const charter = {
    incomeTaxBps: Math.max(0, Math.min(5000, Math.round(Number(input.incomeTaxBps ?? 0)))),
    salesTaxBps: Math.max(0, Math.min(2500, Math.round(Number(input.salesTaxBps ?? 0)))),
    corporateTaxBps: Math.max(0, Math.min(5000, Math.round(Number(input.corporateTaxBps ?? 0)))),
    propertyTaxBps: Math.max(0, Math.min(3000, Math.round(Number(input.propertyTaxBps ?? 0)))),
  };
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ tax_charter_version: number; tax_charter: Record<string, unknown>; tax_charter_correlation_id: string | null }>(
      'SELECT tax_charter_version, tax_charter, tax_charter_correlation_id FROM corporations WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE',
      [input.corporationId],
    )).rows[0];
    if (!prior) throw new Error('Corporation not found');
    if (prior.tax_charter_correlation_id === input.correlationId) return { ok: true, alreadyProcessed: true, corporationId: input.corporationId, charter, version: prior.tax_charter_version, correlationId: input.correlationId };
    const authority = await tx.query(
      `SELECT 1 FROM institution_governance_roles
        WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
          AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`,
      [input.corporationId, input.humanId],
    );
    if (!authority.rows[0]) throw new Error('Corporation tax authority is required');
    const current = JSON.stringify(prior.tax_charter ?? {});
    const next = JSON.stringify(charter);
    if (current === next) return { ok: true, alreadyProcessed: true, corporationId: input.corporationId, charter, version: prior.tax_charter_version, correlationId: input.correlationId };
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const version = Number(prior.tax_charter_version ?? 0) + 1;
    await tx.query(
      'UPDATE corporations SET tax_charter = $1::JSONB, tax_charter_version = $2, tax_charter_updated_game_day = $3, tax_charter_correlation_id = $4 WHERE id = $5',
      [next, version, day, input.correlationId, input.corporationId],
    );
    return { ok: true, corporationId: input.corporationId, charter, version, effectiveGameDay: day + 1, correlationId: input.correlationId };
  });
}
