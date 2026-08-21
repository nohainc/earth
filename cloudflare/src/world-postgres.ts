import type { PostgresRepository } from './repository.ts';
import { projectGameDeadline } from './game-clock.ts';
import { rankOpportunities } from './opportunities.ts';
import { marketFeeRate } from './market-rules.ts';
import { generateDecisionQueue } from './decision-queue.ts';
import { evaluatePlayerObjectives } from './objectives.ts';
import { economicStartIndex } from './starter-package.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';
import { reconcileWorldSimulation } from './engines/simulation-orchestrator.ts';
import { computeResourceFlows } from './engines/resource-flow-engine.ts';
import { TECHNOLOGY_CATALOG_DETAILS } from './technology-postgres.ts';

type Row = Record<string, any>;

function mapByKind(rows: Row[], kind: string): Row {
  return rows.find((row) => row.kind === kind) ?? {};
}

function ratio(value: unknown, divisor: unknown, cap = 1): number {
  return Math.min(cap, Number(value ?? 0) / Math.max(1, Number(divisor ?? 0)));
}

export async function worldSnapshot(repository: PostgresRepository, viewerId: string): Promise<Record<string, unknown>> {
  await reconcileWorldSimulation(repository, viewerId);
  const flows = await computeResourceFlows(repository, viewerId);

  const [world, human, institutions, resources, business, technology, proposals, machines, account, ballots, succession, membership, prices, ledger, cityMetrics, corporationMetrics, personalFinance, contracts, social, technologyAdoptions] = await Promise.all([
    repository.query('SELECT * FROM world_state WHERE id = $1', ['WORLD']),
    repository.query('SELECT * FROM humans WHERE id = $1', [viewerId]),
    repository.query('SELECT * FROM institutions'),
    repository.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1', [viewerId]),
    repository.query("SELECT businesses.*, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id AND holder_id = $1), 0) AS owned_shares, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id), 0) AS total_issued_shares, (SELECT holder_id FROM business_shares WHERE business_id = businesses.id ORDER BY shares DESC, holder_id LIMIT 1) AS controlling_human_id, COALESCE(business_constitutions.version, 1) AS constitution_version, COALESCE(business_constitutions.shareholder_vote_threshold, 0.5) AS shareholder_vote_threshold, COALESCE(business_constitutions.board_approval_threshold, 0.5) AS board_approval_threshold, COALESCE(business_constitutions.dilution_notice_days, 3) AS dilution_notice_days, COALESCE(business_management.manager_id, businesses.owner_id) AS manager_id, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit FROM businesses LEFT JOIN business_constitutions ON business_constitutions.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id LEFT JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.owner_id = $1 OR business_management.manager_id = $1 OR EXISTS (SELECT 1 FROM business_shares viewer_shares WHERE viewer_shares.business_id = businesses.id AND viewer_shares.holder_id = $1) ORDER BY businesses.id", [viewerId]),
    repository.query('SELECT * FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewerId]),
    repository.query('SELECT * FROM proposals ORDER BY closes_at ASC LIMIT 20'),
    repository.query("SELECT machines.*, business_assets.business_id, businesses.name AS business_name FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id LEFT JOIN businesses ON businesses.id = business_assets.business_id WHERE machines.owner_id = $1 ORDER BY machines.id", [viewerId]),
    repository.query("SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewerId]),
    repository.query('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice'),
    repository.query('SELECT * FROM succession_plans WHERE human_id = $1', [viewerId]),
    repository.query('SELECT * FROM memberships WHERE human_id = $1', [viewerId]),
    repository.query('SELECT * FROM market_prices ORDER BY product'),
    repository.query('SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 25'),
    repository.query("SELECT * FROM cities WHERE id = COALESCE((SELECT city_id FROM memberships WHERE human_id = $1 AND city_id IS NOT NULL), 'CITY-0084')", [viewerId]),
    repository.query("SELECT * FROM corporations WHERE id = COALESCE((SELECT corporation_id FROM memberships WHERE human_id = $1 AND corporation_id IS NOT NULL), 'CORP-001')", [viewerId]),
    repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewerId]),
    repository.query("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = $1 OR negotiated_contracts.counterparty_id = $1 ORDER BY negotiated_contracts.created_at DESC LIMIT 30", [viewerId]),
    repository.query("SELECT si.*, sim.status AS member_status FROM social_initiatives si LEFT JOIN social_initiative_members sim ON sim.initiative_id = si.id AND sim.human_id = $1 WHERE si.creator_human_id = $1 OR si.target_human_id = $1 OR sim.human_id = $1 ORDER BY si.updated_at DESC LIMIT 30", [viewerId]),
    repository.query("SELECT bta.business_id, bta.technology_id, bta.adopted_game_day, b.name AS business_name, t.name AS technology_name FROM business_technology_adoptions bta JOIN businesses b ON b.id = bta.business_id JOIN technologies t ON t.id = bta.technology_id WHERE b.owner_id = $1 OR EXISTS (SELECT 1 FROM business_management bm WHERE bm.business_id = b.id AND bm.manager_id = $1) OR EXISTS (SELECT 1 FROM business_shares bs WHERE bs.business_id = b.id AND bs.holder_id = $1) ORDER BY bta.adopted_game_day DESC", [viewerId]),
  ]);
  const dynastyProgress = await repository.query<{ generation: number; dynasty_name: string | null; perks_count: number; heirlooms_count: number; legacy_points: number }>(`SELECT COALESCE(MAX(dlr.generation), 1)::integer AS generation, MAX(d.dynasty_name) AS dynasty_name,
      COUNT(DISTINCT dp.id)::integer AS perks_count, COUNT(DISTINCT dh.id)::integer AS heirlooms_count, COALESCE(MAX(d.legacy_points), 0)::integer AS legacy_points
    FROM dynasties d
    LEFT JOIN dynasty_lineage_records dlr ON dlr.dynasty_id = d.id
    LEFT JOIN dynasty_perks dp ON dp.dynasty_id = d.id
    LEFT JOIN dynasty_heirlooms dh ON dh.dynasty_id = d.id
    WHERE d.email = (SELECT email FROM auth_credentials WHERE human_id = $1)`, [viewerId]).catch(() => ({ rows: [] as { generation: number; dynasty_name: string | null; perks_count: number; heirlooms_count: number; legacy_points: number }[] }));
  const corporationSharedTechnology = await repository.query(
    `SELECT share.patent_id, patents.technology_id, technologies.name, share.shared_game_day
     FROM corporation_technology_shares share
     JOIN memberships member ON member.corporation_id = share.corporation_id AND member.human_id = $1
     JOIN patents ON patents.id = share.patent_id
     JOIN technologies ON technologies.id = patents.technology_id
     WHERE share.status = 'active'
     ORDER BY share.shared_game_day DESC, share.patent_id`,
    [viewerId],
  ).catch(() => ({ rows: [] as Array<Record<string, unknown>> }));
  const worldRow = world.rows[0] ?? {};
  const humanRow = human.rows[0] ?? {};
  const currentGameDay = Number(worldRow.game_day ?? 184);
  const currentGameMinute = Number(worldRow.game_minute ?? 0);
  const city = cityMetrics.rows[0] as Row | undefined;
  const corporation = corporationMetrics.rows[0] as Row | undefined;
  const voteCounts = (ballots.rows as Row[]).reduce<Record<string, Record<string, number>>>((all, row) => {
    const id = String(row.proposal_id);
    all[id] ??= {};
    all[id][String(row.choice)] = Number(row.count);
    return all;
  }, {});
  const products = Object.fromEntries((prices.rows as Row[]).map((row) => [row.product, { price: row.price, supply: row.supply, demand: row.demand }]));
  const referencePrice = (prices.rows as Row[])
    .filter((row) => row.product === 'components' || row.product === 'energy')
    .reduce((sum, row, _, rows) => sum + Number(row.price ?? 0) / Math.max(1, rows.length), 0);
  const startIndex = economicStartIndex(referencePrice || 50);
  const feeRate = Number(await marketFeeRate(repository, viewerId));
  const [rankings, book, trades, ownOrders, productionEvents, aiAssistants, communities, patents, licenses, finance, liquidity, audit, financialStates, roles, history, employees] = await Promise.all([
    Promise.all([
      repository.query('SELECT id, name, corporation_id, residents, treasury, housing_capacity, energy_capacity FROM cities ORDER BY treasury DESC LIMIT 20'),
      repository.query('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10'),
      repository.query("SELECT humans.id, humans.display_name, humans.standing, humans.legacy, memberships.city_id FROM humans JOIN memberships ON memberships.human_id = humans.id WHERE humans.life_status = 'active' AND memberships.city_id = (SELECT city_id FROM memberships WHERE human_id = $1) ORDER BY humans.standing DESC, humans.legacy DESC, humans.id LIMIT 20", [viewerId]),
    ]),
    repository.query("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product"),
    repository.query('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product'),
    repository.query("SELECT id, product, side, quantity, filled_quantity, limit_price, status, created_at FROM market_orders WHERE human_id = $1 AND status IN ('open','partial') ORDER BY created_at DESC LIMIT 50", [viewerId]),
    repository.query('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = $1 ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT 30', [viewerId]),
    repository.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE owner_id = $1 ORDER BY id', [viewerId]),
    repository.query('SELECT id, name, status FROM communities ORDER BY name LIMIT 20'),
    repository.query("SELECT COUNT(*)::integer AS count FROM patents WHERE technology_id = $1 AND status = 'active'", [technology.rows[0]?.id ?? '']),
    repository.query("SELECT COUNT(*)::integer AS count FROM technology_licenses WHERE patent_id IN (SELECT id FROM patents WHERE technology_id = $1) AND status = 'active'", [technology.rows[0]?.id ?? '']),
    repository.query('SELECT scope, category, rate, version FROM tax_rules WHERE active = true ORDER BY id'),
    repository.query("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index"),
    Promise.all([
      repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM machines WHERE condition < 0 OR condition > 100'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)'),
    ]),
    repository.query('SELECT institution_id, institution_kind, status, since_game_day, recovery_game_day FROM financial_states ORDER BY institution_kind, institution_id'),
    repository.query("SELECT institution_roles.id, institution_roles.name, institution_roles.institution_id, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id"),
    Promise.all([repository.query('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT 12'), repository.query('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT 20')]),
    repository.query("SELECT e.id, e.business_id, e.name, e.role, e.skill, e.morale, e.wage, e.status, e.hired_game_day FROM business_employees e WHERE e.business_id IN (SELECT b.id FROM businesses b LEFT JOIN business_management bm ON bm.business_id = b.id WHERE b.owner_id = $1 OR bm.manager_id = $1 OR EXISTS (SELECT 1 FROM business_shares bs WHERE bs.business_id = b.id AND bs.holder_id = $1)) ORDER BY e.status, e.name", [viewerId]),
  ]);
  const serviceRatios = city ? { housing: ratio(city.housing_capacity, city.residents), energy: ratio(city.energy_capacity, city.residents), connectivity: ratio(city.connectivity_capacity, city.residents), health: ratio(city.health_capacity, 100) } : { housing: 0.75, energy: 0.75, connectivity: 0.75, health: 0.5 };
  const serviceStatus = { housing: serviceRatios.housing >= 1 ? 'normal' : serviceRatios.housing >= 0.75 ? 'basic' : 'critical', utilities: serviceRatios.energy >= 1 ? 'normal' : serviceRatios.energy >= 0.75 ? 'basic' : 'critical', connectivity: serviceRatios.connectivity >= 1 ? 'normal' : serviceRatios.connectivity >= 0.75 ? 'basic' : 'critical', health: serviceRatios.health >= 0.8 ? 'normal' : serviceRatios.health >= 0.5 ? 'basic' : 'critical' };
  const cityQualification = city ? { activePopulation: Number(city.residents ?? 0) >= 10, housing: Number(city.housing_capacity ?? 0) >= Number(city.residents ?? 0), energy: Number(city.energy_capacity ?? 0) >= Number(city.residents ?? 0), connectivity: Number(city.connectivity_capacity ?? 0) >= Number(city.residents ?? 0), health: Number(city.health_capacity ?? 0) >= 50, treasury: Number(city.treasury ?? 0) >= 0, governance: true } : {};
  const corporationQualification = corporation ? { activeMembership: Number(corporation.member_count ?? 0) >= 30, recognizedCity: Boolean((await repository.query('SELECT id FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = $1 AND city_id IS NOT NULL LIMIT 1)', [corporation.id])).rows[0]), treasury: Number(corporation.treasury ?? 0) >= 1000, constitution: Number(corporation.constitution_version ?? 0) >= 1, governance: true } : {};
  const money = Number(liquidity.rows[0]?.money_supply ?? 0);
  const activeHumans = Number(liquidity.rows[0]?.active_humans ?? 0);
  const target = activeHumans * Math.max(0.5, Number(liquidity.rows[0]?.living_cost_index ?? 1)) * 100;
  const businessRow = business.rows[0] ?? {};
  const machineRows = machines.rows as Row[];
  const opportunities = rankOpportunities({
    market: prices.rows as Array<{ product: string; supply: unknown; demand: unknown; price: unknown }>,
    machines: machineRows as Array<{ id: string; name: string; output_resource: string; condition: unknown; utilization: unknown }>,
    businesses: business.rows as Array<{ id: string; name?: string; sector?: string; status?: string }>,
    proposals: proposals.rows as Array<{ id: string; title: string; status: string; closes_at?: unknown }>,
    communities: communities.rows as Array<{ id: string; name: string; status: string }>,
  });
  const resourceMap = Object.fromEntries((resources.rows as Row[]).map((row) => [row.resource, row.amount]));
  const decisionQueue = generateDecisionQueue({
    resources: resourceMap,
    machines: machineRows as Array<{ id: string; name?: string; condition?: unknown; utilization?: unknown; output_resource?: string }>,
    contracts: contracts.rows as Array<{ id: string; title?: string; status?: string; delivery_tick?: unknown; terms?: string }>,
    proposals: proposals.rows as Array<{ id: string; title?: string; status?: string; closes_game_day?: unknown; closes_game_minute?: unknown }>,
    technology: { progress: technology.rows[0]?.progress ?? 0, active_patents: Number(patents.rows[0]?.count ?? 0), is_funding_open: true },
    dynasty: { successor_id: succession.rows[0]?.successor_human_id ?? null, perks_available: Number(dynastyProgress.rows[0]?.legacy_points ?? 0) >= 100 && Number(dynastyProgress.rows[0]?.perks_count ?? 0) < 5 },
    business: { id: businessRow.id, name: businessRow.name, profit: businessRow.profit ?? 0, net_income: businessRow.net_income ?? 0, condition: businessRow.condition ?? 100, business_count: business.rows.length, service_business_count: business.rows.filter((row) => ['it-services', 'consulting', 'logistics', 'healthcare', 'education'].includes(String(row.sector))).length },
    finance: { unpaid_tax: 0, status: personalFinance.rows[0]?.status ?? 'active' },
    social: social.rows,
    market: prices.rows as Array<{ product: string; supply?: unknown; demand?: unknown; price?: unknown }>,
    gameDay: currentGameDay,
  });
  const objectives = evaluatePlayerObjectives({
    human: { credits: account.rows[0]?.balance ?? 0, standing: humanRow.standing ?? 0, legacy: humanRow.legacy ?? 0, voting_weight: 1, age_years: humanRow.age_years ?? 31 },
    business: { id: businessRow.id, business_count: business.rows.length, valuation: 35000, treasury: 5000, profit: businessRow.profit ?? 0, net_income: businessRow.net_income ?? 0 },
    institutions: {
      city: { essential_services_index: worldRow.essential_services_index ?? 0.68, standing: humanRow.standing ?? 0 },
      corporation: { treasury: Number(corporation?.treasury ?? 0), member_count: Number(corporation?.member_count ?? 0) },
    },
    governance: { voting_weight: 1 },
    technology: { research_progress: technology.rows[0]?.progress ?? 0, active_patents: Number(patents.rows[0]?.count ?? 0), active_licenses: Number(licenses.rows[0]?.count ?? 0) },
    dynasty: {
      generation: Number(dynastyProgress.rows[0]?.generation ?? 1),
      successor_id: succession.rows[0]?.successor_human_id ?? null,
      perks_count: Number(dynastyProgress.rows[0]?.perks_count ?? 0),
      heirlooms_count: Number(dynastyProgress.rows[0]?.heirlooms_count ?? 0),
    },
    resources: resourceMap,
    netWorth: Number(account.rows[0]?.balance ?? 0) + 15000,
  });
  const recommendations = [
    ...machineRows.filter((machine) => Number(machine.condition ?? 100) < 40).map((machine) => ({ type: 'maintenance', priority: 'high', subject: machine.id, message: `${machine.name} is below 40% condition; allocate Components or enable maintenance automation.` })),
    ...machineRows.filter((machine) => Number(machine.utilization ?? 0) > 0 && Number(machine.condition ?? 100) < 70).map((machine) => ({ type: 'utilization', priority: 'medium', subject: machine.id, message: `Reduce utilization for ${machine.name} until its condition improves.` })),
    ...(city && Number(city.health_capacity ?? 0) / 100 < 0.5 ? [{ type: 'services', priority: 'high', subject: 'CITY-HEALTH', message: 'Health service is critical; propose or fund additional city health capacity.' }] : []),
  ];
  const proposalsWithDeadlines = (proposals.rows as Row[]).map((proposal) => ({
    ...proposal,
    deadline: projectGameDeadline({
      gameDay: currentGameDay,
      gameMinute: currentGameMinute,
      deadlineGameDay: Number(proposal.closes_game_day),
      deadlineGameMinute: Number(proposal.closes_game_minute),
      closesAt: proposal.closes_at,
      nowMs: Date.now(),
      realSecondsPerGameMinute: 60,
    }),
  }));
  return {
    clock: { day: currentGameDay, minute: currentGameMinute, realSecondsPerGameMinute: 60 },
    world: { health: worldRow.health ?? 68, batch: worldRow.market_batch_seconds ?? 498, livingCostIndex: worldRow.living_cost_index ?? 1, economicStartIndex: startIndex, essentialServicesIndex: worldRow.essential_services_index ?? 0.68, serviceRatios, serviceStatus, cityQualification, corporationQualification },
    human: { id: humanRow.id, name: humanRow.display_name, credits: account.rows[0]?.balance ?? 0, standing: humanRow.standing ?? 0, legacy: humanRow.legacy ?? 0, ageYears: humanRow.age_years ?? 31, politicalEligibilityGameDay: humanRow.political_eligibility_game_day ?? 0, politicalMaturity: Number(worldRow.game_day ?? 0) >= Number(humanRow.political_eligibility_game_day ?? 0) },
    life: { generation: Number(dynastyProgress.rows[0]?.generation ?? 1), dynastyName: dynastyProgress.rows[0]?.dynasty_name ?? null, status: humanRow.life_status ?? 'active', ageYears: humanRow.age_years ?? 31, successor: succession.rows[0] ?? null, estatePeriodDays: succession.rows[0]?.estate_period_days ?? 30 },
    membership: membership.rows[0] ?? null,
    institutions: { ouc: mapByKind(institutions.rows, 'OUC'), corporation: { ...mapByKind(institutions.rows, 'CORPORATION'), ...corporation }, city: { ...mapByKind(institutions.rows, 'CITY'), ...city }, business: mapByKind(institutions.rows, 'BUSINESS') },
    resources: resourceMap,
    resourceFlows: flows,
    business: businessRow,
    businesses: business.rows,
    market: { products, book: book.rows, trades: trades.rows, orders: ownOrders.rows, feeRate, lastSettlement: null },
    governance: { proposals: proposalsWithDeadlines.map((proposal) => ({ ...proposal, votes: voteCounts[String(proposal.id)] ?? { support: 0, oppose: 0, abstain: 0 }, ballots: {} })) },
    technology: { research: technology.rows[0] ?? {}, catalog: TECHNOLOGY_CATALOG_DETAILS, adopted: technologyAdoptions.rows, activePatents: Number(patents.rows[0]?.count ?? 0), activeLicenses: Number(licenses.rows[0]?.count ?? 0), corporationSharedPatents: corporationSharedTechnology.rows }, machines: machineRows, workforce: employees.rows, productionEvents: productionEvents.rows, aiAssistants: aiAssistants.rows, aiRecommendations: recommendations, ledgerEntries: ledger.rows,
    publicActivity: [{ type: 'world_clock', day: worldRow.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: worldRow.market_batch_seconds ?? 498 }, ...social.rows.map((row) => ({ type: 'social', title: row.title, initiativeId: row.id, status: row.status }))], opportunities, decisionQueue, objectives, rankings: { cities: rankings[0].rows, corporations: rankings[1].rows }, history: { events: history[0].rows, rankings: history[1].rows }, financeStatus: financialStates.rows, personalFinance: personalFinance.rows[0] ?? { status: 'active', protected_credits: 100 }, contracts: contracts.rows, socialInitiatives: social.rows, roles: roles.rows, communities: communities.rows, cityMembers: rankings[2].rows,
    audit: { balancesNonNegative: Number(audit[0].rows[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(audit[1].rows[0]?.invalid ?? 0) === 0, machineConditionsBounded: Number(audit[2].rows[0]?.invalid ?? 0) === 0, corporationMemberCountsConsistent: Number(audit[3].rows[0]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(audit[4].rows[0]?.invalid ?? 0) === 0 },
    finance: { taxRules: finance.rows, liquidity: { activeHumans, moneySupply: money, target, corridor: { low: target * 0.8, high: target * 1.2 }, status: money < target * 0.8 ? 'below-corridor' : money > target * 1.2 ? 'above-corridor' : 'inside-corridor' } },
    persistence: 'planetscale-postgres',
  };
}
