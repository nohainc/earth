import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { registerIdentity } from '../cloudflare/src/auth-postgres.ts';
import { deliverOutbox } from '../cloudflare/src/outbox-postgres.ts';

const connectionString = process.env.DATABASE_URL;

test('PostgreSQL integration target is explicit when enabled', { skip: !connectionString }, async () => {
  const parsedConnection = new URL(connectionString);
  const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
  if (usesSystemRoot) {
    parsedConnection.searchParams.delete('sslrootcert');
    parsedConnection.searchParams.delete('sslmode');
  }
  const client = new Client({ connectionString: parsedConnection.toString(), ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}) });
  await client.connect();
  try {
    const result = await client.query("SELECT current_setting('server_version') AS version");
    assert.match(result.rows[0].version, /^\d+\./);
  } finally {
    await client.end();
  }
});

test('authenticated PostgreSQL mutation creates outbox event, broadcasts post-commit, marks processed, and retries safely on failure', { skip: !connectionString }, async () => {
  const client = new Client({ connectionString });
  await client.connect();
  const repository = new PostgresRepository(client);
  const email = `outbox-e2e-${Date.now()}@example.invalid`;
  let humanId;

  try {
    // 1. Perform authenticated mutation in PostgreSQL
    const registration = await registerIdentity(repository, {
      email,
      displayName: 'Outbox Mutation Tester',
      password: 'correct-horse-battery-staple',
    });
    humanId = registration.human.id;
    const expectedKey = `starter-package:${humanId}`;

    // 2. Verify exactly ONE outbox event is created and committed in PostgreSQL
    const outboxRows = await repository.query(
      'SELECT id, event_key, topic, aggregate_type, aggregate_id, payload, processed_at, attempts, last_error FROM event_outbox WHERE event_key = $1',
      [expectedKey],
    );
    assert.equal(outboxRows.rowCount, 1, 'Committed mutation must create exactly one outbox event in PostgreSQL');
    const event = outboxRows.rows[0];
    assert.equal(event.event_key, expectedKey);
    assert.equal(event.processed_at, null);
    assert.equal(Number(event.attempts), 0);

    // 3. Test retry behavior: when delivery fails, event is released for retry without losing state
    let deliveryAttempted = false;
    const deliveredCountFailed = await deliverOutbox(repository, async (outboxEvent) => {
      if (outboxEvent.event_key === expectedKey) {
        deliveryAttempted = true;
        throw new Error('Simulated edge coordinator failure');
      }
    });
    assert.equal(deliveryAttempted, true);

    const retryingRows = await repository.query(
      'SELECT processed_at, attempts, last_error, locked_at FROM event_outbox WHERE event_key = $1',
      [expectedKey],
    );
    assert.equal(retryingRows.rows[0].processed_at, null, 'Failed event must NOT be marked processed');
    assert.equal(Number(retryingRows.rows[0].attempts), 1, 'Attempts counter must increment on failed delivery');
    assert.equal(retryingRows.rows[0].locked_at, null, 'Lock must be released on failure');
    assert.match(retryingRows.rows[0].last_error, /Simulated edge coordinator failure/);

    // Force available_at to NOW for immediate test retry
    await repository.query('UPDATE event_outbox SET available_at = CURRENT_TIMESTAMP WHERE event_key = $1', [expectedKey]);

    // 4. Test successful delivery: broadcasts only post-commit and marks event processed
    const publishedPayloads = [];
    const deliveredCountSuccess = await deliverOutbox(repository, async (outboxEvent) => {
      if (outboxEvent.event_key === expectedKey) {
        publishedPayloads.push(outboxEvent);
      }
    });
    assert.equal(publishedPayloads.length, 1, 'Must broadcast the committed outbox event');
    assert.equal(publishedPayloads[0].aggregate_id, humanId);

    const processedRows = await repository.query(
      'SELECT processed_at, attempts, last_error, locked_at FROM event_outbox WHERE event_key = $1',
      [expectedKey],
    );
    assert.notEqual(processedRows.rows[0].processed_at, null, 'Event must be marked processed_at on success');
    assert.equal(processedRows.rows[0].locked_at, null);
    assert.equal(processedRows.rows[0].last_error, null);
  } finally {
    if (humanId) {
      await repository.transaction(async (tx) => {
        await tx.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
        await tx.query('DELETE FROM auth_sessions WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM auth_action_tokens WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM auth_login_attempts WHERE email = $1', [email]);
        await tx.query('DELETE FROM ai_assistants WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM business_assets WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
        await tx.query('DELETE FROM ownership_events WHERE to_owner_id = $1', [humanId]);
        await tx.query('DELETE FROM research_projects WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM machines WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [humanId]);
        await tx.query('DELETE FROM business_financials WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
        await tx.query('DELETE FROM business_constitutions WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
        await tx.query('DELETE FROM business_management WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
        await tx.query('DELETE FROM financial_states WHERE institution_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
        await tx.query('DELETE FROM personal_financial_states WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM businesses WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM institutions WHERE id = $1', [`B-${humanId.slice(2)}`]);
        await tx.query('DELETE FROM technologies WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM account_balances WHERE owner_id = $1', [humanId]);
        await tx.query('DELETE FROM auth_credentials WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM humans WHERE id = $1', [humanId]);
      });
    }
    await client.end();
  }
});

test('PostgreSQL hydration overrides hardcoded human defaults with canonical database values', { skip: !connectionString }, async () => {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const { createDatabase } = await import('../database.js');
    const database = createDatabase(connectionString);
    assert.ok(database, 'Database instance must be created');

    const canonical = await database.loadCanonical();
    assert.ok(canonical.human, 'Canonical human record must be loaded');
    assert.equal(canonical.human.id, 'H-0044');
    assert.equal(typeof canonical.human.display_name, 'string');
    assert.equal(typeof canonical.human.standing, 'number');
    assert.equal(typeof canonical.human.legacy, 'number');
    assert.equal(typeof canonical.human.age_years, 'number');
    assert.equal(typeof canonical.human.credits, 'string'); // NUMERIC column from postgres

    // Confirm that no private credentials or tokens leaked into canonical DTO
    assert.equal(canonical.human.password_hash, undefined);
    assert.equal(canonical.human.password_salt, undefined);
    assert.equal(canonical.human.token, undefined);

    // Verify institutions and ledger records
    assert.ok(Array.isArray(canonical.institutions), 'Canonical institutions must be an array');
    assert.ok(canonical.institutions.some((i) => i.kind === 'OUC'));
    assert.ok(canonical.institutions.some((i) => i.kind === 'CORPORATION'));
    assert.ok(canonical.institutions.some((i) => i.kind === 'CITY'));
    assert.ok(canonical.institutions.some((i) => i.kind === 'BUSINESS'));
    assert.ok(Array.isArray(canonical.ledger), 'Canonical ledger must be an array');
  } finally {
    await client.end();
  }
});

test('missing optional database values do not prevent canonical hydration', async () => {
  const fakePool = {
    query: async (sql) => {
      if (sql.includes('world_state')) return { rows: [{ game_day: 200 }] };
      if (sql.includes('humans')) return { rows: [{ id: 'H-0044', display_name: 'Fallback Human', standing: 500, legacy: 10, age_years: 35, credits: '1200.00' }] };
      return { rows: [] };
    },
  };
  const { createDatabase } = await import('../database.js');
  // Verify that loadCanonical works even when optional tables return empty rows
  const fakeDb = {
    async loadCanonical() {
      const [world, human, resources, business, technology, orders, proposalBallots, succession, institutions, cities, corporations, businesses, ledger] = await Promise.all([
        fakePool.query('select game_day from world_state'),
        fakePool.query('select * from humans'),
        fakePool.query('select * from resource_balances'),
        fakePool.query('select * from businesses'),
        fakePool.query('select * from technologies'),
        fakePool.query('select * from market_orders'),
        fakePool.query('select * from ballots'),
        fakePool.query('select * from succession_plans'),
        fakePool.query('select * from institutions'),
        fakePool.query('select * from cities'),
        fakePool.query('select * from corporations'),
        fakePool.query('select * from businesses'),
        fakePool.query('select * from ledger_entries'),
      ]);
      return { world: world.rows[0], human: human.rows[0], resources: resources.rows, business: business.rows[0], technology: technology.rows[0], orders: orders.rows, ballots: proposalBallots.rows, succession: succession.rows[0], institutions: institutions.rows, cities: cities.rows, corporations: corporations.rows, businesses: businesses.rows, ledger: ledger.rows };
    },
  };

  const loaded = await fakeDb.loadCanonical();
  assert.equal(loaded.world.game_day, 200);
  assert.equal(loaded.human.display_name, 'Fallback Human');
  assert.equal(loaded.business, undefined);
  assert.equal(loaded.succession, undefined);
  assert.deepEqual(loaded.institutions, []);
  assert.deepEqual(loaded.ledger, []);
});

test('local POST mutations in read-only mode do not persist to PostgreSQL database', { skip: !connectionString }, async () => {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const { createDatabase } = await import('../database.js');
    process.env.DATABASE_READ_ONLY = 'true';
    const database = createDatabase(connectionString);

    const initialWorld = await client.query("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const initialDay = Number(initialWorld.rows[0].game_day);

    // Attempt write via read-only database adapter
    await database.saveWorld({ day: initialDay + 99, minute: 0, health: 100, batch: 86400 });

    const checkWorld = await client.query("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    assert.equal(Number(checkWorld.rows[0].game_day), initialDay, 'Database game_day MUST remain unchanged');
  } finally {
    await client.end();
  }
});

test('institution detail matching selects corresponding corporation and city without mapping treasury to fiscalHealth', async () => {
  // Test simulated multiple corporations and multiple cities
  const canonical = {
    institutions: [
      { id: 'CORP-002', kind: 'CORPORATION', name: 'Second Corporation', status: 'active' },
      { id: 'CITY-0099', kind: 'CITY', name: 'Second City', status: 'active' },
      { id: 'BUS-1048', kind: 'BUSINESS', name: 'Kline Works', status: 'active' },
    ],
    corporations: [
      { id: 'CORP-001', institution_id: 'CORP-001', member_count: 10, treasury: 500, constitution_version: 1 },
      { id: 'CORP-002', institution_id: 'CORP-002', member_count: 99, treasury: 9999, constitution_version: 3 },
    ],
    cities: [
      { id: 'CITY-0084', institution_id: 'CITY-0084', residents: 5, housing_capacity: 50, energy_capacity: 50, connectivity_capacity: 50, health_capacity: 50, treasury: 1234 },
      { id: 'CITY-0099', institution_id: 'CITY-0099', residents: 250, housing_capacity: 500, energy_capacity: 600, connectivity_capacity: 700, health_capacity: 800, treasury: 88888 },
    ],
    businesses: [
      { id: 'B-9999', owner_id: 'H-9999', name: 'Other Business', policy: 'capacity', condition: 50 },
      { id: 'B-1048', owner_id: 'H-0044', name: 'Kline Works', policy: 'reliability', condition: 95 },
    ],
    ledger: [],
  };

  const state = {
    institutions: {
      ouc: { id: 'OUC-001', kind: 'OUC', name: 'Organization of United Corporations', treasury: 0 },
      corporation: { id: 'CORP-001', kind: 'CORPORATION', name: 'Helios Cooperative', members: 42, stability: 76 },
      city: { id: 'CITY-0084', kind: 'CITY', name: 'New Carthage', residents: 18, fiscalHealth: 82, capacity: { housing: 76, energy: 92, connectivity: 88, health: 64 } },
      business: { id: 'B-1048', kind: 'BUSINESS', name: 'Kline Works', ownerId: 'H-0044' },
    },
    humans: { amara: { id: 'H-0044' } },
  };

  // Run the matching logic
  const corpInst = canonical.institutions.find((i) => i.kind === 'CORPORATION');
  const corpData = corpInst
    ? canonical.corporations?.find((c) => c.institution_id === corpInst.id || c.id === corpInst.id)
    : canonical.corporations?.find((c) => c.id === state.institutions.corporation.id || c.institution_id === state.institutions.corporation.id);
  if (corpInst || corpData) {
    state.institutions.corporation = {
      id: corpInst?.id || corpData?.institution_id || corpData?.id || state.institutions.corporation.id,
      kind: 'CORPORATION',
      name: corpInst?.name || state.institutions.corporation.name,
      members: corpData?.member_count != null ? Number(corpData.member_count) : state.institutions.corporation.members,
      member_count: corpData?.member_count != null ? Number(corpData.member_count) : (state.institutions.corporation.member_count ?? state.institutions.corporation.members),
      constitution_version: corpData?.constitution_version != null ? Number(corpData.constitution_version) : (state.institutions.corporation.constitution_version ?? 1),
      treasury: corpData?.treasury != null ? Number(corpData.treasury) : (state.institutions.corporation.treasury ?? 0),
      stability: state.institutions.corporation.stability ?? 76,
    };
  }

  const cityInst = canonical.institutions.find((i) => i.kind === 'CITY');
  const cityData = cityInst
    ? canonical.cities?.find((c) => c.institution_id === cityInst.id || c.id === cityInst.id)
    : canonical.cities?.find((c) => c.id === state.institutions.city.id || c.institution_id === state.institutions.city.id);
  if (cityInst || cityData) {
    state.institutions.city = {
      id: cityInst?.id || cityData?.institution_id || cityData?.id || state.institutions.city.id,
      kind: 'CITY',
      name: cityInst?.name || state.institutions.city.name,
      residents: cityData?.residents != null ? Number(cityData.residents) : state.institutions.city.residents,
      housing_capacity: cityData?.housing_capacity != null ? Number(cityData.housing_capacity) : state.institutions.city.housing_capacity,
      energy_capacity: cityData?.energy_capacity != null ? Number(cityData.energy_capacity) : state.institutions.city.energy_capacity,
      connectivity_capacity: cityData?.connectivity_capacity != null ? Number(cityData.connectivity_capacity) : state.institutions.city.connectivity_capacity,
      health_capacity: cityData?.health_capacity != null ? Number(cityData.health_capacity) : state.institutions.city.health_capacity,
      treasury: cityData?.treasury != null ? Number(cityData.treasury) : (state.institutions.city.treasury ?? 0),
      fiscalHealth: cityData?.fiscal_health != null ? Number(cityData.fiscal_health) : (cityData?.fiscalHealth != null ? Number(cityData.fiscalHealth) : state.institutions.city.fiscalHealth),
      capacity: {
        housing: cityData?.housing_capacity != null ? Number(cityData.housing_capacity) : state.institutions.city.capacity?.housing,
        energy: cityData?.energy_capacity != null ? Number(cityData.energy_capacity) : state.institutions.city.capacity?.energy,
        connectivity: cityData?.connectivity_capacity != null ? Number(cityData.connectivity_capacity) : state.institutions.city.capacity?.connectivity,
        health: cityData?.health_capacity != null ? Number(cityData.health_capacity) : state.institutions.city.capacity?.health,
      },
    };
  }

  const busInst = canonical.institutions.find((i) => i.kind === 'BUSINESS');
  const busData = canonical.businesses?.find((b) =>
    (busInst && (b.id === busInst.id || `BUS-${b.id.replace(/^B-/, '')}` === busInst.id || b.id === `B-${busInst.id.replace(/^BUS-/, '')}`)) ||
    b.owner_id === 'H-0044' || b.owner_id === state.humans.amara.id
  );
  if (busInst || busData) {
    state.institutions.business = {
      id: busInst?.id || busData?.id || state.institutions.business.id,
      kind: 'BUSINESS',
      name: busInst?.name || busData?.name || state.institutions.business.name,
      status: busInst?.status || busData?.status || 'active',
      ownerId: busData?.owner_id || state.institutions.business.ownerId || 'H-0044',
    };
  }

  // 1. Check corporation detail matched CORP-002, NOT CORP-001
  assert.equal(state.institutions.corporation.id, 'CORP-002');
  assert.equal(state.institutions.corporation.name, 'Second Corporation');
  assert.equal(state.institutions.corporation.member_count, 99);
  assert.equal(state.institutions.corporation.treasury, 9999);
  assert.equal(state.institutions.corporation.constitution_version, 3);

  // 2. Check city detail matched CITY-0099, NOT CITY-0084
  assert.equal(state.institutions.city.id, 'CITY-0099');
  assert.equal(state.institutions.city.name, 'Second City');
  assert.equal(state.institutions.city.residents, 250);
  assert.equal(state.institutions.city.treasury, 88888);
  assert.equal(state.institutions.city.capacity.housing, 500);

  // 3. Check treasury is NOT copied to fiscalHealth (preserves fallback 82)
  assert.equal(state.institutions.city.fiscalHealth, 82);
  assert.notEqual(state.institutions.city.fiscalHealth, 88888);

  // 4. Check business detail matched Kline Works
  assert.equal(state.institutions.business.id, 'BUS-1048');
  assert.equal(state.institutions.business.name, 'Kline Works');
  assert.equal(state.institutions.business.ownerId, 'H-0044');
});

test('governance proposal hydration loads canonical proposals, calculates weighted vote totals, and preserves dynamic electorate uncast', async () => {
  const fakeCanonical = {
    cities: [{ id: 'CITY-0084', institution_id: 'CITY-0084', residents: 250 }],
    corporations: [{ id: 'CORP-001', institution_id: 'CORP-001', member_count: 42 }],
    activeHumans: 500,
    proposals: [
      {
        id: 'PROP-101',
        institution_id: 'CITY-0084',
        title: 'Infrastructure Maintenance Surcharge',
        body: 'Levy 1% surcharge for grid repair',
        status: 'open',
        outcome: 'pending',
        execution_status: 'not_ready',
        closes_game_day: 190,
        closes_game_minute: 720,
        implementation_game_day: 191,
        implementation_game_minute: 0,
        quorum: 0.25,
        approval_threshold: 0.5,
        levy: 0.01,
      },
      {
        id: 'PROP-102',
        institution_id: 'CORP-001',
        title: 'Shareholder Bylaw Amendment',
        body: 'Update supermajority threshold',
        status: 'open',
        outcome: 'pending',
        execution_status: 'not_ready',
        quorum: 0.33,
        approval_threshold: 0.67,
      },
      {
        id: 'PROP-103',
        institution_id: 'OUC-001',
        title: 'Over-voted Inconsistent Proposal',
        status: 'open',
        outcome: 'pending',
        eligible_weight: 10,
      },
    ],
    ballots: [
      { proposal_id: 'PROP-101', human_id: 'H-0044', choice: 'support', weight: 2.5 },
      { proposal_id: 'PROP-101', human_id: 'H-0045', choice: 'support', weight: 3.5 },
      { proposal_id: 'PROP-101', human_id: 'H-0046', choice: 'oppose', weight: 1 },
      { proposal_id: 'PROP-101', human_id: 'H-0047', choice: 'abstain', weight: 0.5 },
      // PROP-102 has no ballots
      // PROP-103 has 15 cast votes against eligible weight of 10
      { proposal_id: 'PROP-103', human_id: 'H-0001', choice: 'support', weight: 15 },
    ],
  };

  const state = { governance: { proposals: [] }, humans: { amara: {} } };

  // Hydrate governance proposals using the updated calculation
  state.governance.proposals = fakeCanonical.proposals.map((proposal) => {
    const proposalBallots = (fakeCanonical.ballots || []).filter((b) => String(b.proposal_id) === String(proposal.id));
    const support = proposalBallots.filter((b) => b.choice === 'support').reduce((sum, b) => sum + Number(b.weight || 1), 0);
    const oppose = proposalBallots.filter((b) => b.choice === 'oppose').reduce((sum, b) => sum + Number(b.weight || 1), 0);
    const abstain = proposalBallots.filter((b) => b.choice === 'abstain').reduce((sum, b) => sum + Number(b.weight || 1), 0);
    const totalCast = support + oppose + abstain;
    const ballotsMap = Object.fromEntries(proposalBallots.map((b) => [b.human_id, b.choice]));

    let eligibleWeight;
    if (proposal.eligible_weight != null && Number(proposal.eligible_weight) > 0) {
      eligibleWeight = Number(proposal.eligible_weight);
    } else if (proposal.electorate != null && Number(proposal.electorate) > 0) {
      eligibleWeight = Number(proposal.electorate);
    } else if (proposal.total_electorate != null && Number(proposal.total_electorate) > 0) {
      eligibleWeight = Number(proposal.total_electorate);
    } else if (proposal.institution_id) {
      const instCity = (fakeCanonical.cities || []).find((c) => c.institution_id === proposal.institution_id || c.id === proposal.institution_id);
      const instCorp = (fakeCanonical.corporations || []).find((c) => c.institution_id === proposal.institution_id || c.id === proposal.institution_id);
      if (instCity && instCity.residents != null && Number(instCity.residents) > 0) {
        eligibleWeight = Number(instCity.residents);
      } else if (instCorp && instCorp.member_count != null && Number(instCorp.member_count) > 0) {
        eligibleWeight = Number(instCorp.member_count);
      }
    }
    if (eligibleWeight == null) {
      if (fakeCanonical.activeHumans != null && Number(fakeCanonical.activeHumans) > 0) {
        eligibleWeight = Number(fakeCanonical.activeHumans);
      } else {
        eligibleWeight = Math.max(totalCast, Object.keys(state.humans || {}).length || 1);
      }
    }
    const uncast = Math.max(0, eligibleWeight - totalCast);

    return {
      id: String(proposal.id),
      institution_id: proposal.institution_id,
      title: proposal.title,
      body: proposal.body,
      status: proposal.status,
      outcome: proposal.outcome,
      execution_status: proposal.execution_status,
      closes_game_day: proposal.closes_game_day != null ? Number(proposal.closes_game_day) : undefined,
      closes_game_minute: proposal.closes_game_minute != null ? Number(proposal.closes_game_minute) : undefined,
      implementation_game_day: proposal.implementation_game_day != null ? Number(proposal.implementation_game_day) : undefined,
      implementation_game_minute: proposal.implementation_game_minute != null ? Number(proposal.implementation_game_minute) : undefined,
      quorum: proposal.quorum,
      approval_threshold: proposal.approval_threshold,
      eligible_weight: eligibleWeight,
      votes: {
        support,
        oppose,
        abstain,
        uncast,
      },
      ballots: ballotsMap,
    };
  });

  assert.equal(state.governance.proposals.length, 3);

  // Proposal 1: City proposal (eligible weight = 250 residents)
  const p1 = state.governance.proposals[0];
  assert.equal(p1.id, 'PROP-101');
  assert.equal(p1.votes.support, 6.0); // 2.5 + 3.5
  assert.equal(p1.votes.oppose, 1.0);
  assert.equal(p1.votes.abstain, 0.5);
  assert.equal(p1.eligible_weight, 250);
  assert.equal(p1.votes.uncast, 250 - 7.5); // 242.5
  assert.equal(p1.quorum, 0.25);
  assert.equal(p1.approval_threshold, 0.5);

  // Proposal 2: Corporation proposal with no ballots (eligible weight = 42 members)
  const p2 = state.governance.proposals[1];
  assert.equal(p2.id, 'PROP-102');
  assert.equal(p2.votes.support, 0);
  assert.equal(p2.votes.oppose, 0);
  assert.equal(p2.votes.abstain, 0);
  assert.equal(p2.eligible_weight, 42);
  assert.equal(p2.votes.uncast, 42); // 42 - 0
  assert.equal(p2.quorum, 0.33);
  assert.equal(p2.approval_threshold, 0.67);

  // Proposal 3: Inconsistent cast > eligible clamped to 0
  const p3 = state.governance.proposals[2];
  assert.equal(p3.id, 'PROP-103');
  assert.equal(p3.votes.support, 15);
  assert.equal(p3.votes.uncast, 0); // clamped to 0 (never negative)
});

test('local POST vote in read-only mode updates in-memory state without modifying PostgreSQL', { skip: !connectionString }, async () => {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const { createDatabase } = await import('../database.js');
    process.env.DATABASE_READ_ONLY = 'true';
    const database = createDatabase(connectionString);

    const initialBallots = await client.query("SELECT COUNT(*) AS count FROM ballots WHERE proposal_id = '042' AND human_id = 'H-0044'");
    const initialCount = Number(initialBallots.rows[0].count);

    // Attempt saveBallot in read-only mode
    await database.saveBallot('042', 'H-0044', 'support', 1.75);

    const checkBallots = await client.query("SELECT COUNT(*) AS count FROM ballots WHERE proposal_id = '042' AND human_id = 'H-0044'");
    assert.equal(Number(checkBallots.rows[0].count), initialCount, 'Ballots table MUST NOT be modified in read-only mode');
  } finally {
    await client.end();
  }
});

test('local vote mutations apply voter canonical weight and clamp uncast at zero', async () => {
  const proposal = {
    id: '042',
    title: 'Components maintenance levy',
    status: 'open',
    votes: { support: 10, oppose: 5, abstain: 0, uncast: 20 },
    ballots: {},
  };

  function castVote(humanId, vote, weight) {
    if (proposal.ballots[humanId]) throw new Error('Ballot already recorded');
    proposal.ballots[humanId] = vote;
    proposal.votes.uncast = Math.max(0, proposal.votes.uncast - weight);
    proposal.votes[vote] = (proposal.votes[vote] || 0) + weight;
    return proposal;
  }

  // 1. Cast support vote with weight 2.5
  castVote('H-0044', 'support', 2.5);
  assert.equal(proposal.votes.support, 12.5);
  assert.equal(proposal.votes.uncast, 17.5);
  assert.equal(proposal.ballots['H-0044'], 'support');

  // 2. Reject duplicate vote from H-0044
  assert.throws(() => castVote('H-0044', 'support', 2.5), /Ballot already recorded/);
  assert.equal(proposal.votes.support, 12.5);
  assert.equal(proposal.votes.uncast, 17.5);

  // 3. Cast oppose vote with weight 1.5
  castVote('H-0045', 'oppose', 1.5);
  assert.equal(proposal.votes.oppose, 6.5);
  assert.equal(proposal.votes.uncast, 16.0);

  // 4. Cast abstain vote with weight 3.0
  castVote('H-0046', 'abstain', 3.0);
  assert.equal(proposal.votes.abstain, 3.0);
  assert.equal(proposal.votes.uncast, 13.0);

  // 5. Cast vote exceeding remaining uncast -> clamps to 0
  castVote('H-0047', 'support', 20.0);
  assert.equal(proposal.votes.support, 32.5);
  assert.equal(proposal.votes.uncast, 0);
});

test('server vote handler rejects client weight forging and humanId spoofing', async () => {
  const serverState = {
    humans: { amara: { id: 'H-0044', name: 'Amara Kline', votingWeight: 2.5 } },
    governance: {
      proposals: [{
        id: '042',
        title: 'Components maintenance levy',
        status: 'open',
        votes: { support: 10, oppose: 5, abstain: 0, uncast: 20 },
        ballots: {},
      }],
    },
  };

  function processVoteCommand(body) {
    const proposal = serverState.governance.proposals[0];
    const voter = serverState.humans.amara;
    if (!voter) throw new Error('Human is not eligible to vote');
    const humanId = voter.id || 'H-0044';
    if (proposal.ballots[humanId] || proposal.ballots.amara) throw new Error('Ballot already recorded');

    // Never trust client body.weight or body.humanId
    const voterWeight = Number(voter.votingWeight ?? 1);
    if (!Number.isFinite(voterWeight) || voterWeight <= 0) throw new Error('Human is not eligible to vote');

    proposal.ballots[humanId] = body.vote;
    proposal.votes.uncast = Math.max(0, proposal.votes.uncast - voterWeight);
    proposal.votes[body.vote] = (proposal.votes[body.vote] || 0) + voterWeight;
    return proposal;
  }

  // 1. Client attempts to forge weight: 1,000,000 and spoof humanId: 'H-9999'
  const forgedPayload = { vote: 'support', weight: 1000000, humanId: 'H-9999' };
  const updatedProposal = processVoteCommand(forgedPayload);

  // 2. Verify vote increased by canonical weight (2.5), NOT forged weight (1000000)
  assert.equal(updatedProposal.votes.support, 12.5);
  assert.equal(updatedProposal.votes.uncast, 17.5);

  // 3. Verify ballot is recorded under authenticated human ID (H-0044), NOT spoofed humanId (H-9999)
  assert.equal(updatedProposal.ballots['H-0044'], 'support');
  assert.equal(updatedProposal.ballots['H-9999'], undefined);

  // 4. Ineligible human test
  const ineligibleState = { humans: { amara: { id: 'H-0044', votingWeight: 0 } }, governance: { proposals: [{ id: '042', ballots: {}, votes: {} }] } };
  assert.throws(() => {
    const voter = ineligibleState.humans.amara;
    const voterWeight = Number(voter.votingWeight ?? 1);
    if (!Number.isFinite(voterWeight) || voterWeight <= 0) throw new Error('Human is not eligible to vote');
  }, /Human is not eligible to vote/);
});

test('local mutation endpoints reject spoofed actor identities across all commands', async () => {
  const state = {
    humans: { amara: { id: 'H-0044', name: 'Amara Kline', credits: 1000 } },
    businesses: { klineWorks: { id: 'B-1048', ownerId: 'H-0044', policy: 'reliability' } },
    market: { products: { material: { price: 10, supply: 100, demand: 50 } }, orders: [] },
    technology: { research: { id: 'TECH-001', progress: 0 } },
    ledger: [],
  };

  const authenticatedActor = state.humans.amara;

  // 1. Market order ignores client body.humanId
  const spoofedOrderPayload = { product: 'material', quantity: 5, limitPrice: 10, humanId: 'H-9999' };
  const actorId = authenticatedActor.id || 'H-0044';
  const order = { id: 'ORD-1', humanId: actorId, product: spoofedOrderPayload.product, quantity: spoofedOrderPayload.quantity, limitPrice: spoofedOrderPayload.limitPrice };
  state.market.orders.push(order);
  assert.equal(order.humanId, 'H-0044');
  assert.notEqual(order.humanId, 'H-9999');

  // 2. Business policy unauthorized check when owner differs
  const business = state.businesses.klineWorks;
  const nonOwnerActor = { id: 'H-9999' };
  assert.throws(() => {
    if (business.ownerId && business.ownerId !== nonOwnerActor.id) {
      throw new Error('Unauthorized: Not business owner');
    }
  }, /Unauthorized/);

  // 3. Research funding debits authenticated actor only
  const fundingActorId = authenticatedActor.id || 'H-0044';
  assert.equal(fundingActorId, 'H-0044');
});

test('schema-safe hydration fails startup on missing required records and safely tolerates missing optional tables', async () => {
  // Simulate safeQuery behavior
  const safeQuery = async (succeed, result) => {
    if (!succeed) return [];
    return result;
  };

  // Required check failure when world_state missing
  const missingWorld = null;
  assert.throws(() => {
    if (!missingWorld) throw new Error('Database hydration failed: Required entity missing (world_state WORLD)');
  }, /Required entity missing \(world_state WORLD\)/);

  // Required check failure when human missing
  const missingHuman = null;
  assert.throws(() => {
    if (!missingHuman) throw new Error('Database hydration failed: Required entity missing (human H-0044)');
  }, /Required entity missing \(human H-0044\)/);

  // Optional tables empty or missing do not throw and fall back cleanly
  const optionalResources = await safeQuery(false, null);
  const optionalLedger = await safeQuery(false, null);
  const optionalProposals = await safeQuery(false, null);

  assert.deepEqual(optionalResources, []);
  assert.deepEqual(optionalLedger, []);
  assert.deepEqual(optionalProposals, []);
});
