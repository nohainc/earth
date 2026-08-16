import type { PostgresRepository } from './repository.ts';
import { settleMarket } from './market-postgres.ts';
import { processMortality } from './lifecycle-postgres.ts';
import { transferCredits } from './financial-postgres.ts';
import { classifyBusinessFinancialStatus } from './business-finance.ts';
import { centsToMoney, compoundRateAmountToCents, moneyToCents, quantityToCents, rateAmountToCents } from './money.ts';
import { validateWorldAdvanceMinutes } from './scheduler-rules.ts';
import { toNanoMarkup } from './nano-markup.ts';

const products = ['material', 'components', 'energy', 'compute'];

async function settleBusinessDepreciation(tx: PostgresRepository, day: number): Promise<void> {
  const assets = await tx.query<{ business_id: string; machine_id: string; book_value: string }>('SELECT business_assets.business_id, business_assets.machine_id, COALESCE(machine_acquisitions.credit_cost, 0) AS book_value FROM business_assets LEFT JOIN machine_acquisitions ON machine_acquisitions.machine_id = business_assets.machine_id');
  for (const asset of assets.rows) {
    const amountCents = rateAmountToCents(moneyToCents(asset.book_value), '0.01', 1);
    if (amountCents <= 0n) continue;
    const amount = centsToMoney(amountCents);
    const correlationId = `DEPRECIATION-${asset.business_id}-${asset.machine_id}-${day}`;
    const prior = await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'business_depreciation\' AND correlation_id = $1', [correlationId]);
    if (prior.rows[0]) continue;
    await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [amount, day, asset.business_id]);
    await tx.query('INSERT INTO ledger_entries (id,game_day,debit_account,credit_account,amount,currency,reason_type,reason_id,rule_version,correlation_id) VALUES ($1,$2,$3,$4,$5,\'CREDIT\',\'business_depreciation\',$6,\'business-finance-v1\',$7)', [crypto.randomUUID(), day, `business-${asset.business_id}`, 'account-depreciation-expense', amount, asset.machine_id, correlationId]);
  }
}

async function settleBusinessTaxes(tx: PostgresRepository, day: number): Promise<void> {
  const rule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BUSINESS' AND active = true");
  if (!rule.rows[0]) return;
  const businesses = await tx.query<{ id: string; owner_id: string; revenue: string; taxed_revenue: string }>("SELECT businesses.id, businesses.owner_id, business_financials.revenue, business_financials.taxed_revenue FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.status = 'active'");
  for (const business of businesses.rows) {
    const taxableCents = moneyToCents(business.revenue) - moneyToCents(business.taxed_revenue);
    const taxCents = taxableCents > 0n ? rateAmountToCents(taxableCents, rule.rows[0].rate, 1) : 0n;
    if (taxCents <= 0n) { await tx.query('UPDATE business_financials SET taxed_revenue = GREATEST(taxed_revenue, revenue), last_game_day = $1 WHERE business_id = $2', [day, business.id]); continue; }
    const tax = centsToMoney(taxCents);
    const correlationId = `BUSINESS-TAX-${business.id}-${day}`;
    const prior = await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'business_tax\' AND correlation_id = $1', [correlationId]);
    if (prior.rows[0]) continue;
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [business.owner_id]);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < taxCents) continue;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-ouc-treasury', amount: tax, reasonType: 'business_tax', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId });
    await tx.query('UPDATE business_financials SET taxed_revenue = revenue, operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [tax, day, business.id]);
  }
}

async function settleBasicLevy(tx: PostgresRepository, day: number): Promise<void> {
  const rule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true");
  const world = await tx.query<{ living_cost_index: string }>("SELECT living_cost_index FROM world_state WHERE id = 'WORLD'");
  if (!rule.rows[0]) return;
  const levyBaseCents = compoundRateAmountToCents(10000n, String(world.rows[0]?.living_cost_index ?? '1'));
  const humans = await tx.query<{ id: string; account_id: string; balance: string }>("SELECT humans.id, account_balances.account_id, account_balances.balance FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'active'");
  for (const human of humans.rows) {
    const levyCents = rateAmountToCents(levyBaseCents, rule.rows[0].rate, 1);
    const levy = centsToMoney(levyCents);
    const correlationId = `BASIC-LEVY-${human.id}-${day}-v${rule.rows[0].version}`;
    if (levyCents <= 0n || moneyToCents(human.balance) < levyCents || (await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'basic_levy\' AND correlation_id = $1', [correlationId])).rows[0]) continue;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: human.account_id, creditAccount: 'account-ouc-treasury', amount: levy, reasonType: 'basic_levy', reasonId: human.id, ruleVersion: `tax-v${rule.rows[0].version}`, correlationId });
  }
}

async function runAiMaintenance(tx: PostgresRepository, day: number): Promise<void> {
  const assistants = await tx.query<{ owner_id: string; machine_id: string }>("SELECT ai_assistants.owner_id, machines.id AS machine_id FROM ai_assistants JOIN machines ON machines.owner_id = ai_assistants.owner_id WHERE ai_assistants.enabled = true AND ai_assistants.policy = 'maintenance' AND machines.maintenance_due > 0 AND machines.condition < 100");
  for (const assistant of assistants.rows) {
    const components = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE", [assistant.owner_id]);
    const amount = Math.min(5, Number(components.rows[0]?.amount ?? 0));
    if (amount <= 0) continue;
    await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components' AND amount >= $1", [amount, assistant.owner_id]);
    await tx.query('UPDATE machines SET condition = LEAST(100, condition + $1 * 0.8), maintenance_due = GREATEST(0, maintenance_due - $1) WHERE id = $2 AND owner_id = $3', [amount, assistant.machine_id, assistant.owner_id]);
    await tx.query("INSERT INTO maintenance_events (id,machine_id,owner_id,resource,amount,condition_before,condition_after,game_day) SELECT $1,id,owner_id,'components',$2,condition,LEAST(100,condition + $2 * 0.8),$3 FROM machines WHERE id = $4", [crypto.randomUUID(), amount, day, assistant.machine_id]);
  }
}

async function completeContracts(tx: PostgresRepository, day: number): Promise<void> {
  const contracts = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; title: string }>("SELECT id, proposer_id, counterparty_id, title FROM negotiated_contracts WHERE status = 'accepted' AND ends_game_day <= $1 FOR UPDATE", [day]);
  for (const contract of contracts.rows) {
    await tx.query("UPDATE negotiated_contracts SET status = 'completed' WHERE id = $1 AND status = 'accepted'", [contract.id]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'contract.completed\',\'A negotiated contract completed\',$3) ON CONFLICT (id) DO NOTHING', [`CONTRACT-COMPLETED-${contract.id}`, day, toNanoMarkup({ contractId: contract.id })]);
    for (const humanId of [contract.proposer_id, contract.counterparty_id]) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'contract\',\'Contract completed\',$3,$4) ON CONFLICT DO NOTHING', [`CONTRACT-COMPLETE-${contract.id}-${humanId}`, humanId, `${contract.title} completed on game day ${day}.`, contract.id]);
  }
}

async function settleTechnologyRoyalties(tx: PostgresRepository, day: number): Promise<void> {
  const licenses = await tx.query<{ id: string; licensor_id: string; licensee_id: string; royalty_rate: string }>("SELECT technology_licenses.id, licensor_id, licensee_id, royalty_rate FROM technology_licenses JOIN patents ON patents.id = technology_licenses.patent_id WHERE technology_licenses.status = 'active' AND patents.status = 'active' AND licensor_id <> licensee_id");
  for (const license of licenses.rows) {
    const usage = await tx.query<{ amount: string }>('SELECT COALESCE(SUM(amount), 0) AS amount FROM production_events WHERE owner_id = $1 AND game_day = $2', [license.licensee_id, day]);
    const royaltyCents = compoundRateAmountToCents(quantityToCents(usage.rows[0]?.amount ?? '0'), String(license.royalty_rate), '0.1');
    const royalty = centsToMoney(royaltyCents);
    if (royaltyCents <= 0n) continue;
    const correlationId = `ROYALTY-${license.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM ledger_entries WHERE correlation_id = $1 AND reason_type = 'technology_royalty'", [correlationId])).rows[0]) continue;
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id FOR UPDATE", [license.licensee_id, license.licensor_id]);
    const buyer = accounts.rows.find((row) => row.owner_id === license.licensee_id);
    const owner = accounts.rows.find((row) => row.owner_id === license.licensor_id);
    if (!buyer || !owner || moneyToCents(buyer.balance) < royaltyCents) {
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'technology\',\'Royalty payment pending\',$3,$4) ON CONFLICT DO NOTHING', [`ROYALTY-PENDING-${license.id}-${day}`, license.licensee_id, `The ${royalty} Credit royalty for license ${license.id} is pending until your balance is sufficient.`, license.id]);
      continue;
    }
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: buyer.account_id, creditAccount: owner.account_id, amount: royalty, reasonType: 'technology_royalty', reasonId: license.id, ruleVersion: 'technology-v3', correlationId });
    await tx.query("UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [royalty, day, license.licensee_id]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'technology\',\'Technology royalty paid\',$3,$4), ($5,$6,\'technology\',\'Technology royalty received\',$7,$4)', [crypto.randomUUID(), license.licensee_id, `${royalty} Credits paid for licensed technology usage.`, license.id, crypto.randomUUID(), license.licensor_id, `${royalty} Credits received from licensed technology usage.`]);
  }
}

async function updateFinancialStates(tx: PostgresRepository, day: number): Promise<void> {
  const candidates = await tx.query<{ id: string; kind: string; value: string; profit: string | null; condition: string | null; current: string }>("SELECT businesses.id, 'BUSINESS' AS kind, business_financials.profit AS value, business_financials.profit, businesses.condition, businesses.status AS current FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id UNION ALL SELECT id, 'CITY', treasury, NULL, NULL, 'active' FROM cities UNION ALL SELECT id, 'CORPORATION', treasury, NULL, NULL, 'active' FROM corporations");
  for (const candidate of candidates.rows) {
    const existing = await tx.query<{ status: string; since_game_day: number }>('SELECT status, since_game_day FROM financial_states WHERE institution_id = $1 FOR UPDATE', [candidate.id]);
    const current = existing.rows[0]?.status ?? candidate.current;
    if (current === 'dissolved') continue;
    const numeric = Number(candidate.value);
    const target = candidate.kind === 'BUSINESS'
      ? classifyBusinessFinancialStatus({ profit: candidate.profit, condition: candidate.condition, currentStatus: current, sinceGameDay: existing.rows[0] ? Number(existing.rows[0].since_game_day) : null, gameDay: day })
      : numeric <= 0 ? (existing.rows[0] && day - Number(existing.rows[0].since_game_day) >= 7 ? 'insolvent' : 'distressed') : 'active';
    if (target === current && existing.rows[0]) continue;
    const reason = target === 'active' ? 'Positive operating position restored' : 'Operating reserve is depleted';
    await tx.query('INSERT INTO financial_states (institution_id,institution_kind,status,since_game_day,recovery_game_day,last_reason) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT(institution_id) DO UPDATE SET status=EXCLUDED.status,recovery_game_day=EXCLUDED.recovery_game_day,last_reason=EXCLUDED.last_reason,updated_at=CURRENT_TIMESTAMP', [candidate.id, candidate.kind, target, existing.rows[0]?.since_game_day ?? day, target === 'active' ? day : null, reason]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,$5,$6,$7)', [crypto.randomUUID(), candidate.id, candidate.kind, current, target, day, reason]);
    if (candidate.kind === 'BUSINESS') await tx.query('UPDATE businesses SET status = $1 WHERE id = $2', [target === 'active' ? 'active' : 'distressed', candidate.id]);
  }
}

async function dissolveInstitutions(tx: PostgresRepository, day: number): Promise<void> {
  const candidates = await tx.query<{ id: string; kind: string; name: string }>("SELECT institutions.id, institutions.kind, institutions.name FROM institutions JOIN financial_states ON financial_states.institution_id = institutions.id WHERE financial_states.status = 'insolvent' AND $1 - financial_states.since_game_day >= 30 FOR UPDATE", [day]);
  for (const candidate of candidates.rows) {
    const members = candidate.kind === 'CITY'
      ? await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 FOR UPDATE', [candidate.id])
      : candidate.kind === 'CORPORATION'
        ? await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE corporation_id = $1 FOR UPDATE', [candidate.id])
        : { rows: [] } as { rows: Array<{ human_id: string }> };
    if (candidate.kind === 'CITY') {
      await tx.query('UPDATE memberships SET city_id = NULL WHERE city_id = $1', [candidate.id]);
      await tx.query('UPDATE cities SET residents = 0 WHERE id = $1', [candidate.id]);
    } else if (candidate.kind === 'CORPORATION') {
      await tx.query('UPDATE memberships SET corporation_id = NULL WHERE corporation_id = $1', [candidate.id]);
      await tx.query('UPDATE corporations SET member_count = 0 WHERE id = $1', [candidate.id]);
    } else if (candidate.kind === 'BUSINESS') {
      await tx.query("UPDATE businesses SET status = 'bankrupt' WHERE id = $1", [candidate.id]);
    }
    await tx.query("UPDATE institutions SET status = 'dissolved' WHERE id = $1", [candidate.id]);
    await tx.query("UPDATE financial_states SET status = 'dissolved', recovery_game_day = $1, last_reason = 'Institution remained insolvent beyond the engine resolution window', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2 AND status = 'insolvent'", [day, candidate.id]);
    const reason = 'Institution remained insolvent beyond the engine resolution window';
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,\'insolvent\',\'dissolved\',$4,$5) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, candidate.id, candidate.kind, day, reason]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'institution.dissolved\',$3,$4) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, day, `${candidate.kind} ${candidate.name} was dissolved`, toNanoMarkup({ institutionId: candidate.id, releasedMembers: members.rows.length })]);
    for (const member of members.rows) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'institution\',$3,$4,$5) ON CONFLICT DO NOTHING', [`DISSOLVE-${candidate.id}-${day}-${member.human_id}`, member.human_id, `${candidate.kind} dissolved`, `${candidate.kind} ${candidate.name} was dissolved after prolonged insolvency. Your institutional membership was released.`, candidate.id]);
  }
}

async function snapshotRankings(tx: PostgresRepository, day: number): Promise<void> {
  const [cities, corporations] = await Promise.all([
    tx.query<{ id: string; treasury: string }>('SELECT id, treasury FROM cities ORDER BY treasury DESC LIMIT 10'),
    tx.query<{ id: string; treasury: string }>('SELECT id, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10'),
  ]);
  for (const [index, row] of cities.rows.entries()) await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,\'city_treasury\',$3,$4,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`CITY-${day}-${row.id}`, day, row.id, index + 1, Number(row.treasury)]);
  for (const [index, row] of corporations.rows.entries()) await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,\'corporation_treasury\',$3,$4,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`CORP-${day}-${row.id}`, day, row.id, index + 1, Number(row.treasury)]);
  const prices = await tx.query<{ product: string; price: string }>('SELECT product, price FROM market_prices');
  for (const p of prices.rows) {
    await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,$3,$4,1,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`PRICE-${day}-${p.product}`, day, `market_price_${p.product}`, p.product, Number(p.price)]);
  }
}

async function processCityDynamics(tx: PostgresRepository, day: number): Promise<void> {
  const cities = await tx.query<{ id: string; residents: number; housing_capacity: number; energy_capacity: number; connectivity_capacity: number; health_capacity: number; treasury: string }>('SELECT * FROM cities WHERE residents > 0 ORDER BY id');
  for (const city of cities.rows) {
    const res = Math.max(1, Number(city.residents));
    if (Number(city.energy_capacity) < res) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`BROWNOUT-${city.id}-${day}`, day, 'city.brownout', `Power grid deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, capacity: city.energy_capacity, demand: city.residents })]);
    }
    if (Number(city.health_capacity) < res * 0.5) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`HEALTH-CRISIS-${city.id}-${day}`, day, 'city.healthcare_crisis', `Hospital capacity deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, healthCapacity: city.health_capacity, residents: city.residents })]);
    }
  }
  if (cities.rows.length >= 2) {
    const scoredCities = cities.rows.map((c) => {
      const res = Math.max(1, Number(c.residents));
      const housingScore = Math.min(1.2, Number(c.housing_capacity) / res);
      const energyScore = Math.min(1.2, Number(c.energy_capacity) / res);
      const healthScore = Math.min(1.0, Number(c.health_capacity) / 100);
      const connectivityScore = Math.min(1.0, Number(c.connectivity_capacity) / res);
      const totalScore = (housingScore + energyScore + healthScore + connectivityScore) / 4;
      return { ...c, totalScore };
    });
    const bestCity = scoredCities.reduce((prev, curr) => (curr.totalScore > prev.totalScore ? curr : prev), scoredCities[0]);
    const worstCity = scoredCities.reduce((prev, curr) => (curr.totalScore < prev.totalScore ? curr : prev), scoredCities[0]);
    if (bestCity.id !== worstCity.id && bestCity.totalScore >= 0.8 && worstCity.totalScore < 0.6 && Number(worstCity.residents) > 5) {
      const migrant = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 LIMIT 1 FOR UPDATE', [worstCity.id]);
      if (migrant.rows[0]) {
        await tx.query('UPDATE memberships SET city_id = $1 WHERE human_id = $2', [bestCity.id, migrant.rows[0].human_id]);
        await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [worstCity.id]);
        await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [bestCity.id]);
        await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CITY',$3,'joined',$4,'economic_migration')", [crypto.randomUUID(), migrant.rows[0].human_id, bestCity.id, day]);
        await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`MIGRATION-${migrant.rows[0].human_id}-${day}`, migrant.rows[0].human_id, 'institution', 'Relocated to higher-opportunity city', `You migrated from ${worstCity.id} to ${bestCity.id} due to superior municipal infrastructure and health services.`, bestCity.id]);
      }
    }
  }
}

async function processPatentExpirations(tx: PostgresRepository, day: number): Promise<void> {
  const expiredPatents = await tx.query<{ id: string; technology_id: string }>("SELECT id, technology_id FROM patents WHERE expiry_game_day <= $1 AND status = 'active'", [day]);
  if (expiredPatents.rows.length > 0) {
    await tx.query("UPDATE patents SET status = 'expired' WHERE expiry_game_day <= $1 AND status = 'active'", [day]);
    await tx.query("UPDATE technology_licenses SET status = 'expired' WHERE patent_id = ANY($1::text[]) AND status = 'active'", [expiredPatents.rows.map((p) => p.id)]);
    for (const patent of expiredPatents.rows) {
      await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'patent.expired','Patent entered public domain',$3) ON CONFLICT (id) DO NOTHING", [`PATENT-EXPIRED-${patent.id}`, day, toNanoMarkup({ patentId: patent.id, technologyId: patent.technology_id })]);
    }
  }
}

async function ensureMarketLiquidity(tx: PostgresRepository, day: number): Promise<void> {
  await tx.query("UPDATE market_prices SET supply = GREATEST(supply, 10), demand = GREATEST(demand, 10), game_day = $1 WHERE supply <= 1 OR demand <= 1", [day]);
}

async function settleProduction(tx: PostgresRepository, day: number): Promise<number> {
  const machines = await tx.query<{ id: string; owner_id: string; business_id: string | null; productive_capacity: string; utilization: string; condition: string; output_resource: string; input_resource: string; input_per_output: string; focus: string }>("SELECT machines.id, machines.owner_id, business_assets.business_id, machines.productive_capacity, machines.utilization, machines.condition, machines.output_resource, machines.input_resource, machines.input_per_output, COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC, started_game_day DESC LIMIT 1), 'efficiency') AS focus FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE machines.condition > 0 AND machines.utilization > 0");
  let events = 0;
  for (const machine of machines.rows) {
    const outputFactor = machine.focus === 'efficiency' ? 1.1 : machine.focus === 'cost' ? 1 : 0.9;
    const inputFactor = machine.focus === 'cost' ? 0.85 : 1;
    const theoretical = Math.max(0, Number(machine.productive_capacity) * Number(machine.utilization) / 100 * Math.min(1, Number(machine.condition) / 100) * 2 * outputFactor);
    const input = await tx.query<{ amount: string }>('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE', [machine.owner_id, machine.input_resource]);
    const available = Number(input.rows[0]?.amount ?? 0);
    const perOutput = Number(machine.input_per_output) * inputFactor;
    const output = Math.round(Math.min(theoretical, perOutput > 0 ? available / perOutput : theoretical) * 100) / 100;
    const consumed = Math.round(output * perOutput * 100) / 100;
    if (output <= 0 || consumed <= 0) continue;
    const price = await tx.query<{ price: string }>('SELECT price FROM market_prices WHERE product = $1', [machine.input_resource]);
    const inputCost = Math.round(consumed * Number(price.rows[0]?.price ?? 0) * 100) / 100;
    await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1', [consumed, machine.owner_id, machine.input_resource]);
    await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [machine.owner_id, machine.output_resource, output]);
    const eventId = crypto.randomUUID();
    await tx.query('INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [eventId, machine.id, machine.owner_id, machine.output_resource, output, day]);
    if (machine.business_id) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [inputCost, day, machine.business_id]);
    events += 1;
  }
  return events;
}

export async function advanceWorld(repository: PostgresRepository, minutesPerTick = 5, idempotencyKey?: string): Promise<{ day: number; minute: number; newDay: boolean; productionEvents: number; marketSettlements: number; alreadyProcessed?: boolean }> {
  validateWorldAdvanceMinutes(minutesPerTick);
  const result = await repository.transaction(async (tx) => {
    if (idempotencyKey) {
      const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [`SCHEDULED-TICK-${idempotencyKey}`]);
      if (prior.rows[0]) {
        const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
        return { day: Number(world.rows[0]?.game_day ?? 0), minute: Number(world.rows[0]?.game_minute ?? 0), newDay: false, productionEvents: 0, marketSettlements: 0, alreadyProcessed: true };
      }
    }
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const currentDay = Number(world.rows[0]?.game_day ?? 0);
    const currentMinute = Number(world.rows[0]?.game_minute ?? 0);
    const nextMinute = currentMinute + minutesPerTick;
    const newDay = nextMinute >= 1440;
    const day = currentDay + (newDay ? 1 : 0);
    const minute = nextMinute % 1440;
    await tx.query('UPDATE world_state SET game_day = $1, game_minute = $2 WHERE id = \'WORLD\'', [day, minute]);
    const expiringRoles = await tx.query<{ id: string; human_id: string; institution_id: string; role_id: string }>("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= $1 FOR UPDATE", [day]);
    await tx.query("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    for (const role of expiringRoles.rows) {
      await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'expired',$5,'term_completed') ON CONFLICT (human_id,role_id,action,game_day) DO NOTHING", [`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, role.institution_id, role.role_id, day]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'governance','Role term completed',$3,$4) ON CONFLICT DO NOTHING", [`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, `Your term for role ${role.role_id} has ended. You may claim an eligible role again when available.`, role.role_id]);
    }
    await tx.query("UPDATE authority_delegations SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    await tx.query("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND (closes_game_day, closes_game_minute) <= ($1, $2)", [day, minute]);
    await tx.query("UPDATE machines SET condition = GREATEST(0, condition - GREATEST(0.05, utilization * 0.005 * CASE COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC LIMIT 1), 'efficiency') WHEN 'durability' THEN 0.7 WHEN 'safety' THEN 0.8 ELSE 1 END)), maintenance_due = maintenance_due + GREATEST(1, utilization * 0.25)");
    await tx.query("UPDATE market_prices SET price = GREATEST(1, ROUND(price * (1 + LEAST(0.05, GREATEST(-0.05, (demand - supply) / GREATEST(1, supply + demand))))::numeric, 2)), game_day = $1", [day]);
    if (newDay) {
      await tx.query("UPDATE research_projects SET progress = LEAST(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'");
      await tx.query("UPDATE technologies SET progress = LEAST(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)");
      await tx.query("UPDATE cities SET housing_capacity = housing_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000), energy_capacity = energy_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000), connectivity_capacity = connectivity_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000), health_capacity = health_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000)");
      await tx.query('UPDATE budgets SET amount = GREATEST(0, amount - 100), game_day = $1 WHERE amount > 0', [day]);
      await tx.query("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active' AND $1 % 365 = 0", [day]);
      if (day % 365 === 0) await processMortality(tx, day);
      await settleBusinessDepreciation(tx, day);
      await settleBusinessTaxes(tx, day);
      await settleBasicLevy(tx, day);
      await processCityDynamics(tx, day);
      await processPatentExpirations(tx, day);
      await updateFinancialStates(tx, day);
      await dissolveInstitutions(tx, day);
      await snapshotRankings(tx, day);
    }
    await ensureMarketLiquidity(tx, day);
    await tx.query("UPDATE world_state SET living_cost_index = ROUND(GREATEST(0.5, LEAST(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50))::numeric, 3), essential_services_index = ROUND(GREATEST(0, LEAST(1, (SELECT COALESCE(MIN(LEAST(LEAST(1, housing_capacity / GREATEST(1, residents)), LEAST(1, energy_capacity / GREATEST(1, residents)), LEAST(1, connectivity_capacity / GREATEST(1, residents)), LEAST(1, health_capacity / 100.0))), 0) FROM cities)))::numeric, 3) WHERE id = 'WORLD'");
    await tx.query("UPDATE world_state SET health = CAST(GREATEST(0, LEAST(100, (SELECT COALESCE(AVG(condition), 68) FROM machines) * COALESCE(essential_services_index, 0.68))) AS INTEGER) WHERE id = 'WORLD'");
    await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'world_clock','A new game tick begins',$3) ON CONFLICT (id) DO NOTHING", [`CLOCK-${day}-${minute}`, day, toNanoMarkup({ newDay })]);
    const productionEvents = await settleProduction(tx, day);
    await settleTechnologyRoyalties(tx, day);
    await runAiMaintenance(tx, day);
    await completeContracts(tx, day);
    if (idempotencyKey) {
      await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'scheduled_tick','Scheduled world tick committed',$3) ON CONFLICT (id) DO NOTHING", [`SCHEDULED-TICK-${idempotencyKey}`, day, toNanoMarkup({ day, minute, newDay, productionEvents })]);
    }
    return { day, minute, newDay, productionEvents };
  });
  if (result.alreadyProcessed) return result;
  let marketSettlements = 0;
  for (const product of products) {
    const settled = await settleMarket(repository, product);
    if (settled.filled) marketSettlements += 1;
  }
  return { ...result, marketSettlements };
}
