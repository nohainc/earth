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
import { BUILDING_CATALOG } from './real-estate-catalog.ts';
import { getCityDistrictZoning } from './real-estate-postgres.ts';

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

  const [world, human, institutions, resources, business, technology, proposals, governanceRules, account, ballots, succession, membership, prices, ledger, cityMetrics, corporationMetrics, personalFinance, contracts, technologyAdoptions] = await Promise.all([
    repository.query('SELECT * FROM world_state WHERE id = $1', ['WORLD']),
    repository.query('SELECT * FROM humans WHERE id = $1', [viewerId]),
    repository.query('SELECT * FROM institutions'),
    repository.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1', [viewerId]),
    repository.query("SELECT businesses.*, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id AND holder_id = $1), 0) AS owned_shares, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id), 0) AS total_issued_shares, (SELECT holder_id FROM business_shares WHERE business_id = businesses.id ORDER BY shares DESC, holder_id LIMIT 1) AS controlling_human_id, COALESCE(business_constitutions.version, 1) AS constitution_version, COALESCE(business_constitutions.shareholder_vote_threshold, 0.5) AS shareholder_vote_threshold, COALESCE(business_constitutions.board_approval_threshold, 0.5) AS board_approval_threshold, COALESCE(business_constitutions.dilution_notice_days, 3) AS dilution_notice_days, COALESCE(business_management.manager_id, businesses.owner_id) AS manager_id, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit FROM businesses LEFT JOIN business_constitutions ON business_constitutions.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id LEFT JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.owner_id = $1 OR business_management.manager_id = $1 OR EXISTS (SELECT 1 FROM business_shares viewer_shares WHERE viewer_shares.business_id = businesses.id AND viewer_shares.holder_id = $1) ORDER BY businesses.id", [viewerId]),
    repository.query('SELECT * FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewerId]),
    repository.query('SELECT * FROM proposals ORDER BY closes_at ASC LIMIT 20'),
    repository.query("SELECT * FROM governance_rules WHERE status IN ('active','superseded') ORDER BY institution_id, category, version DESC"),
    repository.query("SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewerId]),
    repository.query('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice'),
    repository.query('SELECT * FROM succession_plans WHERE human_id = $1', [viewerId]),
    repository.query('SELECT * FROM memberships WHERE human_id = $1', [viewerId]),
    repository.query('SELECT * FROM market_prices ORDER BY product'),
    repository.query('SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 25'),
    repository.query("SELECT c.*, i.name FROM cities c JOIN memberships m ON m.city_id = c.id JOIN institutions i ON i.id = c.institution_id WHERE m.human_id = $1 LIMIT 1", [viewerId]),
    // Resolve the active corporation strictly from this user's membership.
    // Falling back to CORP-001 made Helios appear as the active corporation
    // when a newly joined corporation was not present in a stale snapshot.
    repository.query("SELECT c.*, i.name FROM corporations c JOIN memberships m ON m.corporation_id = c.id JOIN institutions i ON i.id = c.institution_id WHERE m.human_id = $1 LIMIT 1", [viewerId]),
    repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewerId]),
    repository.query("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = $1 OR negotiated_contracts.counterparty_id = $1 ORDER BY negotiated_contracts.created_at DESC LIMIT 30", [viewerId]),
    repository.query("SELECT bta.business_id, bta.technology_id, bta.adopted_game_day, b.name AS business_name, t.name AS technology_name FROM business_technology_adoptions bta JOIN businesses b ON b.id = bta.business_id JOIN technologies t ON t.id = bta.technology_id WHERE b.owner_id = $1 OR EXISTS (SELECT 1 FROM business_management bm WHERE bm.business_id = b.id AND bm.manager_id = $1) OR EXISTS (SELECT 1 FROM business_shares bs WHERE bs.business_id = b.id AND bs.holder_id = $1) ORDER BY bta.adopted_game_day DESC", [viewerId]),
  ]);
  const houseProgress = await repository.query<{ generation: number; house_name: string | null; epitaph: string | null; perks_count: number; heirlooms_count: number; legacy_points: number }>(`SELECT COALESCE(MAX(hlr.generation), 1)::integer AS generation, MAX(h.house_name) AS house_name,
      MAX(hlr.epitaph) FILTER (WHERE hlr.human_id = $1) AS epitaph,
      COUNT(DISTINCT hp.id)::integer AS perks_count, COUNT(DISTINCT hh.id)::integer AS heirlooms_count, COALESCE(MAX(h.legacy_points), 0)::integer AS legacy_points
    FROM houses h
    LEFT JOIN house_lineage_records hlr ON hlr.house_id = h.id
    LEFT JOIN house_perks hp ON hp.house_id = h.id
    LEFT JOIN house_heirlooms hh ON hh.house_id = h.id
    WHERE h.email = (SELECT email FROM auth_credentials WHERE human_id = $1)`, [viewerId]).catch(() => ({ rows: [] as { generation: number; house_name: string | null; epitaph: string | null; perks_count: number; heirlooms_count: number; legacy_points: number }[] }));
  const corporationSharedTechnology = { rows: [] as Array<Record<string, unknown>> };
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
  const [rankings, book, trades, ownOrders, aiAssistants, communities, finance, liquidity, audit, financialStates, roles, history, buildings, investmentShares, civicDividends, corporateResearch, districtZoning] = await Promise.all([
    Promise.all([
      repository.query(`
        SELECT entity_id AS id, entity_name AS name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics, affiliation,
               (raw_metrics->>'capitalization')::numeric AS capitalization,
               (raw_metrics->>'businesses')::integer AS businesses_count,
               (raw_metrics->>'residents')::integer AS residents,
               (raw_metrics->>'housing_capacity')::integer AS housing_capacity,
               (raw_metrics->>'energy_capacity')::integer AS energy_capacity,
               (raw_metrics->>'connectivity_capacity')::integer AS connectivity_capacity,
               (raw_metrics->>'health_capacity')::integer AS health_capacity,
               (raw_metrics->>'treasury')::numeric AS treasury
        FROM civic_rankings
        WHERE category = 'cities'
        ORDER BY rank ASC
      `).then(async (res) => {
        if (res.rows.length > 0) return res;
        return repository.query(`SELECT cities.id, city_institutions.name, city_institutions.charter_rules, cities.corporation_id, cities.residents, cities.treasury, cities.housing_capacity, cities.energy_capacity, cities.connectivity_capacity, cities.health_capacity
          FROM cities
          JOIN institutions city_institutions ON city_institutions.id = cities.institution_id
          ORDER BY (LEAST(1, housing_capacity / GREATEST(1, residents::numeric)) * 25
            + LEAST(1, energy_capacity / GREATEST(1, residents::numeric)) * 25
            + LEAST(1, connectivity_capacity / GREATEST(1, residents::numeric)) * 20
            + LEAST(1, health_capacity / 100.0) * 20
            + LEAST(1, GREATEST(0, treasury::numeric) / 10000.0) * 10) DESC, residents DESC, id LIMIT 20`);
      }).catch(() => repository.query(`SELECT cities.id, city_institutions.name, city_institutions.charter_rules, cities.corporation_id, cities.residents, cities.treasury, cities.housing_capacity, cities.energy_capacity, cities.connectivity_capacity, cities.health_capacity
          FROM cities
          JOIN institutions city_institutions ON city_institutions.id = cities.institution_id
          ORDER BY id LIMIT 20`)),
      repository.query(`
        SELECT entity_id AS id, entity_name AS name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics,
               (raw_metrics->>'totalCapitalization')::numeric AS capitalization,
               (raw_metrics->>'totalBusinesses')::integer AS businesses_count,
               (raw_metrics->>'totalResidents')::integer AS member_count,
               (raw_metrics->>'directTreasury')::numeric AS treasury
        FROM civic_rankings
        WHERE category = 'corporations'
        ORDER BY rank ASC
      `).then(async (res) => {
        if (res.rows.length > 0) return res;
        return repository.query(`SELECT c.id, c.member_count, c.treasury,
          i.name, i.status, i.charter_rules,
          c.capital_city_id,
          cap_i.name AS capital_city_name,
          COALESCE((SELECT COUNT(*) FROM cities WHERE cities.corporation_id = c.id), 0)::integer AS city_count,
          (LEAST(1, GREATEST(0, c.member_count::numeric) / 100.0) * 55
           + LEAST(1, GREATEST(0, c.treasury::numeric) / 25000.0) * 25
           + LEAST(1, (SELECT COUNT(*)::numeric FROM businesses b WHERE b.owner_id IN (SELECT human_id FROM memberships m WHERE m.corporation_id = c.id) AND b.status = 'active') / 10.0) * 20) AS development_score
        FROM corporations c
        JOIN institutions i ON i.id = c.institution_id
        LEFT JOIN institutions cap_i ON cap_i.id = c.capital_city_id
        ORDER BY development_score DESC, c.member_count DESC, c.id LIMIT 10`);
      }).catch(() => repository.query(`SELECT c.id, c.member_count, c.treasury, i.name FROM corporations c JOIN institutions i ON i.id = c.institution_id ORDER BY id LIMIT 10`)),
      repository.query(`
        SELECT entity_id AS id, entity_name AS display_name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics, affiliation,
               (raw_metrics->>'legacy')::integer AS legacy,
               (raw_metrics->>'standing')::integer AS standing,
               (raw_metrics->>'personalCapitalization')::numeric AS credits,
               final_score AS composite_index
        FROM civic_rankings
        WHERE category = 'citizens'
        ORDER BY rank ASC
      `).then(async (res) => {
        if (res.rows.length > 0) return res;
        return repository.query(`SELECT humans.id, humans.display_name, humans.standing, humans.legacy,
                                 memberships.city_id,
                                 memberships.corporation_id,
                                 (SELECT name FROM institutions WHERE id = memberships.city_id) AS city_name,
                                 (SELECT name FROM institutions WHERE id = memberships.corporation_id) AS corporation_name,
                                 h.house_name,
                                 COALESCE(ab.balance, '0') AS credits,
                                 ROUND(
                                   LEAST(1, GREATEST(0, humans.legacy::numeric) / 200.0) * 45 +
                                   LEAST(1, GREATEST(0, humans.standing::numeric) / 1000.0) * 35 +
                                   LEAST(1, GREATEST(0, COALESCE(ab.balance::numeric, 0)) / 50000.0) * 20
                                 )::integer AS composite_index
                          FROM humans
                          LEFT JOIN account_balances ab ON ab.account_id = humans.account_id AND ab.currency = 'CREDIT'
                          LEFT JOIN memberships ON memberships.human_id = humans.id
                          LEFT JOIN houses h ON h.founder_human_id = humans.id
                          WHERE humans.life_status = 'active'
                          ORDER BY composite_index DESC, humans.standing DESC, humans.id
                          LIMIT 20`);
      }).catch(() => ({ rows: [] })),
    ]),
    repository.query("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product"),
    repository.query('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product'),
    repository.query("SELECT id, product, side, quantity, filled_quantity, limit_price, status, created_at FROM market_orders WHERE human_id = $1 AND status IN ('open','partial') ORDER BY created_at DESC LIMIT 50", [viewerId]),
    repository.query('SELECT id, tier, policy, enabled FROM ai_assistants WHERE owner_id = $1 ORDER BY id', [viewerId]),
    repository.query(`
      SELECT 
        c.id, 
        c.name, 
        COALESCE(c.description, '') AS description, 
        c.founder_id, 
        COALESCE(h.display_name, 'Citizen') AS founder_name, 
        c.status, 
        COALESCE(c.admission_policy, 'open') AS admission_policy, 
        COALESCE(c.application_question, '') AS application_question,
        COALESCE(c.shared_credits, 0) AS shared_credits,
        (SELECT COUNT(*)::integer FROM community_members cm WHERE cm.community_id = c.id) AS member_count,
        (SELECT cm.role FROM community_members cm WHERE cm.community_id = c.id AND cm.human_id = $1) AS my_role,
        (SELECT cmr.status FROM community_membership_requests cmr WHERE cmr.community_id = c.id AND cmr.human_id = $1 AND cmr.status = 'pending' LIMIT 1) AS my_request_status
      FROM communities c
      LEFT JOIN humans h ON h.id = c.founder_id
      ORDER BY c.name
      LIMIT 50
    `, [viewerId]),
    repository.query('SELECT scope, category, rate, version FROM tax_rules WHERE active = true ORDER BY id'),
    repository.query("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index"),
    Promise.all([
      repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)'),
    ]),
    repository.query('SELECT institution_id, institution_kind, status, since_game_day, recovery_game_day FROM financial_states ORDER BY institution_kind, institution_id'),
    repository.query("SELECT institution_roles.id, institution_roles.name, institution_roles.institution_id, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id"),
    Promise.all([repository.query('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT 12'), repository.query('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT 20')]),
    repository.query("SELECT b.* FROM buildings b WHERE b.owner_id = $1 OR b.city_id = COALESCE((SELECT city_id FROM memberships WHERE human_id = $1 LIMIT 1), 'CITY-0084') ORDER BY b.created_game_day DESC, b.id", [viewerId]).catch(() => ({ rows: [] })),
    repository.query(`
      SELECT
        b.id AS building_id,
        b.name AS building_name,
        b.building_type,
        b.condition,
        COALESCE(s.shares_owned, 0)::integer AS shares_owned,
        COALESCE(s.total_shares_issued, 1000)::integer AS total_shares_issued,
        COALESCE(s.invested_credits, 0) AS invested_credits,
        COALESCE(s.accumulated_dividends_crd, 0) AS accumulated_dividends_crd,
        COALESCE((SELECT SUM(all_shares.shares_owned) FROM building_investment_shares all_shares WHERE all_shares.building_id = b.id), 0)::integer AS shares_sold
      FROM buildings b
      LEFT JOIN building_investment_shares s
        ON s.building_id = b.id AND s.investor_id = $1
      WHERE b.ownership_class = 'public_investment'
        AND b.status NOT IN ('closed', 'foreclosed')
    `, [viewerId]).catch(() => ({ rows: [] })),
    repository.query("SELECT * FROM civic_dividend_payouts WHERE city_id = COALESCE((SELECT city_id FROM memberships WHERE human_id = $1 LIMIT 1), 'CITY-0084') ORDER BY day DESC LIMIT 5").catch(() => ({ rows: [] })),
    repository.query("SELECT crp.* FROM corporate_research_pools crp WHERE crp.corporation_id = COALESCE((SELECT corporation_id FROM memberships WHERE human_id = $1 LIMIT 1), 'CORP-001') ORDER BY crp.status, crp.created_at DESC", [viewerId]).catch(() => ({ rows: [] })),
    getCityDistrictZoning(repository, city?.id ?? 'CITY-0084').catch(() => ({
      cityId: 'CITY-0084',
      cityName: 'New Carthage',
      population: 12,
      totalSlots: 10,
      civicReservedSlots: 3,
      usedPrivateSlots: 0,
      usedCivicSlots: 6,
      availablePrivateSlots: 7,
      availableCivicSlots: 4,
      buildingsCount: 3,
    })),
  ]);
  const buildingsRows = buildings?.rows ?? [];
  const investmentSharesRows = investmentShares?.rows ?? [];
  const civicDividendsRows = civicDividends?.rows ?? [];
  const corporateResearchRows = corporateResearch?.rows ?? [];
  const districtZoningData = districtZoning ?? {
    cityId: city?.id ?? 'CITY-0084',
    cityName: 'New Carthage',
    population: 12,
    totalSlots: 10,
    civicReservedSlots: 3,
    usedPrivateSlots: 0,
    usedCivicSlots: 6,
    availablePrivateSlots: 7,
    availableCivicSlots: 4,
    buildingsCount: 3,
  };
  const serviceRatios = city ? { housing: ratio(city.housing_capacity, city.residents), energy: ratio(city.energy_capacity, city.residents), connectivity: ratio(city.connectivity_capacity, city.residents), health: ratio(city.health_capacity, 100) } : { housing: 0.75, energy: 0.75, connectivity: 0.75, health: 0.5 };
  const serviceStatus = { housing: serviceRatios.housing >= 1 ? 'normal' : serviceRatios.housing >= 0.75 ? 'basic' : 'critical', utilities: serviceRatios.energy >= 1 ? 'normal' : serviceRatios.energy >= 0.75 ? 'basic' : 'critical', connectivity: serviceRatios.connectivity >= 1 ? 'normal' : serviceRatios.connectivity >= 0.75 ? 'basic' : 'critical', health: serviceRatios.health >= 0.8 ? 'normal' : serviceRatios.health >= 0.5 ? 'basic' : 'critical' };
  const cityQualification = city ? { activePopulation: Number(city.residents ?? 0) >= 10, housing: Number(city.housing_capacity ?? 0) >= Number(city.residents ?? 0), energy: Number(city.energy_capacity ?? 0) >= Number(city.residents ?? 0), connectivity: Number(city.connectivity_capacity ?? 0) >= Number(city.residents ?? 0), health: Number(city.health_capacity ?? 0) >= 50, treasury: Number(city.treasury ?? 0) >= 0, governance: true } : {};
  const corporationQualification = corporation ? { activeMembership: Number(corporation.member_count ?? 0) >= 30, recognizedCity: Boolean((await repository.query('SELECT id FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = $1 AND city_id IS NOT NULL LIMIT 1)', [corporation.id])).rows[0]), treasury: Number(corporation.treasury ?? 0) >= 1000, constitution: Number(corporation.constitution_version ?? 0) >= 1, governance: true } : {};
  const money = Number(liquidity.rows[0]?.money_supply ?? 0);
  const activeHumans = Number(liquidity.rows[0]?.active_humans ?? 0);
  const target = activeHumans * Math.max(0.5, Number(liquidity.rows[0]?.living_cost_index ?? 1)) * 100;
  const businessRow = business.rows[0] ?? {};
  const activeBusinesses = business.rows.filter((row) => String(row.status ?? 'active') === 'active');
  const portfolioProfit = activeBusinesses.reduce((sum, row) => sum + Number(row.profit ?? 0), 0);
  const portfolioValuation = activeBusinesses.reduce((sum, row) => sum + 10000 + Math.max(0, Number(row.profit ?? 0)) * 12, 0);
  const opportunities = rankOpportunities({
    market: prices.rows as Array<{ product: string; supply: unknown; demand: unknown; price: unknown }>,
    businesses: business.rows as Array<{ id: string; name?: string; sector?: string; status?: string }>,
    proposals: proposals.rows as Array<{ id: string; title: string; status: string; closes_at?: unknown }>,
    communities: communities.rows as Array<{ id: string; name: string; status: string }>,
  });
  const resourceMap = Object.fromEntries((resources.rows as Row[]).map((row) => [row.resource, row.amount]));
  const decisionQueue = generateDecisionQueue({
    resources: resourceMap,
    contracts: contracts.rows as Array<{ id: string; title?: string; status?: string; delivery_tick?: unknown; terms?: string }>,
    proposals: proposals.rows as Array<{ id: string; title?: string; status?: string; closes_game_day?: unknown; closes_game_minute?: unknown }>,
    technology: { progress: technology.rows[0]?.progress ?? 0, is_funding_open: true },
    house: { successor_id: succession.rows[0]?.successor_human_id ?? null, perks_available: Number(houseProgress.rows[0]?.legacy_points ?? 0) >= 100 && Number(houseProgress.rows[0]?.perks_count ?? 0) < 5 },
    city: city ? { id: city.id, residents: city.residents, housing_capacity: city.housing_capacity, energy_capacity: city.energy_capacity, connectivity_capacity: city.connectivity_capacity, health_capacity: city.health_capacity } : undefined,
    business: { id: businessRow.id, name: businessRow.name, profit: portfolioProfit, net_income: portfolioProfit, valuation: portfolioValuation, condition: businessRow.condition ?? 100, business_count: activeBusinesses.length, service_business_count: activeBusinesses.filter((row) => ['it-services', 'consulting', 'logistics', 'healthcare', 'education'].includes(String(row.sector))).length },
    finance: { unpaid_tax: 0, status: personalFinance.rows[0]?.status ?? 'active' },
    market: prices.rows as Array<{ product: string; supply?: unknown; demand?: unknown; price?: unknown }>,
    gameDay: currentGameDay,
  });
  const objectiveRuleRows = await repository.query<{ key: string; value: string }>("SELECT key, value FROM world_rules WHERE key LIKE 'objectives.%'").catch(() => ({ rows: [] }));
  const objectiveRules = Object.fromEntries(objectiveRuleRows.rows.map((row) => [row.key, Number(row.value)]));
  const objectives = evaluatePlayerObjectives({
    human: { credits: account.rows[0]?.balance ?? 0, standing: humanRow.standing ?? 0, legacy: humanRow.legacy ?? 0, voting_weight: 1, age_years: humanRow.age_years ?? 31 },
    business: { id: businessRow.id, business_count: activeBusinesses.length, valuation: portfolioValuation, treasury: Number(corporation?.treasury ?? 0), profit: portfolioProfit, net_income: portfolioProfit },
    institutions: {
      city: { essential_services_index: worldRow.essential_services_index ?? 0.68, standing: humanRow.standing ?? 0 },
      corporation: { treasury: Number(corporation?.treasury ?? 0), member_count: Number(corporation?.member_count ?? 0) },
    },
    governance: { voting_weight: 1 },
    technology: { research_progress: technology.rows[0]?.progress ?? 0 },
    house: {
      generation: Number(houseProgress.rows[0]?.generation ?? 1),
      successor_id: succession.rows[0]?.successor_human_id ?? null,
      perks_count: Number(houseProgress.rows[0]?.perks_count ?? 0),
      heirlooms_count: Number(houseProgress.rows[0]?.heirlooms_count ?? 0),
    },
    resources: resourceMap,
    netWorth: Number(account.rows[0]?.balance ?? 0) + 15000,
  }, objectiveRules);
  const recommendations = [
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
  const constitutionalRules = await repository.query(
    `SELECT constitutional_rules.id, constitutional_rules.part_number, constitutional_rules.article_number,
      constitutional_rules.rule_number, constitutional_rules.title, constitutional_rules.description, constitutional_rules.authority,
      CASE constitutional_rules.rule_number
        WHEN '1.1' THEN CASE WHEN basic_income_tax.rate IS NULL THEN NULL ELSE trim(trailing '.' from to_char(basic_income_tax.rate * 100, 'FM999999990.999999')) || '%' END
        WHEN '1.2' THEN CASE WHEN business_tax.rate IS NULL THEN NULL ELSE trim(trailing '.' from to_char(business_tax.rate * 100, 'FM999999990.999999')) || '%' END
        WHEN '1.3' THEN CASE WHEN market_tax.rate IS NULL THEN NULL ELSE trim(trailing '.' from to_char(market_tax.rate * 100, 'FM999999990.999999')) || '%' END
        WHEN '1.4' THEN CASE WHEN business_tax_allocation.id IS NULL THEN NULL ELSE 'City ' || trim(trailing '.' from to_char(business_tax_allocation.city_share * 100, 'FM999999990.999999')) || '% · Corporation ' || trim(trailing '.' from to_char(business_tax_allocation.corporation_share * 100, 'FM999999990.999999')) || '% · Earth ' || trim(trailing '.' from to_char(business_tax_allocation.earth_share * 100, 'FM999999990.999999')) || '%' END
        WHEN '2.1' THEN CASE WHEN earth_governance.quorum_threshold IS NULL THEN NULL ELSE trim(trailing '.' from to_char(earth_governance.quorum_threshold * 100, 'FM999999990.999999')) || '%' END
        WHEN '2.2' THEN CASE WHEN earth_governance.approval_threshold IS NULL THEN NULL ELSE trim(trailing '.' from to_char(earth_governance.approval_threshold * 100, 'FM999999990.999999')) || '%' END
        WHEN '2.3' THEN CASE WHEN earth_governance.implementation_delay_days IS NULL THEN NULL ELSE earth_governance.implementation_delay_days::text || ' game day' || CASE WHEN earth_governance.implementation_delay_days = 1 THEN '' ELSE 's' END END
        ELSE constitutional_rules.default_value
      END AS default_value,
      constitutional_rules.permitted_values, constitutional_rules.updated_game_day
    FROM constitutional_rules
    LEFT JOIN tax_rules basic_income_tax ON basic_income_tax.id = 'TAX-OUC-BASIC' AND basic_income_tax.active = true
    LEFT JOIN tax_rules business_tax ON business_tax.id = 'TAX-OUC-BUSINESS' AND business_tax.active = true
    LEFT JOIN tax_rules market_tax ON market_tax.id = 'TAX-OUC-MARKET' AND market_tax.active = true
    LEFT JOIN LATERAL (
      SELECT id, city_share, corporation_share, earth_share
      FROM business_tax_allocation_rules
      WHERE active = true
      ORDER BY version DESC
      LIMIT 1
    ) business_tax_allocation ON true
    LEFT JOIN LATERAL (
      SELECT governance_rules.quorum_threshold, governance_rules.approval_threshold, governance_rules.implementation_delay_days
      FROM governance_rules
      JOIN institutions ON institutions.id = governance_rules.institution_id
      WHERE institutions.kind = 'OUC' AND governance_rules.status = 'active'
      ORDER BY governance_rules.version DESC
      LIMIT 1
    ) earth_governance ON true
    WHERE constitutional_rules.active = true
    ORDER BY constitutional_rules.part_number, constitutional_rules.article_number, constitutional_rules.rule_number`,
  ).catch(() => ({ rows: [] }));
  return {
    clock: { day: currentGameDay, minute: currentGameMinute, realSecondsPerGameMinute: 60 },
    world: { health: worldRow.health ?? 68, batch: worldRow.market_batch_seconds ?? 498, livingCostIndex: worldRow.living_cost_index ?? 1, economicStartIndex: startIndex, essentialServicesIndex: worldRow.essential_services_index ?? 0.68, serviceRatios, serviceStatus, cityQualification, corporationQualification },
    human: { id: humanRow.id, name: humanRow.display_name, epitaph: houseProgress.rows[0]?.epitaph ?? null, credits: account.rows[0]?.balance ?? 0, standing: humanRow.standing ?? 0, legacy: humanRow.legacy ?? 0, ageYears: humanRow.age_years ?? 31, health: 100, vitality: 100, energy: 100, stamina: 100, politicalEligibilityGameDay: humanRow.political_eligibility_game_day ?? 0, politicalMaturity: Number(worldRow.game_day ?? 0) >= Number(humanRow.political_eligibility_game_day ?? 0) },
    life: { generation: Number(houseProgress.rows[0]?.generation ?? 1), houseName: houseProgress.rows[0]?.house_name ?? null, epitaph: houseProgress.rows[0]?.epitaph ?? null, status: humanRow.life_status ?? 'active', ageYears: humanRow.age_years ?? 31, health: 100, vitality: 100, energy: 100, successor: succession.rows[0] ?? null, estatePeriodDays: succession.rows[0]?.estate_period_days ?? 30 },
    membership: membership.rows[0] ?? null,
    institutions: {
      ouc: mapByKind(institutions.rows, 'OUC'),
      // Only expose an active city/corporation when it belongs to this user.
      // Never substitute the first registry entry as an affiliation.
      corporation: corporation ?? {},
      city: city ?? {},
      business: mapByKind(institutions.rows, 'BUSINESS'),
    },
    resources: resourceMap,
    resourceFlows: flows,
    business: businessRow,
    businesses: business.rows,
    buildings: buildingsRows,
    districtZoning: districtZoningData,
    investmentShares: investmentSharesRows,
    civicDividends: civicDividendsRows,
    corporateResearch: corporateResearchRows,
    constitutionalRules: constitutionalRules.rows,
    buildingCatalog: Object.values(BUILDING_CATALOG),
    market: { products, book: book.rows, trades: trades.rows, orders: ownOrders.rows, feeRate, lastSettlement: null },
    governance: { proposals: proposalsWithDeadlines.map((proposal) => ({ ...proposal, votes: voteCounts[String(proposal.id)] ?? { support: 0, oppose: 0, abstain: 0 }, ballots: {} })), rules: governanceRules.rows },
    technology: { research: technology.rows[0] ?? {}, catalog: TECHNOLOGY_CATALOG_DETAILS, adopted: technologyAdoptions.rows }, workforce: [], aiAssistants: aiAssistants.rows, aiRecommendations: recommendations, ledgerEntries: ledger.rows,
    publicActivity: [{ type: 'world_clock', day: worldRow.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: worldRow.market_batch_seconds ?? 498 }], opportunities, decisionQueue, objectives, rankings: { cities: rankings[0].rows.map((row) => ({ ...row, rules: fromNanoMarkup<Record<string, unknown>>(row.charter_rules), charter_rules: undefined })), corporations: rankings[1].rows.map((row) => ({ ...row, rules: fromNanoMarkup<Record<string, unknown>>(row.charter_rules), charter_rules: undefined })), citizens: rankings[2].rows.map((row) => ({ ...row, compositeScore: Math.round(Number(row.standing || 0) * 2 + Number(row.legacy || 0) * 3) })), humans: rankings[2].rows.map((row) => ({ ...row, compositeScore: Math.round(Number(row.standing || 0) * 2 + Number(row.legacy || 0) * 3) })) }, history: { events: history[0].rows, rankings: history[1].rows }, financeStatus: financialStates.rows, personalFinance: personalFinance.rows[0] ?? { status: 'active', protected_credits: 100 }, contracts: contracts.rows, roles: roles.rows, communities: communities.rows, cityMembers: rankings[2].rows,
    audit: { balancesNonNegative: Number(audit[0].rows[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(audit[1].rows[0]?.invalid ?? 0) === 0, corporationMemberCountsConsistent: Number(audit[2].rows[0]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(audit[3].rows[0]?.invalid ?? 0) === 0 },
    finance: { taxRules: finance.rows, liquidity: { activeHumans, moneySupply: money, target, corridor: { low: target * 0.8, high: target * 1.2 }, status: money < target * 0.8 ? 'below-corridor' : money > target * 1.2 ? 'above-corridor' : 'inside-corridor' } },
    persistence: 'planetscale-postgres',
  };
}
