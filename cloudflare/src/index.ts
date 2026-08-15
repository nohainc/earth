import { DurableObject } from 'cloudflare:workers';
import { probePostgres } from './postgres';
import { authorityMode, withPostgresRepository, withRepository } from './repository';
import { cancelMarketOrder as cancelMarketOrderPostgres, listMarketOrders as listMarketOrdersPostgres, settleMarket as settleMarketPostgres, submitMarketOrder as submitMarketOrderPostgres } from './market-postgres';
import { declarePersonalInsolvency as declarePersonalInsolvencyPostgres, publicSpending as publicSpendingPostgres, recoverInstitution as recoverInstitutionPostgres, settleTax as settleTaxPostgres } from './finance-postgres';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, liquidateExpiredEstates as liquidateExpiredEstatesPostgres, registerSuccessor as registerSuccessorPostgres, settleInheritance as settleInheritancePostgres } from './lifecycle-postgres';
import { acceptContract as acceptContractPostgres, cancelContract as cancelContractPostgres, createContract as createContractPostgres, openDispute as openDisputePostgres } from './contracts-postgres';
import { resolveContractDispute as resolveContractDisputePostgres } from './arbitration-postgres';
import { appointManager as appointManagerPostgres, createBusiness as createBusinessPostgres, issueShares as issueSharesPostgres, ownershipRegistry as ownershipRegistryPostgres, setPolicy as setBusinessPolicyPostgres, transferShares as transferSharesPostgres, updateConstitution as updateConstitutionPostgres } from './business-postgres';
import { acquireMachine as acquireMachinePostgres, maintainMachine as maintainMachinePostgres, sellMachine as sellMachinePostgres, setMachineUtilization as setMachineUtilizationPostgres, upgradeMachine as upgradeMachinePostgres } from './machines-postgres';
import { createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres, grantPatent as grantPatentPostgres, licenseTechnology as licenseTechnologyPostgres } from './technology-postgres';
import { castVote as castVotePostgres, createProposal as createProposalPostgres, executeProposal as executeProposalPostgres, resolveProposals as resolveProposalsPostgres } from './governance-postgres';
import { advanceWorld as advanceWorldPostgres } from './scheduler-postgres';
import { loginIdentity as loginIdentityPostgres, registerIdentity as registerIdentityPostgres } from './auth-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { listAssistants as listAssistantsPostgres, updateAssistantPolicy as updateAssistantPolicyPostgres, upgradeAssistant as upgradeAssistantPostgres } from './ai-postgres';
import { changeDelegation as changeDelegationPostgres, changeRole as changeRolePostgres, listRoles as listRolesPostgres } from './roles-postgres';
import { changeCommunityMembership as changeCommunityMembershipPostgres, contributeToCommunity as contributeToCommunityPostgres, createCommunity as createCommunityPostgres, listCommunities as listCommunitiesPostgres, listCommunityContributions as listCommunityContributionsPostgres, listCommunityMembers as listCommunityMembersPostgres } from './communities-postgres';
import { deliverOutbox } from './outbox-postgres';
import { changeCityResidency as changeCityResidencyPostgres, changeCorporationMembership as changeCorporationMembershipPostgres, cityQualification as cityQualificationPostgres, corporationQualification as corporationQualificationPostgres, contributeToCorporation as contributeToCorporationPostgres, createCity as createCityPostgres, createCorporation as createCorporationPostgres, listCities as listCitiesPostgres, listCorporations as listCorporationsPostgres, setCityBudget as setCityBudgetPostgres, spendCorporationTreasury as spendCorporationTreasuryPostgres } from './institutions-postgres';
import { auditWorld as auditWorldPostgres, listAuthorityEvents as listAuthorityEventsPostgres, listEvents as listEventsPostgres, listGovernanceProposals as listGovernanceProposalsPostgres, listGovernanceRules as listGovernanceRulesPostgres, listHistory as listHistoryPostgres, listInstitutions as listInstitutionsPostgres, listMembershipEvents as listMembershipEventsPostgres, listNotifications as listNotificationsPostgres, listOwnershipEvents as listOwnershipEventsPostgres, listRankings as listRankingsPostgres, listTechnology as listTechnologyPostgres, markNotificationRead as markNotificationReadPostgres, readBusiness as readBusinessPostgres } from './read-postgres';

const SESSION_DAYS = 7;
const WEB_ASSET_VERSION = '2026-08-15-auth-recovery-1';
const MACHINE_CATALOG: Record<string, { output: string; credit: number; material: number; capacity: number }> = {
  extractor: { output: 'material', credit: 4200, material: 80, capacity: 2 },
  'energy-array': { output: 'energy', credit: 3600, material: 60, capacity: 2 },
  'compute-node': { output: 'compute', credit: 5200, material: 100, capacity: 1.5 },
  fabricator: { output: 'components', credit: 4800, material: 90, capacity: 1.8 },
  'housing-fabricator': { output: 'components', credit: 5000, material: 110, capacity: 1.6 },
  'research-cluster': { output: 'compute', credit: 7000, material: 140, capacity: 1.2 },
};
const encoder = new TextEncoder();
const bytesToBase64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const base64ToBytes = (value: string) => Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const bytesToBase32 = (bytes: Uint8Array) => {
  let output = ''; let buffer = 0; let bits = 0;
  for (const byte of bytes) { buffer = (buffer << 8) | byte; bits += 8; while (bits >= 5) { output += base32Alphabet[(buffer >>> (bits - 5)) & 31]; bits -= 5; } }
  if (bits > 0) output += base32Alphabet[(buffer << (5 - bits)) & 31];
  return output;
};
const base32ToBytes = (value: string) => {
  let buffer = 0; let bits = 0; const output: number[] = [];
  for (const char of value.replace(/=+$/, '').toUpperCase()) { const index = base32Alphabet.indexOf(char); if (index < 0) continue; buffer = (buffer << 5) | index; bits += 5; if (bits >= 8) { output.push((buffer >>> (bits - 8)) & 255); bits -= 8; } }
  return new Uint8Array(output);
};
async function totp(secret: string, timestamp = Date.now()): Promise<string> {
  const counter = Math.floor(timestamp / 30000); const data = new ArrayBuffer(8); const view = new DataView(data); view.setUint32(4, counter);
  const key = await crypto.subtle.importKey('raw', base32ToBytes(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const hash = new Uint8Array(await crypto.subtle.sign('HMAC', key, data)); const offset = hash[hash.length - 1] & 15;
  const value = ((hash[offset] & 127) << 24) | (hash[offset + 1] << 16) | (hash[offset + 2] << 8) | hash[offset + 3];
  return String(value % 1000000).padStart(6, '0');
}
async function validTotp(secret: string, code: string): Promise<boolean> {
  if (!/^\d{6}$/.test(code)) return false;
  for (const drift of [-30000, 0, 30000]) if (code === await totp(secret, Date.now() + drift)) return true;
  return false;
}
async function votingWeight(env: Env, humanId: string, institutionId: string): Promise<number> {
  const institution = await env.DB.prepare('SELECT kind FROM institutions WHERE id = ?').bind(institutionId).first<{ kind: string }>();
  if (institution?.kind !== 'OUC') return 1;
  const delegated = await env.DB.prepare("SELECT delegator_id FROM authority_delegations WHERE institution_id = ? AND delegate_id = ? AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1").bind(institutionId, humanId).first<{ delegator_id: string }>();
  const representation = await env.DB.prepare('SELECT corporations.member_count, cities.residents FROM memberships LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = ?').bind(delegated?.delegator_id ?? humanId).first<{ member_count: number | null; residents: number | null }>();
  const population = Number(representation?.member_count ?? representation?.residents ?? 0);
  return Math.round((1 + Math.min(2, population / 100)) * 1000) / 1000;
}
async function resolveGovernanceProposals(env: Env): Promise<void> {
  await env.DB.prepare("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND closes_at <= CURRENT_TIMESTAMP").run();
  const open = await env.DB.prepare("SELECT id, institution_id, quorum, approval_threshold, implementation_delay_days FROM proposals WHERE status = 'closed' AND outcome = 'pending'").all<{ id: string; institution_id: string; quorum: number; approval_threshold: number; implementation_delay_days: number }>();
  for (const proposal of open.results) {
    const counts = await env.DB.prepare('SELECT choice, COALESCE(SUM(weight), 0) AS weight FROM ballots WHERE proposal_id = ? GROUP BY choice').bind(proposal.id).all<{ choice: string; weight: number }>();
    const totals = Object.fromEntries(counts.results.map((row) => [row.choice, Number(row.weight)]));
    const eligible = await env.DB.prepare("SELECT COUNT(*) AS count FROM humans WHERE life_status = 'active'").first<{ count: number }>();
    const representation = await env.DB.prepare("SELECT COALESCE(SUM(1 + CASE WHEN memberships.corporation_id IS NOT NULL THEN MIN(2, corporations.member_count / 100.0) WHEN memberships.city_id IS NOT NULL THEN MIN(2, cities.residents / 100.0) ELSE 0 END), 0) AS weight FROM humans LEFT JOIN memberships ON memberships.human_id = humans.id LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE humans.life_status = 'active'").first<{ weight: number }>();
    const eligibleWeight = Math.max(Number(eligible?.count ?? 0), Number(representation?.weight ?? 0));
    const cast = (totals.support ?? 0) + (totals.oppose ?? 0) + (totals.abstain ?? 0);
    const decisive = (totals.support ?? 0) + (totals.oppose ?? 0);
    const quorumMet = eligibleWeight > 0 && cast / eligibleWeight >= Number(proposal.quorum);
    const passed = quorumMet && decisive > 0 && (totals.support ?? 0) / decisive >= Number(proposal.approval_threshold);
    const outcome = !quorumMet ? 'no_quorum' : passed ? 'passed' : 'rejected';
    const implementationAt = passed ? `+${Math.max(0, Number(proposal.implementation_delay_days))} days` : null;
    await env.DB.prepare("UPDATE proposals SET outcome = ?, resolved_at = CURRENT_TIMESTAMP, implementation_at = CASE WHEN ? = 'passed' THEN datetime(CURRENT_TIMESTAMP, ?) ELSE NULL END WHERE id = ?").bind(outcome, outcome, implementationAt ?? '+0 days', proposal.id).run();
  }
}
async function hasActiveRole(env: Env, humanId: string, roleIds: string[]): Promise<boolean> {
  if (!roleIds.length) return false;
  const placeholders = roleIds.map(() => '?').join(',');
  const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
  const row = await env.DB.prepare(`SELECT id FROM role_assignments WHERE (human_id = ? OR role_id IN (SELECT role_id FROM authority_delegations WHERE delegate_id = ? AND status = 'active' AND ends_game_day > ?)) AND status = 'active' AND ends_game_day > ? AND role_id IN (${placeholders}) LIMIT 1`).bind(humanId, humanId, day, day, ...roleIds).first();
  return Boolean(row);
}
async function eligibleForInstitution(env: Env, humanId: string, institutionId: string): Promise<boolean> {
  const world = await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>();
  const human = await env.DB.prepare('SELECT political_eligibility_game_day FROM humans WHERE id = ?').bind(humanId).first<{ political_eligibility_game_day: number }>();
  if (Number(world?.game_day ?? 0) < Number(human?.political_eligibility_game_day ?? 0)) return false;
  const institution = await env.DB.prepare('SELECT kind FROM institutions WHERE id = ?').bind(institutionId).first<{ kind: string }>();
  if (!institution) return false;
  if (institution.kind === 'OUC') return Boolean(await env.DB.prepare("SELECT id FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = ? AND status = 'active' UNION ALL SELECT id FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = ? AND status = 'active' LIMIT 1").bind(humanId, humanId).first());
  if (institution.kind === 'CORPORATION') return Boolean(await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND corporation_id = ?').bind(humanId, institutionId).first());
  if (institution.kind === 'CITY') return Boolean(await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND city_id = ?').bind(humanId, institutionId).first());
  return false;
}
async function canExerciseDelegatedRole(env: Env, humanId: string, institutionId: string): Promise<boolean> {
  return Boolean(await env.DB.prepare("SELECT id FROM authority_delegations WHERE institution_id = ? AND delegate_id = ? AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1").bind(institutionId, humanId).first()) || await eligibleForInstitution(env, humanId, institutionId);
}
async function marketFeeRate(env: Env): Promise<number> {
  const rule = await env.DB.prepare("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string }>();
  if (!rule?.value_json) return 0;
  try {
    const value = JSON.parse(rule.value_json) as { feeRate?: number };
    return typeof value.feeRate === 'number' && value.feeRate >= 0 && value.feeRate <= 0.05 ? value.feeRate : 0;
  } catch (_error) { return 0; }
}
async function marketFairAllocation(env: Env): Promise<boolean> {
  const rule = await env.DB.prepare("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string }>();
  if (!rule?.value_json) return true;
  try {
    const value = JSON.parse(rule.value_json) as { fairAllocation?: boolean };
    return value.fairAllocation !== false;
  } catch (_error) { return true; }
}
async function settleMachineProduction(env: Env, gameDay: number): Promise<void> {
  const producers = await env.DB.prepare("SELECT machines.id, machines.owner_id, business_assets.business_id, machines.productive_capacity, machines.utilization, machines.condition, machines.output_resource, machines.input_resource, machines.input_per_output, COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC, started_game_day DESC LIMIT 1), 'efficiency') AS research_focus FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE machines.condition > 0 AND machines.utilization > 0").all<{ id: string; owner_id: string; business_id?: string; productive_capacity: number; utilization: number; condition: number; output_resource: string; input_resource: string; input_per_output: number; research_focus: string }>();
  for (const machine of producers.results) {
    const focus = String(machine.research_focus);
    const outputFactor = focus === 'efficiency' ? 1.1 : focus === 'cost' ? 1 : 0.9;
    const inputFactor = focus === 'cost' ? 0.85 : 1;
    const theoreticalOutput = Math.max(0, Number(machine.productive_capacity) * Number(machine.utilization) / 100 * Math.min(1, Number(machine.condition) / 100) * 2 * outputFactor);
    const inputBalance = await env.DB.prepare('SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = ?').bind(machine.owner_id, machine.input_resource).first<{ amount: number }>();
    const availableInput = Number(inputBalance?.amount ?? 0);
    const effectiveInputPerOutput = Number(machine.input_per_output) * inputFactor;
    const output = Math.round(Math.min(theoreticalOutput, effectiveInputPerOutput > 0 ? availableInput / effectiveInputPerOutput : theoreticalOutput) * 100) / 100;
    const consumedInput = Math.round(output * effectiveInputPerOutput * 100) / 100;
    const inputMarket = await env.DB.prepare('SELECT price FROM market_prices WHERE product = ?').bind(machine.input_resource).first<{ price: number }>();
    const inputCostCredits = Math.round(consumedInput * Number(inputMarket?.price ?? 0) * 100) / 100;
    if (output <= 0 || consumedInput <= 0) continue;
    const eventId = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare('UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = ? AND amount >= ?').bind(consumedInput, machine.owner_id, machine.input_resource, consumedInput),
      env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(machine.owner_id, machine.output_resource, output),
      env.DB.prepare('INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(eventId, machine.id, machine.owner_id, machine.output_resource, output, gameDay),
      ...(machine.business_id ? [env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?").bind(inputCostCredits, inputCostCredits, gameDay, machine.business_id)] : []),
      env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), machine.owner_id, 'production', 'Production completed', `${output} ${machine.output_resource} produced by ${machine.id}.`, machine.id),
      env.DB.prepare('UPDATE businesses SET condition = MAX(0, condition - ?) WHERE owner_id = ?').bind(Math.min(2, output * 0.05), machine.owner_id),
    ]);
    await env.MARKET_COORDINATOR.getByName('events-global').broadcast({ type: 'world_activity', gameDay, category: 'production' });
  }
}

async function settleBasicLevies(env: Env, gameDay: number): Promise<void> {
  const [rule, financeRule, world, humans] = await Promise.all([
    env.DB.prepare("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = 1").first<{ rate: number; version: number }>(),
    env.DB.prepare("SELECT value_json, version FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'finance' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string; version: number }>(),
    env.DB.prepare("SELECT living_cost_index FROM world_state WHERE id = 'WORLD'").first<{ living_cost_index: number }>(),
    env.DB.prepare("SELECT humans.id, account_balances.account_id, account_balances.balance FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'active'").all<{ id: string; account_id: string; balance: number }>(),
  ]);
  if (!rule) return;
  let effectiveRate = Number(rule.rate);
  let effectiveVersion = Number(rule.version);
  if (financeRule?.value_json) {
    try {
      const configured = JSON.parse(financeRule.value_json) as { rate?: number };
      if (typeof configured.rate === 'number' && configured.rate >= 0 && configured.rate <= 0.25) {
        effectiveRate = configured.rate;
        effectiveVersion = Number(financeRule.version);
      }
    } catch (_error) { /* retain the safe legacy rate */ }
  }
  const levy = Math.round(Math.max(1, 10 * Math.max(0.5, Number(world?.living_cost_index ?? 1)) * effectiveRate) * 100) / 100;
  for (const human of humans.results) {
    const correlationId = `BASIC-LEVY-${human.id}-${gameDay}-v${effectiveVersion}`;
    const existing = await env.DB.prepare("SELECT id FROM ledger_entries WHERE reason_type = 'basic_levy' AND correlation_id = ?").bind(correlationId).first();
    if (existing || Number(human.balance) < levy) continue;
    await env.DB.batch([
      env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(levy, human.account_id, levy),
      env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(levy, 'account-ouc-treasury'),
      env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), gameDay, human.account_id, 'account-ouc-treasury', levy, 'CREDIT', 'basic_levy', human.id, `tax-v${effectiveVersion}`, correlationId),
      env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`LEVY-${human.id}-${gameDay}`, human.id, 'finance', 'OUC Basic Levy settled', `${levy} Credits were settled for the indexed OUC Basic Levy at living-cost index ${Number(world?.living_cost_index ?? 1).toFixed(2)} (finance rule v${effectiveVersion}).`, correlationId),
    ]);
  }
}
async function settleBusinessTaxes(env: Env, gameDay: number): Promise<void> {
  const rule = await env.DB.prepare("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BUSINESS' AND active = 1").first<{ rate: number; version: number }>();
  if (!rule) return;
  const taxRate = Math.min(0.25, Math.max(0, Number(rule.rate)));
  const businesses = await env.DB.prepare("SELECT businesses.id, businesses.owner_id, business_financials.revenue, business_financials.taxed_revenue, account_balances.account_id, account_balances.balance FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id JOIN account_balances ON account_balances.owner_id = businesses.owner_id AND account_balances.currency = 'CREDIT' WHERE businesses.status = 'active'").all<{ id: string; owner_id: string; revenue: number; taxed_revenue: number; account_id: string; balance: number }>();
  for (const business of businesses.results) {
    const accrued = Math.max(0, Number(business.revenue) - Number(business.taxed_revenue));
    const tax = Math.round(accrued * taxRate * 100) / 100;
    if (tax <= 0) {
      await env.DB.prepare('UPDATE business_financials SET taxed_revenue = MAX(taxed_revenue, revenue), last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?').bind(gameDay, business.id).run();
      continue;
    }
    if (Number(business.balance) < tax) continue;
    const correlationId = `BUSINESS-TAX-${business.id}-${gameDay}-v${Number(rule.version)}`;
    const existing = await env.DB.prepare("SELECT id FROM ledger_entries WHERE reason_type = 'business_tax' AND correlation_id = ?").bind(correlationId).first();
    if (existing) continue;
    await env.DB.batch([
      env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(tax, business.account_id, tax),
      env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(tax),
      env.DB.prepare('UPDATE business_financials SET taxed_revenue = revenue, operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?').bind(tax, tax, gameDay, business.id),
      env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), gameDay, business.account_id, 'account-ouc-treasury', tax, 'CREDIT', 'business_tax', business.id, `business-tax-v${Number(rule.version)}`, correlationId),
      env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`BUSINESS-TAX-${business.id}-${gameDay}`, business.owner_id, 'finance', 'Business tax settled', `${tax} Credits were settled for ${business.id} on accrued business revenue.`, business.id),
    ]);
  }
}
async function runAiMaintenance(env: Env, gameDay: number): Promise<void> {
  const assistants = await env.DB.prepare("SELECT ai_assistants.owner_id, machines.id AS machine_id, business_assets.business_id FROM ai_assistants JOIN machines ON machines.owner_id = ai_assistants.owner_id LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE ai_assistants.enabled = 1 AND ai_assistants.policy = 'maintenance' AND machines.maintenance_due > 0 AND machines.condition < 100").all<{ owner_id: string; machine_id: string; business_id?: string }>();
  for (const assistant of assistants.results) {
    const components = await env.DB.prepare("SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = 'components'").bind(assistant.owner_id).first<{ amount: number }>();
    const amount = Math.min(5, Number(components?.amount ?? 0));
    if (amount <= 0) continue;
    const componentPrice = await env.DB.prepare("SELECT price FROM market_prices WHERE product = 'components'").first<{ price: number }>();
    const maintenanceCost = Math.round(amount * Number(componentPrice?.price ?? 0) * 100) / 100;
    await env.DB.batch([
      env.DB.prepare("UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = 'components' AND amount >= ?").bind(amount, assistant.owner_id, amount),
      env.DB.prepare('UPDATE machines SET condition = MIN(100, condition + ? * 0.8), maintenance_due = MAX(0, maintenance_due - ?) WHERE id = ? AND owner_id = ?').bind(amount, amount, assistant.machine_id, assistant.owner_id),
      env.DB.prepare('INSERT INTO maintenance_events (id, machine_id, owner_id, resource, amount, condition_before, condition_after, game_day) SELECT ?, id, owner_id, \'components\', ?, condition, MIN(100, condition + ? * 0.8), ? FROM machines WHERE id = ?').bind(crypto.randomUUID(), amount, amount, gameDay, assistant.machine_id),
      ...(assistant.business_id ? [env.DB.prepare('UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?').bind(maintenanceCost, maintenanceCost, gameDay, assistant.business_id)] : []),
    ]);
  }
}
async function settleBusinessDepreciation(env: Env, gameDay: number): Promise<void> {
  const assets = await env.DB.prepare("SELECT business_assets.business_id, business_assets.machine_id, COALESCE(machine_acquisitions.credit_cost, 0) AS book_value FROM business_assets LEFT JOIN machine_acquisitions ON machine_acquisitions.machine_id = business_assets.machine_id").all<{ business_id: string; machine_id: string; book_value: number }>();
  for (const asset of assets.results) {
    const amount = Math.round(Math.max(0, Number(asset.book_value) * 0.001) * 100) / 100;
    if (amount <= 0) continue;
    const correlationId = `DEPRECIATION-${asset.machine_id}-${gameDay}`;
    const existing = await env.DB.prepare("SELECT id FROM ledger_entries WHERE reason_type = 'business_depreciation' AND correlation_id = ?").bind(correlationId).first();
    if (existing) continue;
    await env.DB.batch([
      env.DB.prepare('UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?').bind(amount, amount, gameDay, asset.business_id),
      env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), gameDay, `business-${asset.business_id}`, 'account-depreciation-expense', amount, 'CREDIT', 'business_depreciation', asset.machine_id, 'business-finance-v1', correlationId),
    ]);
  }
}
async function completeNegotiatedContracts(env: Env, gameDay: number): Promise<void> {
  const due = await env.DB.prepare("SELECT id, proposer_id, counterparty_id, title FROM negotiated_contracts WHERE status = 'accepted' AND ends_game_day <= ?").bind(gameDay).all<{ id: string; proposer_id: string; counterparty_id: string; title: string }>();
  if (!due.results.length) return;
  await env.DB.batch(due.results.flatMap((contract) => [
    env.DB.prepare("UPDATE negotiated_contracts SET status = 'completed' WHERE id = ? AND status = 'accepted'").bind(contract.id),
    env.DB.prepare('INSERT OR IGNORE INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`CONTRACT-COMPLETED-${contract.id}`, gameDay, 'contract.completed', 'A negotiated contract completed', JSON.stringify({ contractId: contract.id })),
    env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)').bind(`CONTRACT-COMPLETE-${contract.id}-${contract.proposer_id}`, contract.proposer_id, 'contract', 'Contract completed', `${contract.title} completed on game day ${gameDay}.`, contract.id, `CONTRACT-COMPLETE-${contract.id}-${contract.counterparty_id}`, contract.counterparty_id, 'contract', 'Contract completed', `${contract.title} completed on game day ${gameDay}.`, contract.id),
  ]));
}
async function assessInstitutionFinances(env: Env, gameDay: number): Promise<void> {
  const [businessRows, cityRows, corporationRows] = await Promise.all([
    env.DB.prepare('SELECT id, condition, status FROM businesses').all<{ id: string; condition: number; status: string }>(),
    env.DB.prepare('SELECT id, treasury FROM cities').all<{ id: string; treasury: number }>(),
    env.DB.prepare('SELECT id, treasury FROM corporations').all<{ id: string; treasury: number }>(),
  ]);
  const candidates = [
    ...businessRows.results.map((row) => ({ id: row.id, kind: 'BUSINESS', current: row.status, distressed: Number(row.condition) <= 20, bankrupt: Number(row.condition) <= 0 })),
    ...cityRows.results.map((row) => ({ id: row.id, kind: 'CITY', current: 'active', distressed: Number(row.treasury) <= 0, bankrupt: Number(row.treasury) < -1000 })),
    ...corporationRows.results.map((row) => ({ id: row.id, kind: 'CORPORATION', current: 'active', distressed: Number(row.treasury) <= 0, bankrupt: Number(row.treasury) < -1000 })),
  ];
  for (const candidate of candidates) {
    const existing = await env.DB.prepare('SELECT status, since_game_day FROM financial_states WHERE institution_id = ?').bind(candidate.id).first<{ status: string; since_game_day: number }>();
    if (existing?.status === 'dissolved') continue;
    const current = existing?.status ?? candidate.current;
    if (existing?.status === 'insolvent' && gameDay - Number(existing.since_game_day) >= 30 && (candidate.kind === 'CORPORATION' || candidate.kind === 'CITY')) {
      const members = await env.DB.prepare('SELECT human_id FROM memberships WHERE corporation_id = ? OR city_id = ?').bind(candidate.kind === 'CORPORATION' ? candidate.id : '', candidate.kind === 'CITY' ? candidate.id : '').all<{ human_id: string }>();
      await env.DB.batch([
        env.DB.prepare("UPDATE financial_states SET status = 'dissolved', recovery_game_day = ?, last_reason = 'Institution remained insolvent beyond the engine resolution window', updated_at = CURRENT_TIMESTAMP WHERE institution_id = ?").bind(gameDay, candidate.id),
        env.DB.prepare("UPDATE institutions SET status = 'dissolved' WHERE id = ?").bind(candidate.id),
        ...(candidate.kind === 'CORPORATION' ? [env.DB.prepare('UPDATE memberships SET corporation_id = NULL WHERE corporation_id = ?').bind(candidate.id)] : [env.DB.prepare('UPDATE memberships SET city_id = NULL WHERE city_id = ?').bind(candidate.id)]),
        env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), candidate.id, candidate.kind, 'insolvent', 'dissolved', gameDay, 'Institution remained insolvent beyond the engine resolution window'),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`DISSOLVE-${candidate.id}-${gameDay}`, gameDay, 'institution.dissolved', `${candidate.kind} ${candidate.id} was dissolved`, JSON.stringify({ institutionId: candidate.id, releasedMembers: members.results.length })),
        ...members.results.map((member) => env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), member.human_id, 'institution', `${candidate.kind} dissolved`, `${candidate.kind} ${candidate.id} was dissolved after prolonged insolvency. Your institutional membership was released.`, candidate.id)),
      ]);
      continue;
    }
    const baseTarget = candidate.bankrupt ? 'bankrupt' : candidate.distressed ? 'distressed' : 'active';
    const target = baseTarget === 'distressed' && current === 'distressed' && gameDay - Number(existing?.since_game_day ?? gameDay) >= 7 ? 'insolvent' : baseTarget;
    if (target === current) continue;
    const reason = target === 'active' ? 'Positive operating position restored' : candidate.bankrupt ? 'Capital or productive capacity exhausted' : 'Operating reserve is depleted';
    await env.DB.batch([
      env.DB.prepare('INSERT INTO financial_states (institution_id, institution_kind, status, since_game_day, recovery_game_day, last_reason) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(institution_id) DO UPDATE SET status = excluded.status, since_game_day = excluded.since_game_day, recovery_game_day = excluded.recovery_game_day, last_reason = excluded.last_reason, updated_at = CURRENT_TIMESTAMP').bind(candidate.id, candidate.kind, target, existing?.since_game_day ?? gameDay, target === 'active' ? gameDay : null, reason),
      env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), candidate.id, candidate.kind, current, target, gameDay, reason),
      ...(candidate.kind === 'BUSINESS' ? [env.DB.prepare('UPDATE businesses SET status = ? WHERE id = ?').bind(target === 'bankrupt' ? 'bankrupt' : target === 'distressed' || target === 'insolvent' ? 'distressed' : 'active', candidate.id)] : []),
      env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`FIN-${candidate.id}-${gameDay}-${target}`, gameDay, 'financial_event', `${candidate.kind} ${candidate.id} is ${target}`, JSON.stringify({ institutionId: candidate.id, from: current, to: target })),
    ]);
  }
}
async function derivePassword(password: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256);
  return bytesToBase64(new Uint8Array(bits));
}
async function digest(value: string): Promise<string> {
  return bytesToBase64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))));
}
function cookieValue(request: Request, name: string): string | null {
  const cookies = request.headers.get('Cookie')?.split(';').map((part) => part.trim()) ?? [];
  const value = cookies.find((part) => part.startsWith(`${name}=`));
  return value ? decodeURIComponent(value.slice(name.length + 1)) : null;
}
async function currentHuman(request: Request, env: Env, allowEstate = false): Promise<{ id: string; display_name: string; email: string; life_status: string } | null> {
  const token = cookieValue(request, 'earth_session');
  if (!token) return null;
  const tokenHash = await digest(token);
  if (authorityMode(env) === 'postgres') {
    const result = await withRepository(env, (repository) => repository.query<{ id: string; display_name: string; life_status: string; email: string }>("SELECT humans.id, humans.display_name, humans.life_status, auth_credentials.email FROM auth_sessions JOIN humans ON humans.id = auth_sessions.human_id JOIN auth_credentials ON auth_credentials.human_id = humans.id WHERE auth_sessions.token_hash = $1 AND auth_sessions.revoked_at IS NULL AND auth_sessions.expires_at > CURRENT_TIMESTAMP AND (humans.life_status = 'active' OR ($2 = 1 AND humans.life_status = 'estate'))", [tokenHash, allowEstate ? 1 : 0]));
    return result?.rows[0] ?? null;
  }
  return env.DB.prepare("SELECT humans.id, humans.display_name, humans.life_status, auth_credentials.email, auth_credentials.email_verified_at FROM auth_sessions JOIN humans ON humans.id = auth_sessions.human_id JOIN auth_credentials ON auth_credentials.human_id = humans.id WHERE auth_sessions.token_hash = ? AND auth_sessions.revoked_at IS NULL AND auth_sessions.expires_at > CURRENT_TIMESTAMP AND (humans.life_status = 'active' OR (? = 1 AND humans.life_status = 'estate'))").bind(tokenHash, allowEstate ? 1 : 0).first();
}
async function sensitiveActionAllowed(env: Env, humanId: string, otp?: string): Promise<boolean> {
  if (authorityMode(env) === 'postgres') {
    const result = await withRepository(env, (repository) => repository.query<{ mfa_enabled: boolean; mfa_secret: string | null }>('SELECT mfa_enabled, mfa_secret FROM auth_credentials WHERE human_id = $1', [humanId]));
    const credential = result?.rows[0];
    return !credential?.mfa_enabled || Boolean(credential.mfa_secret && await validTotp(credential.mfa_secret, otp ?? ''));
  }
  const credential = await env.DB.prepare('SELECT mfa_enabled, mfa_secret FROM auth_credentials WHERE human_id = ?').bind(humanId).first<{ mfa_enabled: number; mfa_secret: string | null }>();
  return !credential?.mfa_enabled || Boolean(credential.mfa_secret && await validTotp(credential.mfa_secret, otp ?? ''));
}
function sessionCookie(token: string, maxAge: number): string {
  return `earth_session=${encodeURIComponent(token)}; Max-Age=${maxAge}; Path=/; HttpOnly; Secure; SameSite=Lax`;
}
async function issueActionToken(env: Env, humanId: string, action: 'verify_email' | 'reset_password', email: string): Promise<void> {
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await digest(token);
  const id = crypto.randomUUID();
  const expires = new Date(Date.now() + (action === 'verify_email' ? 24 : 1) * 3600000).toISOString();
  if (authorityMode(env) === 'postgres') {
    const result = await withRepository(env, (repository) => repository.query('INSERT INTO auth_action_tokens (id, human_id, token_hash, action, expires_at) VALUES ($1,$2,$3,$4,$5)', [id, humanId, tokenHash, action, expires]));
    if (!result) throw new Error('PostgreSQL authentication repository is unavailable');
  } else {
    await env.DB.prepare('INSERT INTO auth_action_tokens (id, human_id, token_hash, action, expires_at) VALUES (?, ?, ?, ?, ?)').bind(id, humanId, tokenHash, action, expires).run();
  }
  if (!env.EMAIL || !env.EMAIL_FROM) {
    throw new Error('Transactional email is not configured');
  }
  const path = action === 'verify_email' ? '/api/auth/verify-email' : '/api/auth/reset-password';
  const subject = action === 'verify_email' ? 'Verify your EARTH identity' : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}?token=${encodeURIComponent(token)}\n\nThis link expires soon and can only be used once.`;
  try {
    const delivery = await env.EMAIL.send({ to: email, from: { email: env.EMAIL_FROM, name: 'EARTH Identity' }, replyTo: env.EMAIL_REPLY_TO, subject, text, html: `<p>${subject}</p><p><a href="https://earthuc.com${path}?token=${encodeURIComponent(token)}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>` });
    console.info(JSON.stringify({ event: 'transactional_email_accepted', action, messageId: delivery?.messageId ?? null }));
  } catch (error) {
    const details = error && typeof error === 'object' ? error as { code?: unknown; message?: unknown } : {};
    console.error(JSON.stringify({ event: 'transactional_email_failed', action, code: String(details.code ?? 'unknown'), message: String(details.message ?? 'unknown') }));
    // Do not let a failed delivery consume the resend throttle window.
    if (authorityMode(env) === 'postgres') {
      await withRepository(env, (repository) => repository.query('DELETE FROM auth_action_tokens WHERE id = $1', [id]));
    }
    throw error;
  }
}

export class MarketCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      await ctx.storage.put('initialized', true);
    });
  }

  async submitCommand(payload: unknown): Promise<{ ok: true; coordinator: string }> {
    await this.ctx.storage.put('lastCommand', { payload, at: new Date().toISOString() });
    return { ok: true, coordinator: 'market' };
  }

  async snapshot(): Promise<unknown> {
    return this.ctx.storage.get('lastCommand');
  }

  async broadcast(event: Record<string, unknown>): Promise<void> {
    const message = JSON.stringify(event);
    for (const socket of this.ctx.getWebSockets()) {
      try { socket.send(message); } catch { socket.close(1011, 'Live channel unavailable'); }
    }
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('WebSocket upgrade required', { status: 426 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.send(JSON.stringify({ type: 'ready', channel: 'earth-world', coordinator: 'market' }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const text = typeof message === 'string' ? message : new TextDecoder().decode(message);
    if (text === 'ping') {
      socket.send(JSON.stringify({ type: 'pong', at: new Date().toISOString() }));
      return;
    }
    socket.send(JSON.stringify({ type: 'snapshot', data: await this.snapshot() }));
  }

  async webSocketClose(socket: WebSocket, code: number, reason: string): Promise<void> {
    socket.close(code, reason);
  }
}

async function advanceWorldFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  try {
    const result = await withRepository(env, async (repository) => {
      const authority = await repository.query("SELECT 1 FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') UNION ALL SELECT 1 FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [viewer.id]);
      if (!authority.rows[0]) throw new Error('Only an active OUC Delegate may advance the simulation clock manually');
      await resolveProposalsPostgres(repository);
      return advanceWorldPostgres(repository, 1440);
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    const state = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewer.id));
    return Response.json({ ok: true, result, state, persistence: 'planetscale-postgres' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to advance the simulation clock';
    return Response.json({ ok: false, error: message }, { status: /delegate/i.test(message) ? 403 : 409 });
  }
}

async function productionEventsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
  const result = await withRepository(env, (repository) => repository.query('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = $1 ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT $2', [viewer.id, limit]));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ events: result.rows, persistence: 'planetscale-postgres' });
}

async function servicesStatusFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const city = (await withRepository(env, (repository) => repository.query<Record<string, number>>('SELECT cities.* FROM cities JOIN memberships ON memberships.city_id = cities.id WHERE memberships.human_id = $1', [viewer.id])))?.rows[0];
  const independentBaseline = { housing: 0.75, utilities: 0.75, connectivity: 0.75, health: 0.5 };
  const ratios = city ? { housing: Math.min(1, Number(city.housing_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), utilities: Math.min(1, Number(city.energy_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), connectivity: Math.min(1, Number(city.connectivity_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), health: Math.min(1, Number(city.health_capacity ?? 0) / 100) } : independentBaseline;
  const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
  return Response.json({ cityId: city?.id ?? null, provider: city ? 'city-capacity' : 'ouc-independent-minimum', ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)), persistence: 'planetscale-postgres' });
}

async function worldActivityFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, async (repository) => {
    const [world, technology] = await Promise.all([
      repository.query('SELECT game_day, market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
      repository.query('SELECT progress FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewer.id]),
    ]);
    return { activity: [{ type: 'world_clock', day: world.rows[0]?.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: world.rows[0]?.market_batch_seconds ?? 498 }] };
  });
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function eventsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function notificationsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function markNotificationReadFromPostgres(request: Request, env: Env, notificationId: string): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => markNotificationReadPostgres(repository, viewer.id, notificationId));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function auditFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => auditWorldPostgres(repository, viewer.id));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function institutionsFromPostgres(request: Request, env: Env): Promise<Response> {
  const result = await withRepository(env, (repository) => listInstitutionsPostgres(repository));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function rankingsFromPostgres(request: Request, env: Env): Promise<Response> {
  const result = await withRepository(env, (repository) => listRankingsPostgres(repository));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function historyFromPostgres(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listHistoryPostgres(repository, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function ownershipHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listOwnershipEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function membershipHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listMembershipEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function authorityHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listAuthorityEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/api/day/advance' && request.method === 'POST') return advanceWorldFromPostgres(request, env);
    if (url.pathname === '/api/production/events' && request.method === 'GET') return productionEventsFromPostgres(request, env);
    if (url.pathname === '/api/services/status' && request.method === 'GET') return servicesStatusFromPostgres(request, env);
    if (url.pathname === '/api/world/activity' && request.method === 'GET') return worldActivityFromPostgres(request, env);
    if (url.pathname === '/api/events' && request.method === 'GET') return eventsFromPostgres(request, env);
    if (url.pathname === '/api/notifications' && request.method === 'GET') return notificationsFromPostgres(request, env);
    if (url.pathname === '/api/audit' && request.method === 'GET') return auditFromPostgres(request, env);
    const notificationReadRoute = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
    if (notificationReadRoute && request.method === 'POST') return markNotificationReadFromPostgres(request, env, notificationReadRoute[1]);
    if (url.pathname === '/api/world/audit' && request.method === 'GET') return auditFromPostgres(request, env);
    if (url.pathname === '/api/institutions' && request.method === 'GET') return institutionsFromPostgres(request, env);
    if (url.pathname === '/api/rankings' && request.method === 'GET') return rankingsFromPostgres(request, env);
    if (url.pathname === '/api/history' && request.method === 'GET') return historyFromPostgres(request, env);
    if (url.pathname === '/api/ownership/events' && request.method === 'GET') return ownershipHistoryFromPostgres(request, env);
    if (url.pathname === '/api/membership/events' && request.method === 'GET') return membershipHistoryFromPostgres(request, env);
    if (url.pathname === '/api/governance/authority/events' && request.method === 'GET') return authorityHistoryFromPostgres(request, env);
    if (url.pathname === '/api/auth/me' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      return Response.json({ authenticated: Boolean(human), human, persistence: authorityMode(env) === 'postgres' ? 'planetscale-postgres' : 'cloudflare-d1' });
    }
    if (url.pathname === '/api/auth/mfa/enroll' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const secret = bytesToBase32(crypto.getRandomValues(new Uint8Array(20)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_secret = $1, mfa_enabled = false WHERE human_id = $2', [secret, human.id]));
        if (result) return Response.json({ ok: true, secret, otpauth: `otpauth://totp/EARTH:${encodeURIComponent(human.email)}?secret=${secret}&issuer=EARTH`, message: 'Scan or enter this secret in an authenticator, then confirm with a six-digit code.' });
      }
      await env.DB.prepare('UPDATE auth_credentials SET mfa_secret = ?, mfa_enabled = 0 WHERE human_id = ?').bind(secret, human.id).run();
      return Response.json({ ok: true, secret, otpauth: `otpauth://totp/EARTH:${encodeURIComponent(human.email)}?secret=${secret}&issuer=EARTH`, message: 'Scan or enter this secret in an authenticator, then confirm with a six-digit code.' });
    }
    if (url.pathname === '/api/auth/mfa/confirm' && request.method === 'POST') {
      const human = await currentHuman(request, env); if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ code?: string }>(); const credential = authorityMode(env) === 'postgres' ? null : await env.DB.prepare('SELECT mfa_secret FROM auth_credentials WHERE human_id = ?').bind(human.id).first<{ mfa_secret: string | null }>();
      if (authorityMode(env) === 'postgres') {
        const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null }>('SELECT mfa_secret FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
        if (!credential?.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
        const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = true WHERE human_id = $1', [human.id]));
        if (result) return Response.json({ ok: true, enabled: true });
      }
      if (!credential?.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
      await env.DB.prepare('UPDATE auth_credentials SET mfa_enabled = 1 WHERE human_id = ?').bind(human.id).run();
      return Response.json({ ok: true, enabled: true });
    }
    if (url.pathname === '/api/auth/mfa/disable' && request.method === 'POST') {
      const human = await currentHuman(request, env); if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ code?: string }>(); const credential = authorityMode(env) === 'postgres' ? null : await env.DB.prepare('SELECT mfa_secret, mfa_enabled FROM auth_credentials WHERE human_id = ?').bind(human.id).first<{ mfa_secret: string | null; mfa_enabled: number }>();
      if (authorityMode(env) === 'postgres') {
        const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null; mfa_enabled: boolean }>('SELECT mfa_secret, mfa_enabled FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
        if (!credential?.mfa_enabled || !credential.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
        const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = false, mfa_secret = NULL WHERE human_id = $1', [human.id]));
        if (result) return Response.json({ ok: true, enabled: false });
      }
      if (!credential?.mfa_enabled || !credential.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
      await env.DB.prepare('UPDATE auth_credentials SET mfa_enabled = 0, mfa_secret = NULL WHERE human_id = ?').bind(human.id).run();
      return Response.json({ ok: true, enabled: false });
    }
    if (url.pathname === '/api/auth/sessions' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const token = cookieValue(request, 'earth_session');
      const currentHash = token ? await digest(token) : '';
      if (authorityMode(env) === 'postgres') {
        const sessions = await withRepository(env, (repository) => repository.query('SELECT id, created_at, expires_at, revoked_at, token_hash FROM auth_sessions WHERE human_id = $1 ORDER BY created_at DESC', [human.id]));
        if (sessions) return Response.json({ sessions: sessions.rows.map(({ token_hash: _tokenHash, ...session }) => ({ ...session, current: _tokenHash === currentHash })), persistence: 'planetscale-postgres' });
      }
      const sessions = await env.DB.prepare('SELECT id, created_at, expires_at, revoked_at, token_hash FROM auth_sessions WHERE human_id = ? ORDER BY created_at DESC').bind(human.id).all();
      return Response.json({ sessions: (sessions.results as Array<Record<string, unknown>>).map(({ token_hash, ...session }) => ({ ...session, current: token_hash === currentHash })), persistence: 'cloudflare-d1' });
    }
    const revokeSessionMatch = url.pathname.match(/^\/api\/auth\/sessions\/([^/]+)$/);
    if (revokeSessionMatch && request.method === 'DELETE') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND human_id = $2 AND revoked_at IS NULL', [revokeSessionMatch[1], human.id]));
        if (result) return Response.json({ ok: result.rowCount === 1, persistence: 'planetscale-postgres' });
      }
      const result = await env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = ? AND human_id = ? AND revoked_at IS NULL').bind(revokeSessionMatch[1], human.id).run();
      return Response.json({ ok: Number(result.meta?.changes ?? 0) === 1, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/auth/sessions' && request.method === 'DELETE') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [human.id]));
        if (result) return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
      }
      await env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(human.id).run();
      return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
    }
    if (url.pathname === '/api/auth/register' && request.method === 'POST') {
      const body = await request.json<{ email?: string; password?: string; passwordConfirmation?: string; displayName?: string }>();
      const email = body.email?.trim().toLowerCase();
      const displayName = body.displayName?.trim();
      const password = body.password ?? '';
      if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return Response.json({ ok: false, error: 'A valid email is required' }, { status: 400 });
      if (!displayName || displayName.length < 2 || displayName.length > 80) return Response.json({ ok: false, error: 'Display name must be 2–80 characters' }, { status: 400 });
      if (password.length < 12) return Response.json({ ok: false, error: 'Password must be at least 12 characters' }, { status: 400 });
      if (password !== (body.passwordConfirmation ?? '')) return Response.json({ ok: false, error: 'Passwords do not match' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => registerIdentityPostgres(repository, { email, displayName, password }));
          if (result) {
            try {
              const identity = result.human as { id: string; email: string };
              await issueActionToken(env, identity.id, 'verify_email', identity.email);
            } catch {
              return Response.json({ ok: false, error: 'Identity created, but the verification email could not be sent. Please retry shortly.' }, { status: 503 });
            }
            return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Identity creation failed';
          return Response.json({ ok: false, error: message }, { status: /already registered/i.test(message) ? 409 : 400 });
        }
      }
      if (await env.DB.prepare('SELECT human_id FROM auth_credentials WHERE email = ?').bind(email).first()) return Response.json({ ok: false, error: 'Email is already registered' }, { status: 409 });
      const humanId = `H-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const accountId = `account-${humanId.toLowerCase()}`;
      const worldDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const businessId = `B-${humanId.slice(2)}`;
      const technologyId = `TECH-${humanId.slice(2)}`;
      const machineId = `M-${humanId.slice(2)}-01`;
      const researchId = `R-${humanId.slice(2)}`;
      const assistantId = `AI-${humanId.slice(2)}-01`;
      const salt = crypto.getRandomValues(new Uint8Array(16));
      // Cloudflare Workers WebCrypto supports PBKDF2 iteration counts up to 100,000.
      // Keep the stored count explicit so login and future migrations remain compatible.
      const iterations = 100000;
      const passwordHash = await derivePassword(password, salt, iterations);
      await env.DB.batch([
        env.DB.prepare('INSERT INTO humans (id, account_id, display_name, age_years, standing, legacy, political_eligibility_game_day) VALUES (?, ?, ?, 31, 0, 0, ?)').bind(humanId, accountId, displayName, worldDay + 3),
        env.DB.prepare('INSERT INTO auth_credentials (human_id, email, password_hash, password_salt, password_iterations) VALUES (?, ?, ?, ?, ?)').bind(humanId, email, passwordHash, bytesToBase64(salt), iterations),
        env.DB.prepare('INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES (?, ?, ?, ?)').bind(accountId, humanId, 18420, 'CREDIT'),
        env.DB.prepare("INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, 'material', 420), (?, 'components', 86), (?, 'energy', 92), (?, 'compute', 64)").bind(humanId, humanId, humanId, humanId),
        env.DB.prepare('INSERT INTO businesses (id, owner_id, name, policy, condition) VALUES (?, ?, ?, ?, ?)').bind(businessId, humanId, `${displayName} Works`, 'reliability', 100),
        env.DB.prepare('INSERT INTO business_financials (business_id, last_game_day) VALUES (?, ?)').bind(businessId, worldDay),
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, ?)').bind(businessId, humanId, 100),
        env.DB.prepare('INSERT INTO technologies (id, name, owner_id, progress) VALUES (?, ?, ?, ?)').bind(technologyId, `${displayName} Adaptive System`, humanId, 0),
        env.DB.prepare('INSERT INTO machines (id, owner_id, name, machine_type, condition, utilization, maintenance_due, productive_capacity) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').bind(machineId, humanId, `${displayName} Service Unit`, 'service-robot', 100, 25, 0, 1),
        env.DB.prepare("INSERT INTO business_assets (business_id, machine_id, assigned_game_day, assigned_by) VALUES (?, ?, ?, 'starter-package')").bind(businessId, machineId, worldDay),
        env.DB.prepare('INSERT INTO research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day) VALUES (?, ?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?))').bind(researchId, technologyId, humanId, 0, 0, 'active', 'WORLD'),
        env.DB.prepare("INSERT INTO ai_assistants (id, owner_id, tier, policy, enabled) VALUES (?, ?, 'basic', 'recommend', 1)").bind(assistantId, humanId),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?))').bind(crypto.randomUUID(), 'BUSINESS', businessId, null, humanId, 1, 'starter_package', humanId, 'WORLD'),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?))').bind(crypto.randomUUID(), 'BUSINESS_SHARES', businessId, null, humanId, 100, 'starter_package', humanId, 'WORLD'),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?))').bind(crypto.randomUUID(), 'MACHINE', machineId, null, humanId, 1, 'starter_package', humanId, 'WORLD'),
      ]);
      try {
        await issueActionToken(env, humanId, 'verify_email', email);
      } catch {
        return Response.json({ ok: false, error: 'Identity created, but the verification email could not be sent. Please retry shortly.' }, { status: 503 });
      }
      return Response.json({ ok: true, human: { id: humanId, displayName, email }, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    if (url.pathname === '/api/auth/verify-email/resend' && request.method === 'POST') {
      const body = await request.json<{ email?: string }>();
      const email = body.email?.trim().toLowerCase();
      if (authorityMode(env) === 'postgres') {
        if (email) {
          const credential = (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string; email_verified_at: string | null }>('SELECT human_id, email, email_verified_at FROM auth_credentials WHERE email = $1', [email])))?.rows[0];
          if (credential && !credential.email_verified_at) {
            const recentlySent = (await withRepository(env, (repository) => repository.query('SELECT 1 FROM auth_action_tokens WHERE human_id = $1 AND action = \'verify_email\' AND created_at > CURRENT_TIMESTAMP - INTERVAL \'60 seconds\' LIMIT 1', [credential.human_id])))?.rows[0];
            if (!recentlySent) {
              try {
                await issueActionToken(env, credential.human_id, 'verify_email', credential.email);
              } catch {
                return Response.json({ ok: false, error: 'The verification email could not be sent. Please try again shortly.' }, { status: 503 });
              }
            }
          }
        }
        return Response.json({ ok: true, message: 'If that identity exists and needs verification, a new email has been sent.' });
      }
      if (email) {
        const credential = await env.DB.prepare('SELECT human_id, email, email_verified_at FROM auth_credentials WHERE email = ?').bind(email).first<{ human_id: string; email: string; email_verified_at: string | null }>();
        if (credential && !credential.email_verified_at) {
          try {
            await issueActionToken(env, credential.human_id, 'verify_email', credential.email);
          } catch {
            return Response.json({ ok: false, error: 'The verification email could not be sent. Please try again shortly.' }, { status: 503 });
          }
        }
      }
      return Response.json({ ok: true, message: 'If that identity exists and needs verification, a new email has been sent.' });
    }
    if (url.pathname === '/api/auth/verify-email' && request.method === 'GET') {
      const token = url.searchParams.get('token');
      if (!token) return Response.json({ ok: false, error: 'Verification token is required' }, { status: 400 });
      const tokenHash = await digest(token);
      if (authorityMode(env) === 'postgres') {
        const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'verify_email' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
        if (!action) return Response.json({ ok: false, error: 'Verification link is invalid or expired' }, { status: 400 });
        const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
          await tx.query('UPDATE auth_credentials SET email_verified_at = CURRENT_TIMESTAMP WHERE human_id = $1', [action.human_id]);
          await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
          return true;
        }));
        if (updated) return Response.json({ ok: true, message: 'Email verified. You can now sign in.' });
      }
      const action = await env.DB.prepare("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = ? AND action = 'verify_email' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP").bind(tokenHash).first<{ id: string; human_id: string }>();
      if (!action) return Response.json({ ok: false, error: 'Verification link is invalid or expired' }, { status: 400 });
      await env.DB.batch([
        env.DB.prepare('UPDATE auth_credentials SET email_verified_at = CURRENT_TIMESTAMP WHERE human_id = ?').bind(action.human_id),
        env.DB.prepare('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = ?').bind(action.id),
      ]);
      return Response.json({ ok: true, message: 'Email verified. You can now sign in.' });
    }
    if (url.pathname === '/api/auth/password-reset/request' && request.method === 'POST') {
      const body = await request.json<{ email?: string }>();
      const email = body.email?.trim().toLowerCase();
      if (authorityMode(env) === 'postgres') {
        const credential = email ? (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string }>('SELECT human_id, email FROM auth_credentials WHERE email = $1', [email])))?.rows[0] : null;
        if (credential) {
          try { await issueActionToken(env, credential.human_id, 'reset_password', credential.email); } catch { /* Keep recovery responses generic. */ }
        }
        return Response.json({ ok: true, message: 'If that identity exists, recovery instructions have been sent.' });
      }
      const credential = email ? await env.DB.prepare('SELECT human_id, email FROM auth_credentials WHERE email = ?').bind(email).first<{ human_id: string; email: string }>() : null;
      if (credential) {
        try { await issueActionToken(env, credential.human_id, 'reset_password', credential.email); } catch { /* Keep recovery responses generic and JSON-safe. */ }
      }
      return Response.json({ ok: true, message: 'If that identity exists, recovery instructions have been sent.' });
    }
    if (url.pathname === '/api/auth/password-reset/complete' && request.method === 'POST') {
      const body = await request.json<{ token?: string; password?: string }>();
      if (!body.token || (body.password ?? '').length < 12) return Response.json({ ok: false, error: 'A valid token and 12-character password are required' }, { status: 400 });
      const tokenHash = await digest(body.token);
      if (authorityMode(env) === 'postgres') {
        const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'reset_password' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
        if (!action) return Response.json({ ok: false, error: 'Recovery link is invalid or expired' }, { status: 400 });
        const salt = crypto.getRandomValues(new Uint8Array(16));
        const iterations = 100000;
        const passwordHash = await derivePassword(body.password, salt, iterations);
        const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
          await tx.query('UPDATE auth_credentials SET password_hash = $1, password_salt = $2, password_iterations = $3 WHERE human_id = $4', [passwordHash, bytesToBase64(salt), iterations, action.human_id]);
          await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
          await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [action.human_id]);
          return true;
        }));
        if (updated) return Response.json({ ok: true, message: 'Password reset. All previous sessions were revoked.' });
      }
      const action = await env.DB.prepare("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = ? AND action = 'reset_password' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP").bind(tokenHash).first<{ id: string; human_id: string }>();
      if (!action) return Response.json({ ok: false, error: 'Recovery link is invalid or expired' }, { status: 400 });
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const iterations = 100000;
      const passwordHash = await derivePassword(body.password, salt, iterations);
      await env.DB.batch([
        env.DB.prepare('UPDATE auth_credentials SET password_hash = ?, password_salt = ?, password_iterations = ? WHERE human_id = ?').bind(passwordHash, bytesToBase64(salt), iterations, action.human_id),
        env.DB.prepare('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = ?').bind(action.id),
        env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(action.human_id),
      ]);
      return Response.json({ ok: true, message: 'Password reset. All previous sessions were revoked.' });
    }
    if (url.pathname === '/api/auth/login' && request.method === 'POST') {
      const body = await request.json<{ email?: string; password?: string; otp?: string }>();
      const email = body.email?.trim().toLowerCase();
      if (authorityMode(env) === 'postgres') {
        if (!email || !body.password) return Response.json({ ok: false, error: 'Invalid email or password' }, { status: 401 });
        try {
          const result = await withRepository(env, (repository) => loginIdentityPostgres(repository, { email, password: body.password ?? '', otp: body.otp ?? '', validTotp }));
          if (result) return new Response(JSON.stringify({ ok: result.ok, human: result.human, expiresAt: result.expiresAt }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(String(result.token), Number(result.maxAge)) } });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Invalid email or password';
          const status = /too many/i.test(message) ? 429 : /verify|active/i.test(message) ? 403 : 401;
          return Response.json({ ok: false, error: message }, { status });
        }
      }
      const attempt = email ? await env.DB.prepare('SELECT * FROM auth_login_attempts WHERE email = ?').bind(email).first<{ window_started_at: string; attempt_count: number; blocked_until: string | null }>() : null;
      if (attempt?.blocked_until && new Date(attempt.blocked_until).getTime() > Date.now()) return Response.json({ ok: false, error: 'Too many login attempts. Try again later.' }, { status: 429 });
      const credential = email ? await env.DB.prepare("SELECT auth_credentials.*, humans.life_status FROM auth_credentials JOIN humans ON humans.id = auth_credentials.human_id WHERE auth_credentials.email = ?").bind(email).first<{ human_id: string; password_hash: string; password_salt: string; password_iterations: number; email_verified_at: string | null; mfa_enabled: number; mfa_secret: string | null; life_status: string }>() : null;
      if (credential?.life_status !== 'active') return Response.json({ ok: false, error: 'This Human is not currently active' }, { status: 403 });
      if (credential && !credential.email_verified_at) return Response.json({ ok: false, error: 'Verify your email before signing in' }, { status: 403 });
      const passwordMatches = Boolean(credential && (body.password ?? '').length && await derivePassword(body.password ?? '', base64ToBytes(credential.password_salt), Number(credential.password_iterations)) === credential.password_hash);
      if (!passwordMatches) {
        if (email) {
          const withinWindow = attempt && Date.now() - new Date(attempt.window_started_at).getTime() < 15 * 60 * 1000;
          const count = withinWindow ? Number(attempt?.attempt_count ?? 0) + 1 : 1;
          const blockedUntil = count >= 5 ? new Date(Date.now() + 15 * 60 * 1000).toISOString() : null;
          await env.DB.prepare('INSERT INTO auth_login_attempts (email, window_started_at, attempt_count, blocked_until) VALUES (?, CURRENT_TIMESTAMP, ?, ?) ON CONFLICT(email) DO UPDATE SET window_started_at = CASE WHEN ? THEN auth_login_attempts.window_started_at ELSE CURRENT_TIMESTAMP END, attempt_count = ?, blocked_until = ?').bind(email, count, blockedUntil, Boolean(withinWindow), count, blockedUntil).run();
        }
        return Response.json({ ok: false, error: 'Invalid email or password' }, { status: 401 });
      }
      if (credential?.mfa_enabled && (!credential.mfa_secret || !(await validTotp(credential.mfa_secret, body.otp ?? '')))) return Response.json({ ok: false, error: 'Authenticator code required' }, { status: 401 });
      await env.DB.prepare('DELETE FROM auth_login_attempts WHERE email = ?').bind(email).run();
      const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
      const tokenHash = await digest(token);
      const sessionId = crypto.randomUUID();
      const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
      await env.DB.prepare('INSERT INTO auth_sessions (id, human_id, token_hash, expires_at) VALUES (?, ?, ?, ?)').bind(sessionId, credential.human_id, tokenHash, expires).run();
      const human = await env.DB.prepare('SELECT id, display_name FROM humans WHERE id = ?').bind(credential.human_id).first();
      return new Response(JSON.stringify({ ok: true, human, expiresAt: expires }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(token, SESSION_DAYS * 86400) } });
    }
    if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
      const token = cookieValue(request, 'earth_session');
      if (authorityMode(env) === 'postgres') {
        if (token) await withRepository(env, async (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = $1', [await digest(token)]));
        return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
      }
      if (token) await env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = ?').bind(await digest(token)).run();
      return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
    }
    const publicMutation = url.pathname === '/api/auth/register' || url.pathname === '/api/auth/login' || url.pathname === '/api/auth/logout' || url.pathname === '/api/auth/verify-email/resend' || url.pathname === '/api/auth/password-reset/request' || url.pathname === '/api/auth/password-reset/complete';
    const estateMutation = url.pathname === '/api/life/successor' || url.pathname === '/api/successor';
    if (url.pathname.startsWith('/api/') && request.method === 'POST' && !publicMutation && !(await currentHuman(request, env, estateMutation))) {
      return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    }
    if (url.pathname === '/api/ai' && !(await currentHuman(request, env))) {
      return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    }
    if (url.pathname === '/edge/market') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const stub = env.MARKET_COORDINATOR.getByName('central-market');
      if (request.method === 'POST') {
        return Response.json(await stub.submitCommand({ humanId: human.id, command: await request.json() }));
      }
      return Response.json({ ok: true, coordinator: 'market', state: await stub.snapshot() });
    }
    if (url.pathname === '/edge/events') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const stub = env.MARKET_COORDINATOR.getByName('events-global');
      return stub.fetch(request);
    }
    if (url.pathname === '/api/world' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const viewerId = viewer.id;
      if (authorityMode(env) === 'postgres') {
        try {
          const snapshot = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewerId));
          if (snapshot) return Response.json(snapshot);
        } catch (error) {
          console.error(JSON.stringify({ event: 'world_snapshot_failed', code: 'WORLD_SNAPSHOT_UNAVAILABLE', message: error instanceof Error ? error.message : 'unknown' }));
          return Response.json({ ok: false, code: 'WORLD_SNAPSHOT_UNAVAILABLE', error: 'World snapshot is temporarily unavailable', persistence: 'planetscale-postgres' }, { status: 503 });
        }
      }
      const [world, human, institutions, resources, business, technology, proposals, machines, account, ballots, succession, membership, prices, ledger, cityMetrics, corporationMetrics, personalFinance, contracts] = await Promise.all([
        env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM institutions').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(viewerId).all(),
        env.DB.prepare("SELECT businesses.*, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id AND holder_id = ?), 0) AS owned_shares, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id), 0) AS total_issued_shares, (SELECT holder_id FROM business_shares WHERE business_id = businesses.id ORDER BY shares DESC, holder_id LIMIT 1) AS controlling_human_id, COALESCE(business_constitutions.version, 1) AS constitution_version, COALESCE(business_constitutions.shareholder_vote_threshold, 0.5) AS shareholder_vote_threshold, COALESCE(business_constitutions.board_approval_threshold, 0.5) AS board_approval_threshold, COALESCE(business_constitutions.dilution_notice_days, 3) AS dilution_notice_days, COALESCE(business_management.manager_id, businesses.owner_id) AS manager_id, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit FROM businesses LEFT JOIN business_constitutions ON business_constitutions.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id LEFT JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.owner_id = ? OR business_management.manager_id = ? OR EXISTS (SELECT 1 FROM business_shares viewer_shares WHERE viewer_shares.business_id = businesses.id AND viewer_shares.holder_id = ?) ORDER BY businesses.id LIMIT 1").bind(viewerId, viewerId, viewerId, viewerId).first(),
        env.DB.prepare('SELECT * FROM technologies WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM proposals ORDER BY closes_at ASC LIMIT 20').all(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind(viewerId).all(),
        env.DB.prepare('SELECT balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewerId, 'CREDIT').first<{ balance: number }>(),
        env.DB.prepare('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice').all(),
        env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM market_prices ORDER BY product').all(),
        env.DB.prepare('SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 25').all(),
        env.DB.prepare("SELECT * FROM cities WHERE id = COALESCE((SELECT city_id FROM memberships WHERE human_id = ? AND city_id IS NOT NULL), 'CITY-0084')").bind(viewerId).first(),
        env.DB.prepare("SELECT * FROM corporations WHERE id = COALESCE((SELECT corporation_id FROM memberships WHERE human_id = ? AND corporation_id IS NOT NULL), 'CORP-001')").bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM personal_financial_states WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = ? OR negotiated_contracts.counterparty_id = ? ORDER BY negotiated_contracts.created_at DESC LIMIT 30").bind(viewerId, viewerId).all(),
      ]);
      const institutionRows = institutions.results as Array<Record<string, unknown>>;
      const byKind = (kind: string) => institutionRows.find((item) => item.kind === kind) ?? {};
      const resourceMap = Object.fromEntries((resources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount]));
      const voteCounts = (ballots.results as Array<Record<string, unknown>>).reduce<Record<string, Record<string, number>>>((all, item) => {
        const proposalId = String(item.proposal_id);
        all[proposalId] ??= {};
        all[proposalId][String(item.choice)] = Number(item.count);
        return all;
      }, {});
      const marketProducts = Object.fromEntries((prices.results as Array<Record<string, unknown>>).map((item) => [item.product, { price: item.price, supply: item.supply, demand: item.demand }]));
      const marketFee = await marketFeeRate(env);
      const rankings = await Promise.all([
        env.DB.prepare('SELECT id, residents, treasury, housing_capacity, energy_capacity FROM cities ORDER BY treasury DESC LIMIT 10').all(),
        env.DB.prepare('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10').all(),
      ]);
      const [book, trades] = await Promise.all([
        env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all(),
        env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all(),
      ]);
      const ownOrders = await env.DB.prepare("SELECT id, product, side, quantity, filled_quantity, limit_price, status, created_at FROM market_orders WHERE human_id = ? AND status IN ('open','partial') ORDER BY created_at DESC LIMIT 50").bind(viewerId).all();
      const productionEvents = await env.DB.prepare('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = ? ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT 30').bind(viewerId).all();
      const aiAssistants = await env.DB.prepare('SELECT id, tier, policy, enabled FROM ai_assistants WHERE owner_id = ? ORDER BY id').bind(viewerId).all();
      const aiRecommendations = [
        ...(machines.results as Array<Record<string, unknown>>).filter((machine) => Number(machine.condition ?? 100) < 40).map((machine) => ({ type: 'maintenance', priority: 'high', subject: machine.id, message: `${machine.name} is below 40% condition; allocate Components or enable maintenance automation.` })),
        ...(machines.results as Array<Record<string, unknown>>).filter((machine) => Number(machine.utilization ?? 0) > 0 && Number(machine.condition ?? 100) < 70).map((machine) => ({ type: 'utilization', priority: 'medium', subject: machine.id, message: `Reduce utilization for ${machine.name} until its condition improves.` })),
        ...(Number(cityMetrics?.health_capacity ?? 0) / 100 < 0.5 ? [{ type: 'services', priority: 'high', subject: 'CITY-HEALTH', message: 'Health service is critical; propose or fund additional city health capacity.' }] : []),
      ];
      const communities = await env.DB.prepare('SELECT id, name, status FROM communities ORDER BY name LIMIT 20').all();
      const technologyRegistry = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS count FROM patents WHERE technology_id = ? AND status = ?').bind(technology?.id ?? '', 'active').first(),
        env.DB.prepare('SELECT COUNT(*) AS count FROM technology_licenses WHERE patent_id IN (SELECT id FROM patents WHERE technology_id = ?) AND status = ?').bind(technology?.id ?? '', 'active').first(),
      ]);
      const finance = await env.DB.prepare('SELECT scope, category, rate, version FROM tax_rules WHERE active = 1 ORDER BY id').all();
      const liquidity = await env.DB.prepare("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index").first<{ active_humans: number; money_supply: number; living_cost_index: number }>();
      const liquidityTarget = Number(liquidity?.active_humans ?? 0) * Math.max(0.5, Number(liquidity?.living_cost_index ?? 1)) * 100;
      const liquiditySupply = Number(liquidity?.money_supply ?? 0);
      const liquidityStatus = liquiditySupply < liquidityTarget * 0.8 ? 'below-corridor' : liquiditySupply > liquidityTarget * 1.2 ? 'above-corridor' : 'inside-corridor';
      const audit = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM account_balances WHERE balance < 0').first<{ invalid: number }>(),
        env.DB.prepare("SELECT COUNT(*) AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account").first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM machines WHERE condition < 0 OR condition > 100').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)').first<{ invalid: number }>(),
      ]);
      const financialStates = await env.DB.prepare('SELECT institution_id, institution_kind, status, since_game_day, recovery_game_day FROM financial_states ORDER BY institution_kind, institution_id').all();
      const roles = await env.DB.prepare("SELECT institution_roles.id, institution_roles.name, institution_roles.institution_id, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id").all();
      const serviceRatios = cityMetrics ? {
        housing: Math.min(1, Number(cityMetrics.housing_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        energy: Math.min(1, Number(cityMetrics.energy_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        connectivity: Math.min(1, Number(cityMetrics.connectivity_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        health: Math.min(1, Number(cityMetrics.health_capacity ?? 0) / 100),
      } : { housing: 0.75, energy: 0.75, connectivity: 0.75, health: 0.5 };
      const serviceStatus = {
        housing: serviceRatios.housing >= 1 ? 'normal' : serviceRatios.housing >= 0.75 ? 'basic' : 'critical',
        utilities: serviceRatios.energy >= 1 ? 'normal' : serviceRatios.energy >= 0.75 ? 'basic' : 'critical',
        connectivity: serviceRatios.connectivity >= 1 ? 'normal' : serviceRatios.connectivity >= 0.75 ? 'basic' : 'critical',
        health: serviceRatios.health >= 0.8 ? 'normal' : serviceRatios.health >= 0.5 ? 'basic' : 'critical',
      };
      const cityQualification = cityMetrics ? {
        activePopulation: Number(cityMetrics.residents ?? 0) >= 10,
        housing: Number(cityMetrics.housing_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        energy: Number(cityMetrics.energy_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        connectivity: Number(cityMetrics.connectivity_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        health: Number(cityMetrics.health_capacity ?? 0) >= 50,
        treasury: Number(cityMetrics.treasury ?? 0) >= 0,
        governance: true,
      } : {};
      const corporationQualification = corporationMetrics ? {
        activeMembership: Number(corporationMetrics.member_count ?? 0) >= 30,
        recognizedCity: Boolean(await env.DB.prepare('SELECT id FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = ? AND city_id IS NOT NULL LIMIT 1)').bind(corporationMetrics.id).first()),
        treasury: Number(corporationMetrics.treasury ?? 0) >= 1000,
        constitution: Number(corporationMetrics.constitution_version ?? 0) >= 1,
        governance: true,
      } : {};
      const history = await Promise.all([
        env.DB.prepare('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT 12').all(),
        env.DB.prepare('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT 20').all(),
      ]);
      return Response.json({
        clock: { day: world?.game_day ?? 184, minute: world?.game_minute ?? 0, realSecondsPerGameMinute: 1 },
        world: { health: world?.health ?? 68, batch: world?.market_batch_seconds ?? 498, livingCostIndex: world?.living_cost_index ?? 1, essentialServicesIndex: world?.essential_services_index ?? 0.68, serviceRatios, serviceStatus, cityQualification, corporationQualification },
        human: { id: human?.id, name: human?.display_name, credits: account?.balance ?? 0, standing: human?.standing ?? 0, legacy: human?.legacy ?? 0, ageYears: human?.age_years ?? 31, politicalEligibilityGameDay: human?.political_eligibility_game_day ?? 0, politicalMaturity: Number(world?.game_day ?? 0) >= Number(human?.political_eligibility_game_day ?? 0) },
        life: { generation: 1, status: human?.life_status ?? 'active', ageYears: human?.age_years ?? 31, successor: succession ?? null, estatePeriodDays: succession?.estate_period_days ?? 30 },
        membership: membership ?? null,
        institutions: { ouc: byKind('OUC'), corporation: { ...byKind('CORPORATION'), ...corporationMetrics }, city: { ...byKind('CITY'), ...cityMetrics }, business: byKind('BUSINESS') },
        resources: resourceMap, business: business ?? {}, market: { products: marketProducts, book: book.results, trades: trades.results, orders: ownOrders.results, feeRate: marketFee, lastSettlement: null },
        governance: { proposals: (proposals.results as Array<Record<string, unknown>>).map((proposal) => ({ ...proposal, votes: voteCounts[String(proposal.id)] ?? { support: 0, oppose: 0, abstain: 0 }, ballots: {} })) },
        technology: { research: technology ?? {}, activePatents: Number(technologyRegistry[0]?.count ?? 0), activeLicenses: Number(technologyRegistry[1]?.count ?? 0) }, machines: machines.results, productionEvents: productionEvents.results, aiAssistants: aiAssistants.results, aiRecommendations, ledgerEntries: ledger.results,
        publicActivity: [{ type: 'world_clock', day: world?.game_day ?? 184 }, { type: 'research_progress', progress: technology?.progress ?? 0 }, { type: 'market_cycle', batch: world?.market_batch_seconds ?? 498 }],
        rankings: { cities: rankings[0].results, corporations: rankings[1].results },
        history: { events: history[0].results, rankings: history[1].results },
        financeStatus: financialStates.results,
        personalFinance: personalFinance ?? { status: 'active', protected_credits: 100 },
        contracts: contracts.results,
        roles: roles.results,
        communities: communities.results,
        audit: { balancesNonNegative: Number(audit[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(audit[1]?.invalid ?? 0) === 0, machineConditionsBounded: Number(audit[2]?.invalid ?? 0) === 0, corporationMemberCountsConsistent: Number(audit[3]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(audit[4]?.invalid ?? 0) === 0 },
        finance: { taxRules: finance.results, liquidity: { activeHumans: Number(liquidity?.active_humans ?? 0), moneySupply: liquiditySupply, target: liquidityTarget, corridor: { low: liquidityTarget * 0.8, high: liquidityTarget * 1.2 }, status: liquidityStatus } },
        persistence: 'cloudflare-d1'
      });
    }
    if (url.pathname === '/api/ai' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => listAssistantsPostgres(repository, viewer.id));
      return Response.json({ ...result, constraints: { governance: false, authority: false, allowedPolicies: ['recommend', 'maintenance'] }, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/ai/policy' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ assistantId?: string; policy?: string; enabled?: boolean }>();
      if (!body.assistantId || !['recommend', 'maintenance'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Basic AI supports only recommend or maintenance policies' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => updateAssistantPolicyPostgres(repository, { ownerId: viewer.id, assistantId: body.assistantId, policy: body.policy ?? 'recommend', enabled: body.enabled !== false }));
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'AI assistant not found' }, { status: 404 });
      }
    }
    if (url.pathname === '/api/ai/upgrade' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ assistantId?: string; otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for AI upgrade' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => upgradeAssistantPostgres(repository, { ownerId: viewer.id, assistantId: body.assistantId ?? '' }));
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'AI upgrade failed';
        return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 404 });
      }
    }
    if (url.pathname === '/api/services/status' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const city = (await withRepository(env, (repository) => repository.query<Record<string, number>>('SELECT cities.* FROM cities JOIN memberships ON memberships.city_id = cities.id WHERE memberships.human_id = $1', [viewer.id])))?.rows[0];
        const independentBaseline = { housing: 0.75, utilities: 0.75, connectivity: 0.75, health: 0.5 };
        const ratios = city ? { housing: Math.min(1, Number(city.housing_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), utilities: Math.min(1, Number(city.energy_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), connectivity: Math.min(1, Number(city.connectivity_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), health: Math.min(1, Number(city.health_capacity ?? 0) / 100) } : independentBaseline;
        const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
        return Response.json({ cityId: city?.id ?? null, provider: city ? 'city-capacity' : 'ouc-independent-minimum', ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)), persistence: 'planetscale-postgres' });
      }
      const city = await env.DB.prepare("SELECT cities.* FROM cities JOIN memberships ON memberships.city_id = cities.id WHERE memberships.human_id = ?").bind(viewer.id).first<Record<string, number>>();
      const independentBaseline = { housing: 0.75, utilities: 0.75, connectivity: 0.75, health: 0.5 };
      const ratios = city ? {
        housing: Math.min(1, Number(city.housing_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
        utilities: Math.min(1, Number(city.energy_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
        connectivity: Math.min(1, Number(city.connectivity_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
        health: Math.min(1, Number(city.health_capacity ?? 0) / 100),
      } : independentBaseline;
      const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
      return Response.json({ cityId: city?.id ?? null, provider: city ? 'city-capacity' : 'ouc-independent-minimum', ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/production/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = $1 ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT $2', [viewer.id, limit]));
        if (result) return Response.json({ events: result.rows, persistence: 'planetscale-postgres' });
      }
      const events = await env.DB.prepare('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = ? ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT ?').bind(viewer.id, limit).all();
      return Response.json({ events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/day/advance' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, async (repository) => {
            const authority = await repository.query("SELECT 1 FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') UNION ALL SELECT 1 FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [viewer.id]);
            if (!authority.rows[0]) throw new Error('Only an active OUC Delegate may advance the simulation clock manually');
            await resolveProposalsPostgres(repository);
            return advanceWorldPostgres(repository, 1440);
          });
          if (result) {
            const state = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewer.id));
            return Response.json({ ok: true, result, state, persistence: 'planetscale-postgres' });
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Unable to advance the simulation clock';
          return Response.json({ ok: false, error: message }, { status: /delegate/i.test(message) ? 403 : 409 });
        }
      }
      if (!(await hasActiveRole(env, viewer.id, ['ROLE-OUC-DELEGATE']))) return Response.json({ ok: false, error: 'Only an active OUC Delegate may advance the simulation clock manually' }, { status: 403 });
      await resolveGovernanceProposals(env);
      const current = await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>();
      const day = (current?.game_day ?? 184) + 1;
      await completeNegotiatedContracts(env, day);
      const expiringRoles = (await env.DB.prepare("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= ?").bind(day).all<{ id: string; human_id: string; institution_id: string; role_id: string }>()).results;
      await env.DB.batch([
        env.DB.prepare("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= ?").bind(day),
        ...expiringRoles.flatMap((role) => [
          env.DB.prepare('INSERT OR IGNORE INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), role.human_id, role.institution_id, role.role_id, 'expired', day, 'term_completed'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, 'governance', 'Role term completed', `Your term for role ${role.role_id} has ended. You may claim an eligible role again when available.`, role.role_id),
        ]),
        env.DB.prepare('UPDATE world_state SET game_day = ?, game_minute = 0 WHERE id = ?').bind(day, 'WORLD'),
        env.DB.prepare("UPDATE machines SET condition = MAX(0, condition - MAX(0.1, utilization * 0.01 * CASE COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC LIMIT 1), 'efficiency') WHEN 'durability' THEN 0.7 WHEN 'safety' THEN 0.8 ELSE 1 END)), maintenance_due = maintenance_due + MAX(1, utilization * 0.5)"),
        env.DB.prepare("UPDATE market_prices SET price = MAX(1, ROUND(price * (1 + MIN(0.05, MAX(-0.05, (demand - supply) / MAX(1, supply + demand)))), 2)), game_day = ?").bind(day),
        env.DB.prepare("UPDATE research_projects SET progress = MIN(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'"),
        env.DB.prepare("UPDATE technologies SET progress = MIN(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)"),
        env.DB.prepare("UPDATE cities SET housing_capacity = housing_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000), energy_capacity = energy_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000), connectivity_capacity = connectivity_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000), health_capacity = health_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000)"),
        env.DB.prepare("UPDATE budgets SET amount = MAX(0, amount - 100), game_day = ? WHERE amount > 0").bind(day),
        env.DB.prepare("UPDATE world_state SET living_cost_index = ROUND(MAX(0.5, MIN(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50)), 3), essential_services_index = ROUND(MAX(0, MIN(1, (SELECT COALESCE(MIN(MIN(1, housing_capacity / MAX(1, residents)), MIN(1, energy_capacity / MAX(1, residents)), MIN(1, connectivity_capacity / MAX(1, residents)), MIN(1, health_capacity / 100.0)), 0) FROM cities))), 3) WHERE id = 'WORLD'"),
        env.DB.prepare("UPDATE world_state SET health = CAST(MAX(0, MIN(100, (SELECT COALESCE(AVG(condition), 68) FROM machines) * (SELECT COALESCE(essential_services_index, 0.68) FROM world_state WHERE id = 'WORLD'))) AS INTEGER) WHERE id = 'WORLD'"),
        ...(day % 365 === 0 ? [env.DB.prepare("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active'")] : []),
        env.DB.prepare('INSERT OR IGNORE INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`CLOCK-${day}`, day, 'world_clock', 'A new game day begins', JSON.stringify({ manual: true, market: true, history: true })),
      ]);
      await runAiMaintenance(env, day);
      await settleMachineProduction(env, day);
      await settleBusinessDepreciation(env, day);
      await settleBusinessTaxes(env, day);
      await settleBasicLevies(env, day);
      await assessInstitutionFinances(env, day);
      await completeNegotiatedContracts(env, day);
      const [updatedHuman, updatedAccount, updatedMachines, updatedResources, updatedBusiness, updatedTechnology] = await Promise.all([
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind(viewer.id).first(),
        env.DB.prepare('SELECT balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewer.id, 'CREDIT').first<{ balance: number }>(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind(viewer.id).all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(viewer.id).all(),
        env.DB.prepare("SELECT businesses.*, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id AND holder_id = ?), 0) AS owned_shares, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id), 0) AS total_issued_shares, (SELECT holder_id FROM business_shares WHERE business_id = businesses.id ORDER BY shares DESC, holder_id LIMIT 1) AS controlling_human_id, COALESCE(business_constitutions.version, 1) AS constitution_version, COALESCE(business_constitutions.shareholder_vote_threshold, 0.5) AS shareholder_vote_threshold, COALESCE(business_constitutions.board_approval_threshold, 0.5) AS board_approval_threshold, COALESCE(business_constitutions.dilution_notice_days, 3) AS dilution_notice_days, COALESCE(business_management.manager_id, businesses.owner_id) AS manager_id, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit FROM businesses LEFT JOIN business_constitutions ON business_constitutions.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id LEFT JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.owner_id = ? OR business_management.manager_id = ? OR EXISTS (SELECT 1 FROM business_shares viewer_shares WHERE viewer_shares.business_id = businesses.id AND viewer_shares.holder_id = ?) ORDER BY businesses.id LIMIT 1").bind(viewer.id, viewer.id, viewer.id, viewer.id).first(),
        env.DB.prepare('SELECT * FROM technologies WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first(),
      ]);
      return Response.json({ ok: true, result: { day }, state: { clock: { day, minute: 0, realSecondsPerGameMinute: 1 }, world: { health: 68, batch: 498 }, human: { id: updatedHuman?.id, name: updatedHuman?.display_name, credits: updatedAccount?.balance ?? 0, standing: updatedHuman?.standing ?? 0, legacy: updatedHuman?.legacy ?? 0, ageYears: updatedHuman?.age_years ?? 31 }, life: { generation: 1, successor: null, estatePeriodDays: 30 }, institutions: {}, resources: Object.fromEntries((updatedResources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount])), business: updatedBusiness ?? {}, market: { products: {}, orders: [], lastSettlement: null }, governance: { proposals: [] }, technology: { research: updatedTechnology ?? {} }, machines: updatedMachines.results, ledgerEntries: [], persistence: 'cloudflare-d1' } });
    }
    if (url.pathname === '/api/health') {
      const postgres = await probePostgres(env.HYPERDRIVE);
      const postgresChecks = await withPostgresRepository(env, async (repository) => {
        const [core, feature, maintenance, reservations, governance, financial, assets, taxed, balances, machines, counts] = await Promise.all([
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state','humans','market_prices','account_balances','ledger_entries','ownership_events','membership_events','authority_events']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['recycling_events','ai_assistants','machine_upgrade_events','machine_sales','production_events']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'maintenance_events' AND column_name = 'correlation_id'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_credits'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['business_constitutions','business_management']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_financials'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_assets'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'business_financials' AND column_name = 'taxed_revenue'"),
          repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
          repository.query('SELECT COUNT(*)::integer AS invalid FROM machines WHERE condition < 0 OR condition > 100'),
          Promise.all([repository.query('SELECT COUNT(*)::integer AS count FROM humans'), repository.query('SELECT COUNT(*)::integer AS count FROM businesses'), repository.query('SELECT COUNT(*)::integer AS count FROM ledger_entries'), repository.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'")]),
        ]);
        return { checks: { database: true, coreSchema: Number(core.rows[0]?.count ?? 0) === 8, featureSchema: Number(feature.rows[0]?.count ?? 0) === 5, maintenanceIdempotency: Number(maintenance.rows[0]?.count ?? 0) === 1, marketCreditReservations: Number(reservations.rows[0]?.count ?? 0) === 1, businessGovernanceSchema: Number(governance.rows[0]?.count ?? 0) === 2, businessFinancialSchema: Number(financial.rows[0]?.count ?? 0) === 1, businessAssetSchema: Number(assets.rows[0]?.count ?? 0) === 1, businessTaxSchema: Number(taxed.rows[0]?.count ?? 0) === 1, balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0, machineConditionsBounded: Number(machines.rows[0]?.invalid ?? 0) === 0 }, counts: { humans: Number(counts[0].rows[0]?.count ?? 0), businesses: Number(counts[1].rows[0]?.count ?? 0), ledger: Number(counts[2].rows[0]?.count ?? 0), world: Number(counts[3].rows[0]?.count ?? 0) } };
      });
      const checks = postgresChecks?.checks ?? { database: false, coreSchema: false, featureSchema: false, maintenanceIdempotency: false, marketCreditReservations: false, businessGovernanceSchema: false, businessFinancialSchema: false, businessAssetSchema: false, businessTaxSchema: false, balancesNonNegative: false, machineConditionsBounded: false };
      const shadow = postgresChecks?.counts ?? null;
      return Response.json({
        ok: Object.values(checks).every(Boolean),
        checks: { ...checks, postgresConfigured: postgres.configured, postgresReachable: postgres.reachable, postgresSchemaReady: postgres.schemaReady, postgresDataReady: postgres.dataReady, postgresShadowParity: Boolean(shadow && postgres.dataReady) },
        postgres: { serverVersion: postgres.serverVersion ?? null, featureTableCount: postgres.featureTableCount ?? 0, dataReady: postgres.dataReady },
        shadow: { postgres: shadow, parity: Boolean(shadow && postgres.dataReady) },
        persistence: 'planetscale-postgres',
        migration: { target: 'planetscale-postgres', stage: postgres.schemaReady && postgres.dataReady ? 'postgres-authority-active' : postgres.schemaReady ? 'schema-ready-awaiting-data-verification' : 'connectivity-probe' },
        authority: 'postgres',
        environment: env.ENVIRONMENT,
        workerVersion: '0.1.0',
      });
    }
    if (url.pathname === '/api/world/activity' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => {
          const [world, technology] = await Promise.all([
            repository.query('SELECT game_day, market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
            repository.query('SELECT progress FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewer.id]),
          ]);
          return { activity: [{ type: 'world_clock', day: world.rows[0]?.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: world.rows[0]?.market_batch_seconds ?? 498 }] };
        });
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [world, technology] = await Promise.all([
        env.DB.prepare('SELECT game_day, market_batch_seconds FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT progress FROM technologies WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first(),
      ]);
      return Response.json({ activity: [{ type: 'world_clock', day: world?.game_day ?? 184 }, { type: 'research_progress', progress: technology?.progress ?? 0 }, { type: 'market_cycle', batch: world?.market_batch_seconds ?? 498 }], persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listEventsPostgres(repository, viewer.id, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [ledger, trades, maintenance, production, proposals] = await Promise.all([
        env.DB.prepare('SELECT id, created_at AS occurred_at, reason_type AS type, amount, game_day, debit_account AS actor FROM ledger_entries ORDER BY created_at DESC LIMIT ?').bind(limit).all(),
        env.DB.prepare("SELECT id, created_at AS occurred_at, 'market_trade' AS type, quantity AS amount, game_day, product AS actor FROM market_trades ORDER BY created_at DESC LIMIT ?").bind(limit).all(),
        env.DB.prepare("SELECT id, created_at AS occurred_at, 'machine_maintenance' AS type, amount, game_day, machine_id AS actor FROM maintenance_events WHERE owner_id = ? ORDER BY created_at DESC LIMIT ?").bind(viewer.id, limit).all(),
        env.DB.prepare("SELECT id, created_at AS occurred_at, 'machine_production' AS type, amount, game_day, machine_id AS actor FROM production_events WHERE owner_id = ? ORDER BY created_at DESC LIMIT ?").bind(viewer.id, limit).all(),
        env.DB.prepare("SELECT id, opens_at AS occurred_at, 'proposal_opened' AS type, 0 AS amount, CAST(strftime('%s', opens_at) AS INTEGER) AS game_day, institution_id AS actor FROM proposals ORDER BY opens_at DESC LIMIT ?").bind(limit).all(),
      ]);
      const events = [...ledger.results, ...trades.results, ...maintenance.results, ...production.results, ...proposals.results]
        .sort((a, b) => String((b as Record<string, unknown>).occurred_at).localeCompare(String((a as Record<string, unknown>).occurred_at)))
        .slice(0, limit);
      return Response.json({ ok: true, events, generatedAt: new Date().toISOString(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/notifications' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.id, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const notifications = await env.DB.prepare('SELECT id, notification_type, title, body, entity_id, read_at, created_at FROM notifications WHERE human_id = ? ORDER BY created_at DESC LIMIT ?').bind(viewer.id, limit).all();
      return Response.json({ notifications: notifications.results, unread: (await env.DB.prepare('SELECT COUNT(*) AS count FROM notifications WHERE human_id = ? AND read_at IS NULL').bind(viewer.id).first<{ count: number }>())?.count ?? 0, persistence: 'cloudflare-d1' });
    }
    const notificationReadMatch = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
    if (notificationReadMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => markNotificationReadPostgres(repository, viewer.id, notificationReadMatch[1]));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      await env.DB.prepare('UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE id = ? AND human_id = ?').bind(notificationReadMatch[1], viewer.id).run();
      return Response.json({ ok: true, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/audit' || url.pathname === '/api/world/audit') && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => auditWorldPostgres(repository, viewer.id));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [balances, ledger, machines, succession, corporationCounts, cityCounts] = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM account_balances WHERE balance < 0').first<{ invalid: number }>(),
        env.DB.prepare("SELECT COUNT(*) AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account").first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM machines WHERE condition < 0 OR condition > 100').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS count FROM succession_plans WHERE human_id = ?').bind(viewer.id).first<{ count: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)').first<{ invalid: number }>(),
      ]);
      const checks = { balancesNonNegative: Number(balances?.invalid ?? 0) === 0, ledgerEntriesValid: Number(ledger?.invalid ?? 0) === 0, machineConditionsBounded: Number(machines?.invalid ?? 0) === 0, oneSuccessionPlanPerHuman: Number(succession?.count ?? 0) <= 1, corporationMemberCountsConsistent: Number(corporationCounts?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(cityCounts?.invalid ?? 0) === 0 };
      return Response.json({ ok: Object.values(checks).every(Boolean), checks, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/institutions' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listInstitutionsPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [community, city, corporation, membership, budgets] = await Promise.all([
        env.DB.prepare('SELECT * FROM communities ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM cities ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM corporations ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM memberships ORDER BY human_id').all(),
        env.DB.prepare('SELECT * FROM budgets ORDER BY game_day DESC').all(),
      ]);
      return Response.json({ community: community.results, city: city.results, corporation: corporation.results, membership: membership.results, budgets: budgets.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/roles' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listRolesPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const currentDay = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      const expiring = (await env.DB.prepare("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= ?").bind(currentDay).all<{ id: string; human_id: string; institution_id: string; role_id: string }>()).results;
      await env.DB.prepare("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= ?").bind(currentDay).run();
      await env.DB.prepare("UPDATE authority_delegations SET status = 'expired' WHERE status = 'active' AND ends_game_day <= ?").bind(currentDay).run();
      if (expiring.length) await env.DB.batch(expiring.flatMap((role) => [
        env.DB.prepare('INSERT OR IGNORE INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), role.human_id, role.institution_id, role.role_id, 'expired', currentDay, 'term_completed'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${currentDay}`, role.human_id, 'governance', 'Role term completed', `Your term for role ${role.role_id} has ended. You may claim an eligible role again when available.`, role.role_id),
      ]));
      const roles = await env.DB.prepare("SELECT institution_roles.*, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status, authority_delegations.delegate_id, authority_delegations.ends_game_day AS delegation_ends_game_day FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' LEFT JOIN authority_delegations ON authority_delegations.role_id = institution_roles.id AND authority_delegations.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id").all();
      return Response.json({ roles: roles.results, persistence: 'cloudflare-d1' });
    }
    const roleClaimMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(claim|resign)$/);
    if (roleClaimMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => changeRolePostgres(repository, { humanId: viewer.id, roleId: roleClaimMatch[1], action: roleClaimMatch[2] as 'claim' | 'resign' }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Role operation failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|assignment|eligible|maturity/i.test(message) ? 409 : 403 });
        }
      }
      const role = await env.DB.prepare("SELECT * FROM institution_roles WHERE id = ? AND status = 'active'").bind(roleClaimMatch[1]).first<{ id: string; institution_id: string; term_days: number; eligibility: string }>();
      if (!role) return Response.json({ ok: false, error: 'Role not found' }, { status: 404 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const maturity = await env.DB.prepare('SELECT political_eligibility_game_day FROM humans WHERE id = ?').bind(viewer.id).first<{ political_eligibility_game_day: number }>();
      if (roleClaimMatch[2] === 'claim' && day < Number(maturity?.political_eligibility_game_day ?? 0)) return Response.json({ ok: false, error: `Political maturity is reached on game day ${maturity?.political_eligibility_game_day}` }, { status: 403 });
      await env.DB.prepare("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= ?").bind(day).run();
      if (roleClaimMatch[2] === 'resign') {
        await env.DB.prepare("UPDATE role_assignments SET status = 'resigned' WHERE role_id = ? AND human_id = ? AND status = 'active'").bind(role.id, viewer.id).run();
        await env.DB.batch([
          env.DB.prepare('INSERT INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, role.institution_id, role.id, 'resigned', day, 'voluntary_resignation'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-RESIGNED-${viewer.id}-${role.id}-${day}`, viewer.id, 'governance', 'Role resigned', `You resigned from role ${role.id}.`, role.id),
        ]);
        return Response.json({ ok: true, status: 'resigned', persistence: 'cloudflare-d1' });
      }
      const eligible = role.eligibility === 'representative'
        ? await env.DB.prepare('SELECT memberships.corporation_id FROM memberships JOIN corporations ON corporations.id = memberships.corporation_id WHERE memberships.human_id = ? AND (corporations.institution_id = ? OR memberships.corporation_id = ?)').bind(viewer.id, role.institution_id, role.institution_id).first()
        : role.eligibility === 'city-representative'
          ? await env.DB.prepare('SELECT memberships.city_id FROM memberships JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = ? AND memberships.corporation_id IS NULL').bind(viewer.id).first()
        : role.eligibility === 'resident'
          ? await env.DB.prepare('SELECT memberships.human_id FROM memberships JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = ? AND (cities.institution_id = ? OR memberships.city_id = ?)').bind(viewer.id, role.institution_id, role.institution_id).first()
          : await env.DB.prepare('SELECT memberships.human_id FROM memberships JOIN corporations ON corporations.id = memberships.corporation_id WHERE memberships.human_id = ? AND (corporations.institution_id = ? OR memberships.corporation_id = ?)').bind(viewer.id, role.institution_id, role.institution_id).first();
      if (!eligible) return Response.json({ ok: false, error: 'Human is not eligible for this role' }, { status: 403 });
      if (await env.DB.prepare("SELECT id FROM role_assignments WHERE role_id = ? AND status = 'active'").bind(role.id).first()) return Response.json({ ok: false, error: 'Role is already occupied' }, { status: 409 });
      const assignmentId = crypto.randomUUID();
      await env.DB.prepare('INSERT INTO role_assignments (id, role_id, institution_id, human_id, started_game_day, ends_game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(assignmentId, role.id, role.institution_id, viewer.id, day, day + Math.min(90, Math.max(7, Number(role.term_days)))).run();
      await env.DB.batch([
        env.DB.prepare('INSERT INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, role.institution_id, role.id, 'claimed', day, 'role_claim'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-CLAIMED-${viewer.id}-${role.id}-${day}`, viewer.id, 'governance', 'Role claimed', `You now hold role ${role.id} until the end of your active term.`, role.id),
      ]);
      return Response.json({ ok: true, assignment: await env.DB.prepare('SELECT * FROM role_assignments WHERE id = ?').bind(assignmentId).first(), persistence: 'cloudflare-d1' });
    }
    const delegationMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(delegate|recall)$/);
    if (delegationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const roleId = delegationMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ delegateHumanId?: string }>();
        try {
          const result = await withRepository(env, (repository) => changeDelegationPostgres(repository, { humanId: viewer.id, roleId, action: delegationMatch[2] as 'delegate' | 'recall', delegateHumanId: body.delegateHumanId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Delegation operation failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|currently|eligible|holder/i.test(message) ? 409 : 403 });
        }
      }
      const role = await env.DB.prepare("SELECT id, institution_id FROM institution_roles WHERE id = ? AND status = 'active'").bind(roleId).first<{ id: string; institution_id: string }>();
      if (!role) return Response.json({ ok: false, error: 'Role not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      const assignment = await env.DB.prepare("SELECT id, human_id, ends_game_day FROM role_assignments WHERE role_id = ? AND status = 'active'").bind(roleId).first<{ id: string; human_id: string; ends_game_day: number }>();
      if (!assignment) return Response.json({ ok: false, error: 'Role is not currently occupied' }, { status: 409 });
      const body = await request.json<{ delegateHumanId?: string }>();
      if (delegationMatch[2] === 'delegate') {
        if (assignment.human_id !== viewer.id) return Response.json({ ok: false, error: 'Only the current role holder may delegate authority' }, { status: 403 });
        const delegateId = body.delegateHumanId?.trim() ?? '';
        if (!delegateId || delegateId === viewer.id || !(await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(delegateId).first())) return Response.json({ ok: false, error: 'Delegate must be another active Human' }, { status: 400 });
        await env.DB.prepare("UPDATE authority_delegations SET status = 'revoked' WHERE role_id = ? AND status = 'active'").bind(roleId).run();
        const delegationId = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare('INSERT INTO authority_delegations (id, institution_id, role_id, delegator_id, delegate_id, starts_game_day, ends_game_day) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(delegationId, role.institution_id, roleId, viewer.id, delegateId, day, assignment.ends_game_day),
          env.DB.prepare('INSERT INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, role.institution_id, roleId, 'delegated', day, `delegated_to:${delegateId}`),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-DELEGATED-${delegationId}`, delegateId, 'governance', 'Authority delegated', `You may exercise delegated authority for role ${roleId} until game day ${assignment.ends_game_day}.`, roleId),
        ]);
        return Response.json({ ok: true, delegation: await env.DB.prepare('SELECT * FROM authority_delegations WHERE id = ?').bind(delegationId).first(), persistence: 'cloudflare-d1' });
      }
      if (!(await eligibleForInstitution(env, viewer.id, role.institution_id))) return Response.json({ ok: false, error: 'Human is not eligible to recall this role' }, { status: 403 });
      await env.DB.batch([
        env.DB.prepare("UPDATE role_assignments SET status = 'resigned' WHERE id = ? AND status = 'active'").bind(assignment.id),
        env.DB.prepare("UPDATE authority_delegations SET status = 'revoked' WHERE role_id = ? AND status = 'active'").bind(roleId),
        env.DB.prepare('INSERT INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, role.institution_id, roleId, 'recalled', day, `recalled_holder:${assignment.human_id}`),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-RECALLED-${assignment.id}`, assignment.human_id, 'governance', 'Role recalled', `Your term for role ${roleId} was recalled on game day ${day}.`, roleId),
      ]);
      return Response.json({ ok: true, status: 'recalled', roleId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/communities' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listCommunitiesPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      return Response.json({ communities: (await env.DB.prepare('SELECT * FROM communities ORDER BY id').all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/communities' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; founderId?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const founderId = viewer.id;
      if (!name || name.length < 3 || name.length > 80) return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(founderId).first())) return Response.json({ ok: false, error: 'Founder not found' }, { status: 404 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createCommunityPostgres(repository, { founderId, name, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Community formation failed';
          return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /founder/i.test(message) ? 404 : 400 });
        }
      }
      const priorFormation = await env.DB.prepare("SELECT institution_id FROM membership_events WHERE reason = 'community_formation' AND institution_type = 'COMMUNITY' AND human_id = ? AND id = ?").bind(founderId, correlationId).first<{ institution_id: string }>();
      if (priorFormation) return Response.json({ ok: true, alreadyProcessed: true, community: await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(priorFormation.institution_id).first(), correlationId, persistence: 'cloudflare-d1' });
      const communityId = `COMM-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO communities (id, name, founder_id, shared_credits) VALUES (?, ?, ?, 0)').bind(communityId, name, founderId),
        env.DB.prepare('INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES (?, ?, ?, ?)').bind(communityId, founderId, 'founder', day),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(correlationId, founderId, 'COMMUNITY', communityId, 'joined', day, 'community_formation'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-FOUNDED-${founderId}-${communityId}`, founderId, 'community', 'Community founded', `You founded community ${communityId}.`, communityId),
      ]);
      return Response.json({ ok: true, community: await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(communityId).first(), persistence: 'cloudflare-d1' });
    }
    const communityMembersMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members$/);
    if (communityMembersMatch && request.method === 'GET') {
      const communityId = communityMembersMatch[1];
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => listCommunityMembersPostgres(repository, communityId));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community members could not be loaded' }, { status: 404 });
        }
      }
      const community = await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(communityId).first();
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      const members = await env.DB.prepare('SELECT community_id, human_id, role, joined_game_day FROM community_members WHERE community_id = ? ORDER BY joined_game_day, human_id').bind(communityId).all();
      return Response.json({ community, members: members.results, persistence: 'cloudflare-d1' });
    }
    if (communityMembersMatch && (request.method === 'POST' || request.method === 'DELETE')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const communityId = communityMembersMatch[1];
      const body = await request.json<{ humanId?: string }>();
      const humanId = viewer.id;
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => changeCommunityMembershipPostgres(repository, { communityId, humanId, action: request.method === 'POST' ? 'join' : 'leave' }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: request.method === 'POST' ? 201 : 200 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Community membership change failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member|active/i.test(message) ? 409 : 400 });
        }
      }
      const [community, human] = await Promise.all([
        env.DB.prepare('SELECT id, status FROM communities WHERE id = ?').bind(communityId).first<{ id: string; status: string }>(),
        env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first(),
      ]);
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      if (community.status !== 'active') return Response.json({ ok: false, error: 'Community is not active' }, { status: 409 });
      if (!human) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const existing = await env.DB.prepare('SELECT community_id FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first();
      if (request.method === 'DELETE') {
        if (!existing) return Response.json({ ok: false, error: 'Human is not a community member' }, { status: 409 });
        await env.DB.batch([
          env.DB.prepare('DELETE FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId),
          env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?), ?)').bind(crypto.randomUUID(), humanId, 'COMMUNITY', communityId, 'left', 'WORLD', 'voluntary_departure'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-LEFT-${humanId}-${communityId}`, humanId, 'community', 'Community left', `You left community ${communityId}.`, communityId),
        ]);
        return Response.json({ ok: true, membership: null, persistence: 'cloudflare-d1' });
      }
      if (existing) return Response.json({ ok: false, error: 'Human is already a community member' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES (?, ?, ?, ?)').bind(communityId, humanId, 'member', day),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), humanId, 'COMMUNITY', communityId, 'joined', day, 'voluntary_membership'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-JOINED-${humanId}-${communityId}`, humanId, 'community', 'Community joined', `You joined community ${communityId}.`, communityId),
      ]);
      return Response.json({ ok: true, member: await env.DB.prepare('SELECT * FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first(), persistence: 'cloudflare-d1' });
    }
    const communityContributionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/contributions$/);
    if (communityContributionMatch && request.method === 'GET') {
      const communityId = communityContributionMatch[1];
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => listCommunityContributionsPostgres(repository, communityId));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community contributions could not be loaded' }, { status: 404 });
        }
      }
      const community = await env.DB.prepare('SELECT id, name, shared_credits FROM communities WHERE id = ?').bind(communityId).first();
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      const entries = await env.DB.prepare("SELECT id, game_day, debit_account, credit_account, amount, reason_id, correlation_id, created_at FROM ledger_entries WHERE reason_type = 'community_contribution' AND credit_account = ? ORDER BY created_at DESC LIMIT 100").bind(communityId).all();
      return Response.json({ community, contributions: entries.results, persistence: 'cloudflare-d1' });
    }
    if (communityContributionMatch && request.method === 'POST') {
      const communityId = communityContributionMatch[1];
      const body = await request.json<{ humanId?: string; amount?: number; correlationId?: string }>();
      const authenticatedHuman = await currentHuman(request, env);
      if (!authenticatedHuman) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const humanId = authenticatedHuman.id;
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = body.correlationId || crypto.randomUUID();
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Contribution amount must be positive' }, { status: 400 });
      if (amount > 100000) return Response.json({ ok: false, error: 'Contribution exceeds the per-command limit' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => contributeToCommunityPostgres(repository, { communityId, humanId, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Community contribution failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|member|active/i.test(message) ? 409 : 400 });
        }
      }
      const [community, human, account, membership, prior] = await Promise.all([
        env.DB.prepare('SELECT id, status, shared_credits FROM communities WHERE id = ?').bind(communityId).first<{ id: string; status: string; shared_credits: number }>(),
        env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first(),
        env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(humanId, 'CREDIT').first<{ account_id: string; balance: number }>(),
        env.DB.prepare('SELECT human_id FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first(),
        env.DB.prepare("SELECT id, amount, game_day FROM ledger_entries WHERE reason_type = 'community_contribution' AND correlation_id = ?").bind(correlationId).first<{ id: string; amount: number; game_day: number }>(),
      ]);
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      if (community.status !== 'active') return Response.json({ ok: false, error: 'Community is not active' }, { status: 409 });
      if (!human || !account) return Response.json({ ok: false, error: 'Contributor account not found' }, { status: 404 });
      if (!membership) return Response.json({ ok: false, error: 'Contributor must be a community member' }, { status: 403 });
      if (prior) return Response.json({ ok: true, alreadyProcessed: true, amount: prior.amount, gameDay: prior.game_day, correlationId, community, persistence: 'cloudflare-d1' });
      if (Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const ledgerId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare('UPDATE communities SET shared_credits = shared_credits + ? WHERE id = ?').bind(amount, communityId),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, account.account_id, communityId, amount, 'CREDIT', 'community_contribution', communityId, 'community-v1', correlationId),
      ]);
      return Response.json({ ok: true, amount, correlationId, community: await env.DB.prepare('SELECT id, name, shared_credits FROM communities WHERE id = ?').bind(communityId).first(), account: await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE account_id = ?').bind(account.account_id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/rankings' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listRankingsPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [wealth, cities, corporations, technologies] = await Promise.all([
        env.DB.prepare('SELECT owner_id AS human_id, balance FROM account_balances WHERE currency = ? ORDER BY balance DESC').bind('CREDIT').all(),
        env.DB.prepare('SELECT id, residents, treasury, housing_capacity, energy_capacity, connectivity_capacity, health_capacity FROM cities ORDER BY treasury DESC').all(),
        env.DB.prepare('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC').all(),
        env.DB.prepare('SELECT id, name, owner_id, progress FROM technologies ORDER BY progress DESC').all(),
      ]);
      return Response.json({ wealth: wealth.results, cities: cities.results, corporations: corporations.results, technologies: technologies.results, generatedFrom: 'cloudflare-d1', persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/history' && request.method === 'GET') {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 25)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listHistoryPostgres(repository, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [events, rankings, deceased] = await Promise.all([
        env.DB.prepare('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT ?').bind(limit).all(),
        env.DB.prepare('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT ?').bind(limit * 4).all(),
        env.DB.prepare('SELECT human_id, display_name, death_game_day, final_standing, final_legacy, successor_name FROM deceased_profiles ORDER BY death_game_day DESC LIMIT ?').bind(limit).all(),
      ]);
      return Response.json({ events: events.results, rankings: rankings.results, deceased: deceased.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/ownership/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listOwnershipEventsPostgres(repository, viewer.id, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const events = await env.DB.prepare('SELECT id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day, created_at FROM ownership_events WHERE from_owner_id = ? OR to_owner_id = ? ORDER BY game_day DESC, created_at DESC LIMIT ?').bind(viewer.id, viewer.id, limit).all();
      return Response.json({ events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/membership/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listMembershipEventsPostgres(repository, viewer.id, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const events = await env.DB.prepare('SELECT id, institution_type, institution_id, action, game_day, reason, created_at FROM membership_events WHERE human_id = ? ORDER BY game_day DESC, created_at DESC LIMIT ?').bind(viewer.id, limit).all();
      return Response.json({ events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/authority/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listAuthorityEventsPostgres(repository, viewer.id, limit));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const events = await env.DB.prepare('SELECT id, institution_id, role_id, action, game_day, reason, created_at FROM authority_events WHERE human_id = ? ORDER BY game_day DESC, created_at DESC LIMIT ?').bind(viewer.id, limit).all();
      return Response.json({ events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/cities' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listCitiesPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const cities = await env.DB.prepare('SELECT * FROM cities ORDER BY id').all();
      return Response.json({ cities: cities.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/cities' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; communityId?: string }>();
      const name = body.name?.trim();
      const communityId = body.communityId?.trim();
      if (!name || name.length < 3 || name.length > 80 || !communityId) return Response.json({ ok: false, error: 'City name and founding Community are required' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createCityPostgres(repository, { founderId: viewer.id, communityId, name }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'City formation failed';
          return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
        }
      }
      const founder = await env.DB.prepare('SELECT human_id FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, viewer.id).first();
      const population = await env.DB.prepare("SELECT COUNT(*) AS count FROM community_members JOIN humans ON humans.id = community_members.human_id LEFT JOIN memberships ON memberships.human_id = community_members.human_id WHERE community_id = ? AND humans.life_status = 'active' AND memberships.city_id IS NULL").bind(communityId).first<{ count: number }>();
      if (!founder) return Response.json({ ok: false, error: 'Founder must belong to the Community' }, { status: 403 });
      if (Number(population?.count ?? 0) < 10) return Response.json({ ok: false, error: 'A City requires at least 10 active Community members' }, { status: 409 });
      if (await env.DB.prepare('SELECT id FROM institutions WHERE name = ?').bind(name).first()) return Response.json({ ok: false, error: 'Institution name already exists' }, { status: 409 });
      const cityId = `CITY-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const residents = Number(population.count);
      const foundingMembers = (await env.DB.prepare("SELECT community_members.human_id FROM community_members JOIN humans ON humans.id = community_members.human_id LEFT JOIN memberships ON memberships.human_id = community_members.human_id WHERE community_members.community_id = ? AND humans.life_status = 'active' AND memberships.city_id IS NULL").bind(communityId).all<{ human_id: string }>()).results;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO institutions (id, kind, name, status) VALUES (?, 'CITY', ?, 'active')").bind(cityId, name),
        env.DB.prepare('INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury) VALUES (?, ?, 0, 0, 0, 0, 50, 0)').bind(cityId, cityId),
        env.DB.prepare("INSERT INTO institution_roles (id, institution_id, name, term_days, eligibility) VALUES (?, ?, 'City Mayor', 90, 'resident'), (?, ?, 'Infrastructure Planner', 90, 'resident')").bind(`${cityId}-MAYOR`, cityId, `${cityId}-PLANNER`, cityId),
        env.DB.prepare("UPDATE memberships SET city_id = ? WHERE human_id IN (SELECT community_members.human_id FROM community_members JOIN humans ON humans.id = community_members.human_id WHERE community_members.community_id = ? AND humans.life_status = 'active') AND city_id IS NULL").bind(cityId, communityId),
        env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?), housing_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = ?), energy_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = ?), connectivity_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(cityId, cityId, cityId, cityId, cityId),
        ...foundingMembers.flatMap((member) => [
          env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), member.human_id, 'CITY', cityId, 'joined', day, 'city_formation'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`CITY-FORMED-${member.human_id}-${cityId}`, member.human_id, 'institution', 'City founded', `City ${cityId} was founded and you became a resident.`, cityId),
        ]),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'city.formed', `${name} was founded`, JSON.stringify({ cityId, communityId, residents })),
      ]);
      return Response.json({ ok: true, city: await env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind(cityId).first(), persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const cityQualificationMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/qualification$/);
    if (cityQualificationMatch && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => cityQualificationPostgres(repository, cityQualificationMatch[1]));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'City qualification unavailable' }, { status: 404 });
        }
      }
      const city = await env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind(cityQualificationMatch[1]).first<Record<string, unknown>>();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      const requirements = {
        activePopulation: Number(city.residents ?? 0) >= 10,
        housing: Number(city.housing_capacity ?? 0) >= Number(city.residents ?? 0),
        energy: Number(city.energy_capacity ?? 0) >= Number(city.residents ?? 0),
        connectivity: Number(city.connectivity_capacity ?? 0) >= Number(city.residents ?? 0),
        health: Number(city.health_capacity ?? 0) >= 50,
        treasury: Number(city.treasury ?? 0) >= 0,
        governance: Boolean(await env.DB.prepare("SELECT id FROM institution_roles WHERE institution_id = ? AND status = 'active'").bind(city.institution_id).first()),
      };
      return Response.json({ ok: true, city, requirements, qualified: Object.values(requirements).every(Boolean), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/corporations' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listCorporationsPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const corporations = await env.DB.prepare('SELECT * FROM corporations ORDER BY id').all();
      return Response.json({ corporations: corporations.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/corporations' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; cityId?: string }>();
      const name = body.name?.trim();
      const cityId = body.cityId?.trim();
      if (!name || name.length < 3 || name.length > 80 || !cityId) return Response.json({ ok: false, error: 'Corporation name and founding City are required' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createCorporationPostgres(repository, { founderId: viewer.id, cityId, name }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Corporation formation failed';
          return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
        }
      }
      const city = await env.DB.prepare('SELECT id, residents FROM cities WHERE id = ?').bind(cityId).first<{ id: string; residents: number }>();
      const founder = await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND city_id = ?').bind(viewer.id, cityId).first();
      if (!city || !founder) return Response.json({ ok: false, error: 'Founder must be a resident of the founding City' }, { status: 403 });
      if (Number(city.residents) < 30) return Response.json({ ok: false, error: 'A Corporation requires at least 30 active City residents' }, { status: 409 });
      if (await env.DB.prepare('SELECT id FROM institutions WHERE name = ?').bind(name).first()) return Response.json({ ok: false, error: 'Institution name already exists' }, { status: 409 });
      const corporationId = `CORP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const foundingMembers = (await env.DB.prepare('SELECT human_id FROM memberships WHERE city_id = ? AND corporation_id IS NULL').bind(cityId).all<{ human_id: string }>()).results;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO institutions (id, kind, name, status) VALUES (?, 'CORPORATION', ?, 'active')").bind(corporationId, name),
        env.DB.prepare('INSERT INTO corporations (id, institution_id, member_count, treasury, constitution_version) VALUES (?, ?, 0, 0, 1)').bind(corporationId, corporationId),
        env.DB.prepare("INSERT INTO institution_roles (id, institution_id, name, term_days, eligibility) VALUES (?, ?, 'Corporation Executive', 90, 'member'), (?, ?, 'Corporation Treasurer', 90, 'member'), (?, ?, 'OUC Delegate', 90, 'representative')").bind(`${corporationId}-EXECUTIVE`, corporationId, `${corporationId}-TREASURER`, corporationId, `${corporationId}-DELEGATE`, corporationId),
        env.DB.prepare('UPDATE memberships SET corporation_id = ? WHERE city_id = ? AND corporation_id IS NULL').bind(corporationId, cityId),
        env.DB.prepare('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = ?) WHERE id = ?').bind(corporationId, corporationId),
        ...foundingMembers.flatMap((member) => [
          env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), member.human_id, 'CORPORATION', corporationId, 'joined', day, 'corporation_formation'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`CORP-FORMED-${member.human_id}-${corporationId}`, member.human_id, 'institution', 'Corporation formed', `Corporation ${corporationId} was formed and you became a member.`, corporationId),
        ]),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'corporation.formed', `${name} was formed`, JSON.stringify({ corporationId, cityId, members: Number(city.residents) })),
      ]);
      return Response.json({ ok: true, corporation: await env.DB.prepare('SELECT * FROM corporations WHERE id = ?').bind(corporationId).first(), persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const corporationQualificationMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/qualification$/);
    if (corporationQualificationMatch && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => corporationQualificationPostgres(repository, corporationQualificationMatch[1]));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation qualification unavailable' }, { status: 404 });
        }
      }
      const corporation = await env.DB.prepare('SELECT * FROM corporations WHERE id = ?').bind(corporationQualificationMatch[1]).first<Record<string, unknown>>();
      if (!corporation) return Response.json({ ok: false, error: 'Corporation not found' }, { status: 404 });
      const city = await env.DB.prepare('SELECT * FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = ? AND city_id IS NOT NULL LIMIT 1)').bind(corporationQualificationMatch[1]).first<Record<string, unknown>>();
      const requirements = {
        activeMembership: Number(corporation.member_count ?? 0) >= 30,
        recognizedCity: Boolean(city),
        treasury: Number(corporation.treasury ?? 0) >= 1000,
        constitution: Number(corporation.constitution_version ?? 0) >= 1,
        governance: Boolean(await env.DB.prepare("SELECT id FROM institution_roles WHERE institution_id = ? AND status = 'active'").bind(corporation.institution_id).first()),
      };
      return Response.json({ ok: true, corporation, city, requirements, qualified: Object.values(requirements).every(Boolean), persistence: 'cloudflare-d1' });
    }
    const cityBudgetMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/budget$/);
    if (cityBudgetMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const cityId = cityBudgetMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ category?: string; amount?: number }>();
        const category = body.category?.trim();
        const amount = Number(body.amount);
        if (!category || !Number.isFinite(amount) || amount < 0) return Response.json({ ok: false, error: 'A valid budget category and non-negative amount are required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => setCityBudgetPostgres(repository, { humanId: viewer.id, cityId, category, amount, correlationId: crypto.randomUUID() }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'City budget update failed';
          return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
        }
      }
      if (!(await env.DB.prepare("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = ? AND role_assignments.institution_id = ? AND role_assignments.status = 'active' AND institution_roles.name IN ('City Mayor', 'Infrastructure Planner')").bind(viewer.id, cityId).first())) return Response.json({ ok: false, error: 'An active City Mayor or Infrastructure Planner term is required' }, { status: 403 });
      const body = await request.json<{ category?: string; amount?: number }>();
      const category = body.category?.trim();
      const amount = Number(body.amount);
      if (!category || !Number.isFinite(amount) || amount < 0) return Response.json({ ok: false, error: 'A valid budget category and non-negative amount are required' }, { status: 400 });
      const city = await env.DB.prepare('SELECT treasury FROM cities WHERE id = ?').bind(cityId).first<{ treasury: number }>();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      const id = `BUDGET-${cityId}-${category}`;
      const currentBudget = await env.DB.prepare('SELECT amount FROM budgets WHERE id = ?').bind(id).first<{ amount: number }>();
      const previousAmount = Number(currentBudget?.amount ?? 0);
      const delta = amount - previousAmount;
      if (delta > Number(city.treasury)) return Response.json({ ok: false, error: 'Budget exceeds city treasury' }, { status: 400 });
      const correlationId = crypto.randomUUID();
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE cities SET treasury = treasury - ? WHERE id = ? AND treasury >= ?').bind(delta, cityId, Math.max(0, delta)),
        env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET amount = excluded.amount, game_day = excluded.game_day').bind(id, cityId, category, amount, day),
        ...(delta !== 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, delta > 0 ? cityId : 'city-budget', delta > 0 ? 'city-budget' : cityId, Math.abs(delta), 'CREDIT', 'city_budget_allocation', id, 'city-finance-v1', correlationId)] : []),
        ...(delta > 0 ? [env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) SELECT ?, human_id, ?, ?, ?, ? FROM role_assignments WHERE institution_id = ? AND status = \'active\'').bind(crypto.randomUUID(), 'institution', 'City budget allocated', `${amount} Credits allocated to ${category}.`, id, cityId)] : []),
      ]);
      return Response.json({ ok: true, budget: await env.DB.prepare('SELECT * FROM budgets WHERE id = ?').bind(id).first(), city: await env.DB.prepare('SELECT id, treasury FROM cities WHERE id = ?').bind(cityId).first(), correlationId, persistence: 'cloudflare-d1' });
    }
    const corporationMembershipMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/membership$/);
    if (corporationMembershipMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const corporationId = corporationMembershipMatch[1];
      const humanId = viewer.id;
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => changeCorporationMembershipPostgres(repository, { humanId, corporationId, action: request.method === 'POST' ? 'join' : 'leave' }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Corporation membership change failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member/i.test(message) ? 409 : 400 });
        }
      }
      const corporation = await env.DB.prepare('SELECT id FROM corporations WHERE id = ?').bind(corporationId).first();
      if (!corporation) return Response.json({ ok: false, error: 'Corporation not found' }, { status: 404 });
      const human = await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first();
      if (!human) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const existing = await env.DB.prepare('SELECT corporation_id FROM memberships WHERE human_id = ?').bind(humanId).first<{ corporation_id: string | null }>();
      if (existing?.corporation_id && existing.corporation_id !== corporationId) return Response.json({ ok: false, error: 'Human already belongs to another corporation' }, { status: 409 });
      const cityId = (await env.DB.prepare('SELECT city_id FROM memberships WHERE corporation_id = ? AND city_id IS NOT NULL LIMIT 1').bind(corporationId).first<{ city_id: string }>())?.city_id ?? null;
      await env.DB.prepare('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES (?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?)) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = COALESCE(memberships.city_id, excluded.city_id)').bind(humanId, corporationId, cityId, 'WORLD').run();
      await env.DB.batch([
        env.DB.prepare('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = ?) WHERE id = ?').bind(corporationId, corporationId),
        ...(cityId ? [env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(cityId, cityId)] : []),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?), ?)').bind(crypto.randomUUID(), humanId, 'CORPORATION', corporationId, 'joined', 'WORLD', 'voluntary_membership'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`CORP-JOINED-${humanId}-${corporationId}`, humanId, 'institution', 'Corporation joined', `You joined corporation ${corporationId}.`, corporationId),
      ]);
      return Response.json({ ok: true, membership: await env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(humanId).first(), persistence: 'cloudflare-d1' });
    }
    if (corporationMembershipMatch && request.method === 'DELETE') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const corporationId = corporationMembershipMatch[1];
      const cityId = (await env.DB.prepare('SELECT city_id FROM memberships WHERE human_id = ? AND corporation_id = ?').bind(viewer.id, corporationId).first<{ city_id: string | null }>())?.city_id;
      await env.DB.prepare('UPDATE memberships SET corporation_id = NULL WHERE human_id = ? AND corporation_id = ?').bind(viewer.id, corporationId).run();
      await env.DB.batch([
        env.DB.prepare('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = ?) WHERE id = ?').bind(corporationId, corporationId),
        ...(cityId ? [env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(cityId, cityId)] : []),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?), ?)').bind(crypto.randomUUID(), viewer.id, 'CORPORATION', corporationId, 'left', 'WORLD', 'voluntary_resignation'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`CORP-LEFT-${viewer.id}-${corporationId}`, viewer.id, 'institution', 'Corporation left', `You left corporation ${corporationId}.`, corporationId),
      ]);
      return Response.json({ ok: true, membership: await env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
    }
    const residencyMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/residency$/);
    if (residencyMatch && (request.method === 'POST' || request.method === 'DELETE')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const cityId = residencyMatch[1];
      if (authorityMode(env) !== 'postgres' && !(await env.DB.prepare('SELECT id FROM cities WHERE id = ?').bind(cityId).first())) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      const day = authorityMode(env) === 'postgres' ? 0 : (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const body = request.method === 'POST' ? await request.json<{ correlationId?: string }>() : {};
      const correlationId = body.correlationId?.trim() || `RESIDENCY-${viewer.id}-${cityId}-${request.method}-${day}`;
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => changeCityResidencyPostgres(repository, { humanId: viewer.id, cityId, action: request.method === 'POST' ? 'join' : 'leave', correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'City residency change failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|resident/i.test(message) ? 409 : 400 });
        }
      }
      const replay = await env.DB.prepare('SELECT institution_id, action, game_day FROM membership_events WHERE id = ? AND human_id = ?').bind(correlationId, viewer.id).first<{ institution_id: string; action: string; game_day: number }>();
      if (replay) return Response.json({ ok: true, alreadyProcessed: true, residency: replay.action === 'joined' ? 'resident' : 'independent', correlationId, gameDay: replay.game_day, membership: await env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
      const existingMembership = await env.DB.prepare('SELECT city_id FROM memberships WHERE human_id = ?').bind(viewer.id).first<{ city_id: string | null }>();
      const previousCityId = existingMembership?.city_id ?? null;
      if (request.method === 'POST') {
        await env.DB.batch([
          env.DB.prepare('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES (?, NULL, ?, ?) ON CONFLICT(human_id) DO UPDATE SET city_id = excluded.city_id, joined_game_day = excluded.joined_game_day').bind(viewer.id, cityId, day),
          ...(previousCityId && previousCityId !== cityId ? [env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(previousCityId, previousCityId)] : []),
          env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(cityId, cityId),
        ]);
      } else {
        await env.DB.batch([
          env.DB.prepare('UPDATE memberships SET city_id = NULL WHERE human_id = ? AND city_id = ?').bind(viewer.id, cityId),
          env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(cityId, cityId),
        ]);
      }
      const action = request.method === 'POST' ? 'joined' : 'left';
      await env.DB.batch([
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(correlationId, viewer.id, 'CITY', cityId, action, day, request.method === 'POST' ? 'voluntary_residency' : 'voluntary_departure'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`CITY-${action.toUpperCase()}-${viewer.id}-${cityId}`, viewer.id, 'institution', action === 'joined' ? 'City residency established' : 'City residency ended', action === 'joined' ? `You are now a resident of city ${cityId}.` : `You left city ${cityId}.`, cityId),
      ]);
      return Response.json({ ok: true, residency: action === 'joined' ? 'resident' : 'independent', correlationId, membership: await env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(viewer.id).first(), city: await env.DB.prepare('SELECT id, residents FROM cities WHERE id = ?').bind(cityId).first(), persistence: 'cloudflare-d1' });
    }
    const corporationSpendMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/treasury\/spend$/);
    if (corporationSpendMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const corporationId = corporationSpendMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ category?: string; amount?: number; cityId?: string; correlationId?: string }>();
        const amount = Number(body.amount);
        const category = body.category?.trim() || 'public-services';
        const cityId = body.cityId?.trim() || 'CITY-0084';
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) return Response.json({ ok: false, error: 'Treasury amount must be between 0 and 100,000 Credits' }, { status: 400 });
        if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => spendCorporationTreasuryPostgres(repository, { humanId: viewer.id, corporationId, cityId, category, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Corporation treasury spending failed';
          return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient/i.test(message) ? 409 : 400 });
        }
      }
      if (!(await env.DB.prepare("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = ? AND role_assignments.institution_id = ? AND role_assignments.status = 'active' AND institution_roles.name IN ('Corporation Executive', 'Corporation Treasurer')").bind(viewer.id, corporationId).first())) return Response.json({ ok: false, error: 'An active Corporation Executive or Treasurer term is required' }, { status: 403 });
      const body = await request.json<{ category?: string; amount?: number; cityId?: string; correlationId?: string }>();
      const amount = Number(body.amount);
      const category = body.category?.trim() || 'public-services';
      const cityId = body.cityId?.trim() || 'CITY-0084';
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) return Response.json({ ok: false, error: 'Treasury amount must be between 0 and 100,000 Credits' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      const priorSpending = await env.DB.prepare("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'corporation_public_spending' AND correlation_id = ?").bind(correlationId).first<{ amount: number; game_day: number }>();
      if (priorSpending) return Response.json({ ok: true, alreadyProcessed: true, amount: priorSpending.amount, gameDay: priorSpending.game_day, correlationId, persistence: 'cloudflare-d1' });
      const [corporation, city] = await Promise.all([
        env.DB.prepare('SELECT treasury FROM corporations WHERE id = ?').bind(corporationId).first<{ treasury: number }>(),
        env.DB.prepare('SELECT id FROM cities WHERE id = ?').bind(cityId).first(),
      ]);
      if (!corporation || !city) return Response.json({ ok: false, error: 'Corporation or destination City not found' }, { status: 404 });
      if (Number(corporation.treasury) < amount) return Response.json({ ok: false, error: 'Insufficient Corporation Treasury' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE corporations SET treasury = treasury - ? WHERE id = ? AND treasury >= ?').bind(amount, corporationId, amount),
        env.DB.prepare('UPDATE cities SET treasury = treasury + ? WHERE id = ?').bind(amount, cityId),
        env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET amount = amount + excluded.amount, game_day = excluded.game_day').bind(`CORP-SPEND-${correlationId}`, cityId, category, amount, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, corporationId, cityId, amount, 'CREDIT', 'corporation_public_spending', cityId, 'corp-finance-v1', correlationId),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'corporation_public_spending', `Corporation funding reached ${cityId}`, JSON.stringify({ corporationId, cityId, category, amount, correlationId })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'institution', 'Corporation spending recorded', `${amount} Credits were routed from ${corporationId} to ${cityId} for ${category}.`, correlationId),
        env.DB.prepare("INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) SELECT lower(hex(randomblob(16))), human_id, 'institution', 'City funding received', ? || ' Credits were routed to ' || ? || ' for ' || ? || '.', ? FROM memberships WHERE city_id = ? AND human_id != ?").bind(amount, cityId, category, correlationId, cityId, viewer.id),
      ]);
      return Response.json({ ok: true, amount, category, cityId, corporation: await env.DB.prepare('SELECT id, treasury FROM corporations WHERE id = ?').bind(corporationId).first(), city: await env.DB.prepare('SELECT id, treasury FROM cities WHERE id = ?').bind(cityId).first(), correlationId, persistence: 'cloudflare-d1' });
    }
    const corporationContributionMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/contributions$/);
    if (corporationContributionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const corporationId = corporationContributionMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ amount?: number; correlationId?: string }>();
        const amount = Math.round(Number(body.amount) * 100) / 100;
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!Number.isFinite(amount) || amount <= 0 || amount > 10000) return Response.json({ ok: false, error: 'Contribution must be between 0 and 10,000 Credits' }, { status: 400 });
        if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => contributeToCorporationPostgres(repository, { humanId: viewer.id, corporationId, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Corporation contribution failed';
          return Response.json({ ok: false, error: message }, { status: /membership|required/i.test(message) ? 403 : /insufficient/i.test(message) ? 409 : 400 });
        }
      }
      if (!(await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND corporation_id = ?').bind(viewer.id, corporationId).first())) return Response.json({ ok: false, error: 'Corporation membership is required' }, { status: 403 });
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Math.round(Number(body.amount) * 100) / 100;
      if (!Number.isFinite(amount) || amount <= 0 || amount > 10000) return Response.json({ ok: false, error: 'Contribution must be between 0 and 10,000 Credits' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      const priorContribution = await env.DB.prepare("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'corporation_contribution' AND correlation_id = ?").bind(correlationId).first<{ amount: number; game_day: number }>();
      if (priorContribution) return Response.json({ ok: true, alreadyProcessed: true, amount: priorContribution.amount, gameDay: priorContribution.game_day, correlationId, persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      if (!account || Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for contribution' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare('UPDATE corporations SET treasury = treasury + ? WHERE id = ?').bind(amount, corporationId),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, account.account_id, corporationId, amount, 'CREDIT', 'corporation_contribution', corporationId, 'corp-finance-v1', correlationId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'institution', 'Corporation contribution recorded', `${amount} Credits added to the Corporation Treasury.`, corporationId),
      ]);
      return Response.json({ ok: true, amount, corporation: await env.DB.prepare('SELECT id, treasury FROM corporations WHERE id = ?').bind(corporationId).first(), correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/machines' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => repository.query('SELECT * FROM machines WHERE owner_id = $1 ORDER BY id', [viewer.id]));
        if (result) return Response.json({ machines: result.rows, persistence: 'planetscale-postgres' });
      }
      return Response.json({ machines: (await env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind(viewer.id).all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/machines/acquire' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ machineType?: string; correlationId?: string }>();
      const type = body.machineType?.trim() ?? '';
      const spec = MACHINE_CATALOG[type];
      if (!spec) return Response.json({ ok: false, error: 'Unsupported machine type' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => acquireMachinePostgres(repository, { ownerId: viewer.id, machineType: type, name: `${type.replaceAll('-', ' ')} ${viewer.id.slice(-4)}`, credit: spec.credit, material: spec.material, capacity: spec.capacity, output: spec.output, inputResource: 'energy', correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Machine acquisition failed' }, { status: 409 });
        }
      }
      const priorAcquisition = await env.DB.prepare("SELECT reason_id FROM ledger_entries WHERE reason_type = 'machine_acquisition' AND correlation_id = ?").bind(correlationId).first<{ reason_id: string }>();
      if (priorAcquisition) return Response.json({ ok: true, alreadyProcessed: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(priorAcquisition.reason_id).first(), acquisitionId: correlationId, persistence: 'cloudflare-d1' });
      const [account, material] = await Promise.all([
        env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>(),
        env.DB.prepare("SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = 'material'").bind(viewer.id).first<{ amount: number }>(),
      ]);
      if (!account || Number(account.balance) < spec.credit) return Response.json({ ok: false, error: 'Insufficient Credits for machine acquisition' }, { status: 409 });
      if (!material || Number(material.amount) < spec.material) return Response.json({ ok: false, error: 'Insufficient Material for machine acquisition' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const machineId = `M-${viewer.id}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const acquisitionId = correlationId;
      const ledgerId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(spec.credit, account.account_id, spec.credit),
        env.DB.prepare("UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = 'material' AND amount >= ?").bind(spec.material, viewer.id, spec.material),
        env.DB.prepare('INSERT INTO machines (id, owner_id, name, machine_type, condition, utilization, maintenance_due, productive_capacity, output_resource, input_resource) VALUES (?, ?, ?, ?, 100, 25, 0, ?, ?, ?)').bind(machineId, viewer.id, `${type.replaceAll('-', ' ')} ${machineId.slice(-4)}`, type, spec.capacity, spec.output, 'energy'),
        env.DB.prepare("INSERT INTO business_assets (business_id, machine_id, assigned_game_day, assigned_by) SELECT id, ?, ?, 'machine-acquisition' FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1").bind(machineId, day, viewer.id),
        env.DB.prepare('INSERT INTO machine_acquisitions (id, machine_id, owner_id, machine_type, credit_cost, material_cost, game_day) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(acquisitionId, machineId, viewer.id, type, spec.credit, spec.material, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, account.account_id, 'machine-registry', spec.credit, 'CREDIT', 'machine_acquisition', machineId, 'machine-v1', acquisitionId),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', machineId, null, viewer.id, 1, 'machine_acquisition', acquisitionId, day),
      ]);
      return Response.json({ ok: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first(), acquisitionId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    if (url.pathname === '/api/production/catalog' && request.method === 'GET') {
      return Response.json({ sectors: [
        { id: 'energy', name: 'Energy', output: 'energy', machineTypes: ['energy-array'], acquisition: MACHINE_CATALOG['energy-array'] },
        { id: 'extraction', name: 'Extraction', output: 'material', machineTypes: ['extractor'], acquisition: MACHINE_CATALOG.extractor },
        { id: 'components', name: 'Components', output: 'components', machineTypes: ['fabricator'], acquisition: MACHINE_CATALOG.fabricator },
        { id: 'machines', name: 'Machines', output: 'components', machineTypes: ['assembly-line'] },
        { id: 'maintenance', name: 'Maintenance', output: 'components', machineTypes: ['service-robot'] },
        { id: 'housing', name: 'Housing', output: 'components', machineTypes: ['housing-fabricator'], acquisition: MACHINE_CATALOG['housing-fabricator'] },
        { id: 'compute', name: 'Compute', output: 'compute', machineTypes: ['compute-node'], acquisition: MACHINE_CATALOG['compute-node'] },
        { id: 'r-and-d', name: 'R&D', output: 'compute', machineTypes: ['research-cluster'], acquisition: MACHINE_CATALOG['research-cluster'] },
      ], rules: { serverAuthoritative: true, productionRequiresUtilization: true, depreciationApplied: true }, persistence: authorityMode(env) === 'postgres' ? 'planetscale-postgres' : 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listTechnologyPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [projects, patents, licenses] = await Promise.all([
        env.DB.prepare('SELECT * FROM research_projects ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM patents ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM technology_licenses ORDER BY id').all(),
      ]);
      return Response.json({ projects: projects.results, patents: patents.results, licenses: licenses.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology/projects' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; budget?: number; focus?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const budget = Math.round(Number(body.budget ?? 240) * 100) / 100;
      const focus = body.focus?.trim() ?? 'efficiency';
      if (!name || name.length < 3 || name.length > 120 || !Number.isFinite(budget) || budget < 240 || budget > 100000 || !['efficiency','durability','safety','cost'].includes(focus)) return Response.json({ ok: false, error: 'Research name, focus, or initial budget is invalid' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createResearchProjectPostgres(repository, { ownerId: viewer.id, name, budget, focus, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Research project creation failed' }, { status: 409 });
        }
      }
      const priorProject = await env.DB.prepare("SELECT reason_id FROM ledger_entries WHERE reason_type = 'research_project_funding' AND correlation_id = ?").bind(correlationId).first<{ reason_id: string }>();
      if (priorProject) return Response.json({ ok: true, alreadyProcessed: true, project: await env.DB.prepare('SELECT * FROM research_projects WHERE id = ?').bind(priorProject.reason_id).first(), correlationId, persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      if (!account || Number(account.balance) < budget) return Response.json({ ok: false, error: 'Insufficient Credits for research funding' }, { status: 409 });
      const technologyId = `TECH-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const projectId = `PROJECT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(budget, account.account_id, budget),
        env.DB.prepare("INSERT INTO technologies (id, name, owner_id, progress, version, metadata) VALUES (?, ?, ?, 0, 1, '{}')").bind(technologyId, name, viewer.id),
        env.DB.prepare('INSERT INTO research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day, focus) VALUES (?, ?, ?, ?, 0, \'active\', ?, ?)').bind(projectId, technologyId, viewer.id, budget, day, focus),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, account.account_id, projectId, budget, 'CREDIT', 'research_project_funding', projectId, 'research-v1', correlationId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'technology', 'Research project started', `${name} is now active with ${budget} Credits of funding.`, projectId),
      ]);
      return Response.json({ ok: true, project: await env.DB.prepare('SELECT * FROM research_projects WHERE id = ?').bind(projectId).first(), technology: await env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind(technologyId).first(), persistence: 'cloudflare-d1' }, { status: 201 });
    }
    if ((url.pathname === '/api/technology/TECH-001/fund' || url.pathname === '/api/technology/me/fund') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Number(body.amount ?? 240);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Funding amount must be positive' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => fundResearchProjectPostgres(repository, { ownerId: viewer.id, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Research funding failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
        }
      }
      const priorFunding = await env.DB.prepare("SELECT reason_id, amount, game_day FROM ledger_entries WHERE reason_type = 'research_project_funding_increment' AND correlation_id = ?").bind(correlationId).first<{ reason_id: string; amount: number; game_day: number }>();
      if (priorFunding) return Response.json({ ok: true, alreadyProcessed: true, amount: priorFunding.amount, gameDay: priorFunding.game_day, project: await env.DB.prepare('SELECT * FROM research_projects WHERE id = ?').bind(priorFunding.reason_id).first(), correlationId, persistence: 'cloudflare-d1' });
      const project = await env.DB.prepare('SELECT * FROM research_projects WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first<Record<string, unknown>>();
      if (!project) return Response.json({ ok: false, error: 'Research project not found' }, { status: 404 });
      if (project.owner_id !== viewer.id) return Response.json({ ok: false, error: 'This research project belongs to another Human' }, { status: 403 });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      if (!account || Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for research funding' }, { status: 409 });
      const progress = Math.min(100, Number(project.progress) + Math.min(10, amount / 60));
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare('UPDATE research_projects SET budget = budget + ?, progress = ? WHERE id = ?').bind(amount, progress, project.id),
        env.DB.prepare('UPDATE technologies SET progress = ? WHERE id = ?').bind(progress, project.technology_id),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, account.account_id, project.id, amount, 'CREDIT', 'research_project_funding_increment', project.id, 'research-v2', correlationId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'technology', 'Research funding added', `${amount} Credits added to research project ${project.id}.`, project.id),
      ]);
      return Response.json({ ok: true, project: await env.DB.prepare('SELECT * FROM research_projects WHERE id = ?').bind(project.id).first(), technology: await env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind(project.technology_id).first(), correlationId, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/technology/TECH-001/patent' || url.pathname === '/api/technology/me/patent') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => grantPatentPostgres(repository, { ownerId: viewer.id }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Patent grant failed' }, { status: 409 });
        }
      }
      const project = await env.DB.prepare('SELECT * FROM research_projects WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first<Record<string, unknown>>();
      if (!project || Number(project.progress) < 100) return Response.json({ ok: false, error: 'Research must reach 100% before patent grant' }, { status: 409 });
      if (project.owner_id !== viewer.id) return Response.json({ ok: false, error: 'This research project belongs to another Human' }, { status: 403 });
      const existing = await env.DB.prepare('SELECT * FROM patents WHERE technology_id = ? AND status = ?').bind(project.technology_id, 'active').first();
      if (existing) return Response.json({ ok: true, patent: existing, persistence: 'cloudflare-d1' });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const patentId = `PAT-${project.technology_id}`;
      await env.DB.prepare('INSERT INTO patents (id, technology_id, owner_id, granted_game_day, expiry_game_day) VALUES (?, ?, ?, ?, ?)').bind(patentId, project.technology_id, project.owner_id, day, day + 3650).run();
      return Response.json({ ok: true, patent: await env.DB.prepare('SELECT * FROM patents WHERE id = ?').bind(patentId).first(), persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/technology/TECH-001/license' || url.pathname === '/api/technology/me/license') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ licenseeId?: string; royaltyRate?: number; licenseFee?: number; otp?: string }>();
      const licenseeId = body.licenseeId || viewer.id;
      const royaltyRate = Number(body.royaltyRate ?? 0.05);
      if (authorityMode(env) === 'postgres') {
        const licenseFee = Math.round(Number(body.licenseFee ?? (licenseeId === viewer.id ? 0 : 100)) * 100) / 100;
        const correlationId = crypto.randomUUID();
        if (!Number.isFinite(royaltyRate) || royaltyRate < 0 || royaltyRate > 1 || !Number.isFinite(licenseFee) || licenseFee < 0 || licenseFee > 100000 || (licenseeId !== viewer.id && licenseFee < 50)) return Response.json({ ok: false, error: 'License terms are invalid' }, { status: 400 });
        if (licenseeId !== viewer.id && !(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for external IP licensing' }, { status: 401 });
        try {
          const result = await withRepository(env, (repository) => licenseTechnologyPostgres(repository, { ownerId: viewer.id, licenseeId, royaltyRate, licenseFee, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Technology license failed' }, { status: 409 });
        }
      }
      const patent = await env.DB.prepare('SELECT * FROM patents WHERE owner_id = ? AND status = ? ORDER BY granted_game_day DESC LIMIT 1').bind(viewer.id, 'active').first<Record<string, unknown>>();
      if (!patent) return Response.json({ ok: false, error: 'An active patent is required' }, { status: 409 });
      if (patent.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the patent owner can issue a license' }, { status: 403 });
      if (!Number.isFinite(royaltyRate) || royaltyRate < 0 || royaltyRate > 1) return Response.json({ ok: false, error: 'Royalty rate must be between 0 and 1' }, { status: 400 });
      const licensee = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(licenseeId).first();
      if (!licensee) return Response.json({ ok: false, error: 'Licensee not found' }, { status: 404 });
      const licenseFee = Math.round(Number(body.licenseFee ?? (licenseeId === viewer.id ? 0 : 100)) * 100) / 100;
      if (!Number.isFinite(licenseFee) || licenseFee < 0 || licenseFee > 100000 || (licenseeId !== viewer.id && licenseFee < 50)) return Response.json({ ok: false, error: 'External licenses require a fee between 50 and 100,000 Credits' }, { status: 400 });
      if (licenseeId !== viewer.id && !(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for external IP licensing' }, { status: 401 });
      const licenseId = `LIC-${patent.id}-${licenseeId}`;
      const buyerAccount = licenseeId === viewer.id ? null : await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(licenseeId).first<{ account_id: string; balance: number }>();
      const ownerAccount = licenseeId === viewer.id ? null : await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string }>();
      if (licenseeId !== viewer.id && (!buyerAccount || !ownerAccount || Number(buyerAccount.balance) < licenseFee)) return Response.json({ ok: false, error: 'Licensee has insufficient Credits' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>)?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      await env.DB.batch([
        ...(licenseeId !== viewer.id ? [
          env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(licenseFee, buyerAccount!.account_id, licenseFee),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(licenseFee, ownerAccount!.account_id),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, buyerAccount!.account_id, ownerAccount!.account_id, licenseFee, 'CREDIT', 'technology_license_fee', licenseId, 'technology-v2', correlationId),
          env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(licenseFee, licenseFee, day, licenseeId),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), licenseeId, 'technology', 'Technology license acquired', `You licensed patent ${patent.id} for ${licenseFee} Credits.`, licenseId),
        ] : []),
        env.DB.prepare('INSERT INTO technology_licenses (id, patent_id, licensor_id, licensee_id, royalty_rate) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET royalty_rate = excluded.royalty_rate, status = \'active\'').bind(licenseId, patent.id, patent.owner_id, licenseeId, royaltyRate),
      ]);
      return Response.json({ ok: true, license: await env.DB.prepare('SELECT * FROM technology_licenses WHERE id = ?').bind(licenseId).first(), licenseFee, correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => {
          const [account, state, machines, businesses] = await Promise.all([
            repository.query("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
            repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
            repository.query("SELECT id, machine_type, condition FROM machines WHERE owner_id = $1 AND machine_type != 'service-robot'", [viewer.id]),
            repository.query('SELECT id, name, status FROM businesses WHERE owner_id = $1', [viewer.id]),
          ]);
          const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
          return { account: account.rows[0] ?? null, state: stateRow, liquidatableAssets: { machines: machines.rows, businesses: businesses.rows }, protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100), basicServiceRobot: true } };
        });
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [account, state, machines, businesses] = await Promise.all([
        env.DB.prepare("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first(),
        env.DB.prepare('SELECT * FROM personal_financial_states WHERE human_id = ?').bind(viewer.id).first(),
        env.DB.prepare("SELECT id, machine_type, condition FROM machines WHERE owner_id = ? AND machine_type != 'service-robot'").bind(viewer.id).all(),
        env.DB.prepare('SELECT id, name, status FROM businesses WHERE owner_id = ?').bind(viewer.id).all(),
      ]);
      return Response.json({ account, state: state ?? { status: 'active', protected_credits: 100 }, liquidatableAssets: { machines: machines.results, businesses: businesses.results }, protectedMinimum: { credits: Number(state?.protected_credits ?? 100), basicServiceRobot: true }, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/personal/declare' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ otp?: string; reason?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for personal insolvency' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => declarePersonalInsolvencyPostgres(repository, viewer.id, (body.reason?.trim() || 'Human-requested insolvency restructuring').slice(0, 240)));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Personal insolvency failed' }, { status: 409 });
        }
      }
      const prior = await env.DB.prepare("SELECT * FROM personal_financial_states WHERE human_id = ? AND status = 'bankrupt'").bind(viewer.id).first();
      if (prior) return Response.json({ ok: true, alreadyProcessed: true, state: prior, persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      const machines = (await env.DB.prepare("SELECT id, machine_type FROM machines WHERE owner_id = ? AND machine_type != 'service-robot'").bind(viewer.id).all<{ id: string; machine_type: string }>()).results;
      const businesses = (await env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ?').bind(viewer.id).all<{ id: string }>()).results;
      const liquidationValue = Math.round(machines.length * 50 + businesses.length * 100);
      const reason = (body.reason?.trim() || 'Human-requested insolvency restructuring').slice(0, 240);
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare("UPDATE account_balances SET balance = MAX(100, balance) WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id),
        env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(liquidationValue, viewer.id),
        env.DB.prepare("DELETE FROM business_assets WHERE machine_id IN (SELECT id FROM machines WHERE owner_id = ? AND machine_type != 'service-robot')").bind(viewer.id),
        env.DB.prepare('DELETE FROM machines WHERE owner_id = ? AND machine_type != \'service-robot\'').bind(viewer.id),
        ...businesses.map((business) => env.DB.prepare('DELETE FROM business_shares WHERE business_id = ?').bind(business.id)),
        env.DB.prepare('DELETE FROM businesses WHERE owner_id = ?').bind(viewer.id),
        ...businesses.map((business) => env.DB.prepare("DELETE FROM institutions WHERE id = ? AND kind = 'BUSINESS'").bind(business.id)),
        env.DB.prepare('INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES (?, \'bankrupt\', ?, 100, ?) ON CONFLICT(human_id) DO UPDATE SET status = excluded.status, since_game_day = excluded.since_game_day, last_reason = excluded.last_reason, updated_at = CURRENT_TIMESTAMP').bind(viewer.id, day, reason),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`PERSONAL-BANKRUPTCY-${viewer.id}-${day}`, day, 'human.bankruptcy', 'A Human entered insolvency restructuring', JSON.stringify({ humanId: viewer.id, liquidationValue, reason })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'finance', 'Personal insolvency recorded', 'Non-protected productive assets were liquidated. Your basic service robot and 100 Credit protected minimum remain.', eventId),
      ]);
      return Response.json({ ok: true, state: await env.DB.prepare('SELECT * FROM personal_financial_states WHERE human_id = ?').bind(viewer.id).first(), protectedCredits: 100, liquidated: { machines: machines.length, businesses: businesses.length, estimatedValue: liquidationValue }, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => {
          const [account, rules] = await Promise.all([
            repository.query("SELECT account_id, owner_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
            repository.query('SELECT scope, category, rate, version FROM tax_rules WHERE active = true ORDER BY id'),
          ]);
          return { account: account.rows[0] ?? null, taxRules: rules.rows };
        });
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [account, rules] = await Promise.all([
        env.DB.prepare('SELECT account_id, owner_id, balance, currency FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewer.id, 'CREDIT').first(),
        env.DB.prepare('SELECT scope, category, rate, version FROM tax_rules WHERE active = 1 ORDER BY id').all(),
      ]);
      return Response.json({ account, taxRules: rules.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/contracts' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = $1 OR negotiated_contracts.counterparty_id = $1 ORDER BY negotiated_contracts.created_at DESC LIMIT 50", [viewer.id]));
        if (result) return Response.json({ contracts: result.rows, persistence: 'planetscale-postgres' });
      }
      return Response.json({ contracts: (await env.DB.prepare("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = ? OR negotiated_contracts.counterparty_id = ? ORDER BY negotiated_contracts.created_at DESC LIMIT 50").bind(viewer.id, viewer.id).all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/contracts' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ kind?: string; counterpartyId?: string; title?: string; terms?: Record<string, unknown>; amount?: number; durationDays?: number; correlationId?: string }>();
      const kind = body.kind?.trim() ?? '';
      const counterpartyId = body.counterpartyId?.trim() ?? '';
      const title = body.title?.trim() ?? '';
      const amount = Math.round(Number(body.amount ?? 0) * 100) / 100;
      const durationDays = Number(body.durationDays ?? 30);
      if (!['employment', 'intellectual_service', 'capacity', 'strategic'].includes(kind)) return Response.json({ ok: false, error: 'Unsupported contract kind' }, { status: 400 });
      if (!counterpartyId || counterpartyId === viewer.id || !(await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(counterpartyId).first())) return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
      if (title.length < 3 || title.length > 140 || !Number.isFinite(amount) || amount < 0 || amount > 100000 || !Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) return Response.json({ ok: false, error: 'Contract terms are outside engine bounds' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createContractPostgres(repository, { proposerId: viewer.id, kind, counterpartyId, title, terms: body.terms ?? {}, amount, durationDays, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract creation failed' }, { status: 409 });
        }
      }
      const prior = await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE proposer_id = ? AND correlation_id = ?').bind(viewer.id, correlationId).first();
      if (prior) return Response.json({ ok: true, alreadyProcessed: true, contract: prior, correlationId, persistence: 'cloudflare-d1' });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      const contractId = `CON-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      await env.DB.prepare('INSERT INTO negotiated_contracts (id, kind, proposer_id, counterparty_id, title, terms_json, amount, starts_game_day, ends_game_day, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(contractId, kind, viewer.id, counterpartyId, title, JSON.stringify(body.terms ?? {}), amount, day, day + durationDays, correlationId).run();
      await env.DB.batch([
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'contract.proposed', 'A negotiated contract was proposed', JSON.stringify({ contractId, kind, proposer: viewer.id, counterparty: counterpartyId })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), counterpartyId, 'contract', 'Contract proposal received', `${title} was proposed for your acceptance.`, contractId),
      ]);
      return Response.json({ ok: true, contract: await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contractId).first(), correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const contractActionMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(accept|cancel)$/);
    if (contractActionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = contractActionMatch[2] === 'cancel'
            ? await withRepository(env, (repository) => cancelContractPostgres(repository, contractActionMatch[1], viewer.id))
            : await withRepository(env, (repository) => acceptContractPostgres(repository, contractActionMatch[1], viewer.id));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract action failed' }, { status: 409 });
        }
      }
      const contract = await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contractActionMatch[1]).first<{ id: string; proposer_id: string; counterparty_id: string; amount: number; status: string; title: string }>();
      if (!contract) return Response.json({ ok: false, error: 'Contract not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      if (contractActionMatch[2] === 'cancel') {
        if (contract.proposer_id !== viewer.id && contract.counterparty_id !== viewer.id) return Response.json({ ok: false, error: 'Only a contract party may cancel' }, { status: 403 });
        if (contract.status !== 'proposed') return Response.json({ ok: false, error: 'Only a proposed contract can be cancelled' }, { status: 409 });
        await env.DB.prepare("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = ? AND status = 'proposed'").bind(contract.id).run();
        return Response.json({ ok: true, status: 'cancelled', contractId: contract.id, persistence: 'cloudflare-d1' });
      }
      if (contract.counterparty_id !== viewer.id) return Response.json({ ok: false, error: 'Only the counterparty may accept this contract' }, { status: 403 });
      if (contract.status !== 'proposed') return Response.json({ ok: true, alreadyProcessed: contract.status === 'accepted', status: contract.status, contractId: contract.id, persistence: 'cloudflare-d1' });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => acceptContractPostgres(repository, contract.id, viewer.id));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract settlement failed' }, { status: 409 });
        }
      }
      const payer = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.proposer_id).first<{ account_id: string; balance: number }>();
      const receiver = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.counterparty_id).first<{ account_id: string }>();
      if (!payer || !receiver || Number(payer.balance) < Number(contract.amount)) return Response.json({ ok: false, error: 'Proposer has insufficient Credits to settle this contract' }, { status: 409 });
      const correlationId = `CONTRACT-${contract.id}`;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(contract.amount, payer.account_id, contract.amount),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(contract.amount, receiver.account_id),
        env.DB.prepare("UPDATE negotiated_contracts SET status = 'accepted', accepted_game_day = ? WHERE id = ? AND status = 'proposed'").bind(day, contract.id),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, payer.account_id, receiver.account_id, contract.amount, 'CREDIT', 'contract_payment', contract.id, 'contracts-v1', correlationId),
        env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.proposer_id),
        env.DB.prepare("UPDATE business_financials SET revenue = revenue + ?, profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.counterparty_id),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'contract.accepted', 'A negotiated contract was accepted', JSON.stringify({ contractId: contract.id, amount: contract.amount })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.proposer_id, 'contract', 'Contract accepted', `${contract.title} was accepted and ${contract.amount} Credits were settled.`, contract.id),
      ]);
      return Response.json({ ok: true, status: 'accepted', contract: await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contract.id).first(), persistence: 'cloudflare-d1' });
    }
    const contractDisputeMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(dispute|resolve)$/);
    if (contractDisputeMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres' && contractDisputeMatch[2] === 'dispute') {
        const body = await request.json<{ reason?: string }>();
        const reason = body.reason?.trim() ?? '';
        if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => openDisputePostgres(repository, { contractId: contractDisputeMatch[1], claimantId: viewer.id, reason }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyOpen ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Dispute opening failed' }, { status: 409 });
        }
      }
      if (authorityMode(env) === 'postgres' && contractDisputeMatch[2] === 'resolve') {
        const body = await request.json<{ outcome?: string; resolution?: string }>();
        if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => resolveContractDisputePostgres(repository, { contractId: contractDisputeMatch[1], resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Arbitration resolution failed' }, { status: 409 });
        }
      }
      const contract = await env.DB.prepare('SELECT id, proposer_id, counterparty_id, amount, status, title FROM negotiated_contracts WHERE id = ?').bind(contractDisputeMatch[1]).first<{ id: string; proposer_id: string; counterparty_id: string; amount: number; status: string; title: string }>();
      if (!contract) return Response.json({ ok: false, error: 'Contract not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      if (contractDisputeMatch[2] === 'dispute') {
        if (viewer.id !== contract.proposer_id && viewer.id !== contract.counterparty_id) return Response.json({ ok: false, error: 'Only a contract party may open a dispute' }, { status: 403 });
        if (!['accepted', 'completed'].includes(contract.status)) return Response.json({ ok: false, error: 'Only an accepted or completed contract can be disputed' }, { status: 409 });
        const body = await request.json<{ reason?: string }>();
        const reason = body.reason?.trim() ?? '';
        if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
        const existing = await env.DB.prepare("SELECT * FROM contract_disputes WHERE contract_id = ? AND status = 'open'").bind(contract.id).first();
        if (existing) return Response.json({ ok: true, alreadyOpen: true, dispute: existing, persistence: 'cloudflare-d1' });
        const disputeId = `DISPUTE-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
        await env.DB.batch([
          env.DB.prepare('INSERT INTO contract_disputes (id, contract_id, claimant_id, respondent_id, reason) VALUES (?, ?, ?, ?, ?)').bind(disputeId, contract.id, viewer.id, viewer.id === contract.proposer_id ? contract.counterparty_id : contract.proposer_id, reason),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'arbitration.opened', 'A contract dispute was opened', JSON.stringify({ disputeId, contractId: contract.id })),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.proposer_id, 'arbitration', 'Contract dispute opened', `${contract.title} is awaiting OUC arbitration.`, disputeId),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.counterparty_id, 'arbitration', 'Contract dispute opened', `${contract.title} is awaiting OUC arbitration.`, disputeId),
        ]);
        return Response.json({ ok: true, dispute: await env.DB.prepare('SELECT * FROM contract_disputes WHERE id = ?').bind(disputeId).first(), persistence: 'cloudflare-d1' }, { status: 201 });
      }
      if (authorityMode(env) !== 'postgres' && !(await canExerciseDelegatedRole(env, viewer.id, 'OUC-001'))) return Response.json({ ok: false, error: 'OUC arbitration authority is required' }, { status: 403 });
      const body = await request.json<{ outcome?: string; resolution?: string }>();
      if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => resolveContractDisputePostgres(repository, { contractId: contract.id, resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Arbitration resolution failed' }, { status: 409 });
        }
      }
      const dispute = await env.DB.prepare("SELECT * FROM contract_disputes WHERE contract_id = ? AND status = 'open'").bind(contract.id).first<{ id: string; claimant_id: string; respondent_id: string }>();
      if (!dispute) return Response.json({ ok: false, error: 'Open dispute not found' }, { status: 404 });
      const statements: D1PreparedStatement[] = [
        env.DB.prepare("UPDATE contract_disputes SET status = 'resolved', outcome = ?, resolved_by = ?, resolved_game_day = ?, resolution = ? WHERE id = ? AND status = 'open'").bind(body.outcome, viewer.id, day, body.resolution!.trim().slice(0, 1000), dispute.id),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'arbitration.resolved', 'A contract dispute was resolved', JSON.stringify({ disputeId: dispute.id, contractId: contract.id, outcome: body.outcome, resolvedBy: viewer.id })),
      ];
      if (body.outcome === 'void') {
        const payer = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.counterparty_id).first<{ account_id: string; balance: number }>();
        const receiver = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.proposer_id).first<{ account_id: string }>();
        if (!payer || !receiver || Number(payer.balance) < Number(contract.amount)) return Response.json({ ok: false, error: 'Counterparty cannot fund the arbitration refund' }, { status: 409 });
        const refundId = `ARBITRATION-REFUND-${contract.id}`;
        statements.push(
          env.DB.prepare("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = ? AND status IN ('accepted','completed')").bind(contract.id),
          env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(contract.amount, payer.account_id, contract.amount),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(contract.amount, receiver.account_id),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(refundId, day, payer.account_id, receiver.account_id, contract.amount, 'CREDIT', 'contract_arbitration_refund', contract.id, 'arbitration-v1', refundId),
          env.DB.prepare("UPDATE business_financials SET operating_costs = MAX(0, operating_costs - ?), profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.proposer_id),
          env.DB.prepare("UPDATE business_financials SET revenue = MAX(0, revenue - ?), profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.counterparty_id),
        );
      }
      await env.DB.batch(statements);
      return Response.json({ ok: true, outcome: body.outcome, dispute: await env.DB.prepare('SELECT * FROM contract_disputes WHERE id = ?').bind(dispute.id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const liquidity = (await withRepository(env, (repository) => repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index")))?.rows[0];
        const activeHumans = Number(liquidity?.active_humans ?? 0); const supply = Number(liquidity?.money_supply ?? 0); const livingCostIndex = Number(liquidity?.living_cost_index ?? 1); const target = activeHumans * Math.max(0.5, livingCostIndex) * 100;
        return Response.json({ activeHumans, moneySupply: supply, livingCostIndex, target, corridor: { low: target * 0.8, high: target * 1.2 }, status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor', persistence: 'planetscale-postgres' });
      }
      const liquidity = await env.DB.prepare("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index").first<{ active_humans: number; money_supply: number; living_cost_index: number }>();
      const target = Number(liquidity?.active_humans ?? 0) * Math.max(0.5, Number(liquidity?.living_cost_index ?? 1)) * 100;
      const supply = Number(liquidity?.money_supply ?? 0);
      return Response.json({ activeHumans: Number(liquidity?.active_humans ?? 0), moneySupply: supply, livingCostIndex: Number(liquidity?.living_cost_index ?? 1), target, corridor: { low: target * 0.8, high: target * 1.2 }, status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor', persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/status' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => {
          const [states, events] = await Promise.all([
            repository.query('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id'),
            repository.query('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50'),
          ]);
          return { states: states.rows, events: events.rows };
        });
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [states, events] = await Promise.all([
        env.DB.prepare('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id').all(),
        env.DB.prepare('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50').all(),
      ]);
      return Response.json({ states: states.results, events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/recover' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ institutionId?: string; amount?: number; otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for financial recovery' }, { status: 401 });
      const institutionId = body.institutionId?.trim() ?? '';
      const amount = Math.round(Number(body.amount) * 100) / 100;
      if (!institutionId || !Number.isFinite(amount) || amount <= 0 || amount > 100000) return Response.json({ ok: false, error: 'Recovery amount must be between 0 and 100,000 Credits' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => recoverInstitutionPostgres(repository, { humanId: viewer.id, institutionId, amount, correlationId: crypto.randomUUID() }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Institution recovery failed';
          return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient|crisis/i.test(message) ? 409 : 400 });
        }
      }
      const institution = await env.DB.prepare('SELECT id, kind FROM institutions WHERE id = ? AND kind IN (\'CITY\', \'CORPORATION\')').bind(institutionId).first<{ id: string; kind: string }>();
      if (!institution) return Response.json({ ok: false, error: 'Recoverable institution not found' }, { status: 404 });
      const eligible = institution.kind === 'CITY'
        ? await hasActiveRole(env, viewer.id, ['ROLE-CITY-MAYOR', 'ROLE-CITY-PLANNER'])
        : await hasActiveRole(env, viewer.id, ['ROLE-CORP-EXECUTIVE', 'ROLE-CORP-TREASURER']);
      if (!eligible) return Response.json({ ok: false, error: 'An active institutional finance role is required' }, { status: 403 });
      const state = await env.DB.prepare("SELECT status FROM financial_states WHERE institution_id = ? AND status IN ('distressed','insolvent')").bind(institutionId).first<{ status: string }>();
      if (!state) return Response.json({ ok: false, error: 'Institution is not currently in a recoverable crisis state' }, { status: 409 });
      const account = await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = \'CREDIT\'').bind(viewer.id).first<{ account_id: string; balance: number }>();
      if (!account || Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for recovery' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = \'WORLD\'').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      const ledgerId = crypto.randomUUID();
      const targetTable = institution.kind === 'CITY' ? 'cities' : 'corporations';
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare(`UPDATE ${targetTable} SET treasury = treasury + ? WHERE id = ?`).bind(amount, institutionId),
        env.DB.prepare("UPDATE financial_states SET status = 'active', recovery_game_day = ?, last_reason = 'Player-authorized crisis recovery', updated_at = CURRENT_TIMESTAMP WHERE institution_id = ?").bind(day, institutionId),
        env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, \'active\', ?, ?)').bind(crypto.randomUUID(), institutionId, institution.kind, state.status, day, 'Player-authorized crisis recovery'),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'financial_recovery', `${institution.kind} ${institutionId} recovered`, JSON.stringify({ institutionId, amount, humanId: viewer.id })),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, account.account_id, institutionId, amount, 'CREDIT', 'institution_recovery', institutionId, 'finance-v2', correlationId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'finance', 'Institution recovered', `${institution.kind} ${institutionId} returned to active status after your ${amount} Credit recovery contribution.`, institutionId),
      ]);
      return Response.json({ ok: true, institutionId, amount, status: 'active', correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/taxes/settle' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ taxableAmount?: number }>();
      const taxableAmount = Number(body.taxableAmount);
      if (!Number.isFinite(taxableAmount) || taxableAmount <= 0) return Response.json({ ok: false, error: 'Taxable amount must be positive' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => settleTaxPostgres(repository, viewer.id, taxableAmount));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Tax settlement failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
        }
      }
      const account = await env.DB.prepare('SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewer.id, 'CREDIT').first<{ account_id: string; owner_id: string; balance: number }>();
      const accountId = account?.account_id ?? '';
      const [legacyRule, activeFinanceRule] = await Promise.all([
        env.DB.prepare('SELECT * FROM tax_rules WHERE id = ? AND active = 1').bind('TAX-OUC-BASIC').first<{ rate: number; version: number }>(),
        env.DB.prepare("SELECT value_json, version FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'finance' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string; version: number }>(),
      ]);
      if (!legacyRule || !account) return Response.json({ ok: false, error: 'Tax rule or account not found' }, { status: 404 });
      let effectiveRate = Number(legacyRule.rate);
      let effectiveVersion = Number(legacyRule.version);
      if (activeFinanceRule?.value_json) {
        try {
          const configured = JSON.parse(activeFinanceRule.value_json) as { rate?: number };
          if (typeof configured.rate === 'number' && configured.rate >= 0 && configured.rate <= 0.25) {
            effectiveRate = configured.rate;
            effectiveVersion = Number(activeFinanceRule.version);
          }
        } catch (_error) { /* retain the safe legacy rate */ }
      }
      const amount = Math.round(taxableAmount * effectiveRate * 100) / 100;
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = `TAX-${accountId}-${gameDay}-${amount.toFixed(2)}-${effectiveVersion}`;
      const priorSettlement = await env.DB.prepare("SELECT id, amount, game_day, rule_version FROM ledger_entries WHERE reason_type = 'tax_settlement' AND correlation_id = ?").bind(correlationId).first<{ id: string; amount: number; game_day: number; rule_version: string }>();
      if (priorSettlement) return Response.json({ ok: true, alreadySettled: true, amount: priorSettlement.amount, gameDay: priorSettlement.game_day, ruleVersion: priorSettlement.rule_version, correlationId, persistence: 'cloudflare-d1' });
      if (Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for tax settlement' }, { status: 409 });
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, accountId, amount),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, gameDay, accountId, 'account-ouc-treasury', amount, 'CREDIT', 'tax_settlement', accountId, `tax-v${effectiveVersion}`, correlationId),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`TAX-SETTLED-${correlationId}`, viewer.id, 'finance', 'Tax settlement recorded', `${amount} Credits were settled to the OUC treasury at rate ${(effectiveRate * 100).toFixed(2)}% (rule v${effectiveVersion}).`, correlationId),
      ]);
      return Response.json({ ok: true, amount, rate: effectiveRate, ruleVersion: effectiveVersion, correlationId, accounts: (await env.DB.prepare('SELECT * FROM account_balances WHERE account_id IN (?, ?)').bind(accountId, 'account-ouc-treasury').all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/public-spending' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) !== 'postgres' && !(await hasActiveRole(env, viewer.id, ['ROLE-CITY-MAYOR', 'ROLE-CITY-PLANNER']))) return Response.json({ ok: false, error: 'An active City Mayor or Infrastructure Planner term is required' }, { status: 403 });
      const body = await request.json<{ cityId?: string; category?: string; amount?: number; correlationId?: string }>();
      const cityId = body.cityId || 'CITY-0084';
      const category = body.category?.trim() || 'public-services';
      const amount = Number(body.amount);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Public spending amount must be positive' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => publicSpendingPostgres(repository, { actorId: viewer.id, cityId, category, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Public spending failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
        }
      }
      const priorSpending = await env.DB.prepare("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'public_spending' AND correlation_id = ?").bind(correlationId).first<{ amount: number; game_day: number }>();
      if (priorSpending) return Response.json({ ok: true, alreadyProcessed: true, amount: priorSpending.amount, gameDay: priorSpending.game_day, correlationId, persistence: 'cloudflare-d1' });
      const treasury = await env.DB.prepare('SELECT balance FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first<{ balance: number }>();
      const city = await env.DB.prepare('SELECT id FROM cities WHERE id = ?').bind(cityId).first();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      if (!treasury || Number(treasury.balance) < amount) return Response.json({ ok: false, error: 'OUC treasury cannot fund this spending' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('UPDATE cities SET treasury = treasury + ? WHERE id = ?').bind(amount, cityId),
        env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET amount = amount + excluded.amount, game_day = excluded.game_day').bind(`SPEND-${cityId}-${category}`, cityId, category, amount, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, 'account-ouc-treasury', cityId, amount, 'CREDIT', 'public_spending', cityId, 'finance-v1', correlationId),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'public_spending', `OUC funding reached ${cityId}`, JSON.stringify({ cityId, category, amount, correlationId, actorId: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'finance', 'Public spending recorded', `${amount} Credits were routed from the OUC treasury to ${cityId} for ${category}.`, correlationId),
        env.DB.prepare("INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) SELECT lower(hex(randomblob(16))), human_id, 'finance', 'City funding received', ? || ' Credits were routed to ' || ? || ' for ' || ? || '.', ? FROM memberships WHERE city_id = ? AND human_id != ?").bind(amount, cityId, category, correlationId, cityId, viewer.id),
      ]);
      return Response.json({ ok: true, amount, city: await env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind(cityId).first(), treasury: await env.DB.prepare('SELECT * FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first(), correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/book' && request.method === 'GET') {
      const postgresBook = await withRepository(env, async (repository) => {
        const [rows, trades, rule] = await Promise.all([
          repository.query("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product"),
          repository.query('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product'),
          repository.query("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1"),
        ]);
        let feeRate = 0;
        const value = rule.rows[0]?.value_json;
        if (value) {
          try {
            const parsed = typeof value === 'string' ? JSON.parse(value) : value;
            if (typeof parsed?.feeRate === 'number' && parsed.feeRate >= 0 && parsed.feeRate <= 0.05) feeRate = parsed.feeRate;
          } catch { /* invalid governance JSON keeps the safe zero fee */ }
        }
        return { book: rows.rows, trades: trades.rows, feeRate };
      });
      if (postgresBook) return Response.json({ ...postgresBook, persistence: 'planetscale-postgres' });
      const rows = await env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all();
      const trades = await env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all();
      return Response.json({ book: rows.results, trades: trades.results, feeRate: await marketFeeRate(env), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'GET') {
      const product = url.searchParams.get('product');
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listMarketOrdersPostgres(repository, product));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const query = product ? env.DB.prepare('SELECT * FROM market_orders WHERE product = ? ORDER BY created_at DESC LIMIT 100').bind(product) : env.DB.prepare('SELECT * FROM market_orders ORDER BY created_at DESC LIMIT 100');
      return Response.json({ orders: (await query.all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ humanId?: string; product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string }>();
      const humanId = viewer.id;
      const product = body.product;
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => submitMarketOrderPostgres(repository, { humanId, product: product!, side, quantity, limitPrice, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Market order failed';
          const status = /not found/i.test(message) ? 404 : /insufficient|reservation/i.test(message) ? 409 : 400;
          return Response.json({ ok: false, error: message }, { status });
        }
      }
      const priorOrder = await env.DB.prepare('SELECT * FROM market_orders WHERE human_id = ? AND correlation_id = ?').bind(humanId, correlationId).first();
      if (priorOrder) return Response.json({ ok: true, alreadyProcessed: true, order: priorOrder, correlationId, persistence: 'cloudflare-d1' });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      if (side === 'sell') {
        const inventory = await env.DB.prepare('SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = ?').bind(humanId, product).first<{ amount: number }>();
        if (!inventory || Number(inventory.amount) < quantity) return Response.json({ ok: false, error: `Insufficient ${product} inventory` }, { status: 409 });
      }
      const reservationFeeRate = side === 'buy' ? await marketFeeRate(env) : 0;
      const reservedCredits = side === 'buy' ? Math.round(quantity * limitPrice * (1 + reservationFeeRate) * 100) / 100 : 0;
      const account = side === 'buy' ? await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(humanId).first<{ account_id: string; balance: number }>() : null;
      if (side === 'buy' && (!account || Number(account.balance) < reservedCredits)) return Response.json({ ok: false, error: 'Insufficient Credits to reserve this order' }, { status: 409 });
      const orderId = crypto.randomUUID();
      await env.DB.batch([
        ...(side === 'sell' ? [env.DB.prepare('UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = ? AND amount >= ?').bind(quantity, humanId, product, quantity)] : [env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(reservedCredits, account!.account_id, reservedCredits)]),
        env.DB.prepare('INSERT INTO market_orders (id, human_id, product, side, quantity, limit_price, reserved_credits, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').bind(orderId, humanId, product, side, quantity, limitPrice, reservedCredits, correlationId),
        env.DB.prepare(`UPDATE market_prices SET ${side === 'sell' ? 'supply' : 'demand'} = ${side === 'sell' ? 'supply' : 'demand'} + ? WHERE product = ?`).bind(quantity, product),
      ]);
      const coordinator = env.MARKET_COORDINATOR.getByName(`market-${product}`);
      const coordination = await coordinator.submitCommand({ type: 'order.submitted', orderId, product, quantity });
      return Response.json({ ok: true, order: await env.DB.prepare('SELECT * FROM market_orders WHERE id = ?').bind(orderId).first(), coordination, correlationId, persistence: 'cloudflare-d1' });
    }
    const cancelOrderMatch = url.pathname.match(/^\/api\/market\/orders\/([^/]+)$/);
    if (cancelOrderMatch && request.method === 'DELETE') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => cancelMarketOrderPostgres(repository, { orderId: cancelOrderMatch[1], humanId: viewer.id }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market order cancellation failed' }, { status: 404 });
        }
      }
      const order = await env.DB.prepare("SELECT * FROM market_orders WHERE id = ? AND human_id = ? AND status IN ('open','partial')").bind(cancelOrderMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!order) return Response.json({ ok: false, error: 'Open order not found for this Human' }, { status: 404 });
      const remaining = Number(order.quantity) - Number(order.filled_quantity);
      const release = String(order.side) === 'sell'
        ? env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(viewer.id, order.product, remaining)
        : env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(Number(order.reserved_credits ?? 0), viewer.id);
      const signal = String(order.side) === 'sell' ? 'supply' : 'demand';
      await env.DB.batch([
        release,
        env.DB.prepare("UPDATE market_orders SET status = 'cancelled', reserved_credits = 0 WHERE id = ? AND human_id = ?").bind(order.id, viewer.id),
        env.DB.prepare(`UPDATE market_prices SET ${signal} = MAX(0, ${signal} - ?) WHERE product = ?`).bind(remaining, order.product),
      ]);
      return Response.json({ ok: true, orderId: order.id, released: remaining, side: order.side, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/settle' && request.method === 'POST') {
      const body = await request.json<{ product?: string }>();
      const product = body.product;
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '')) return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => settleMarketPostgres(repository, product!));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market settlement failed' }, { status: 409 });
        }
      }
      const price = await env.DB.prepare('SELECT * FROM market_prices WHERE product = ?').bind(product).first<{ price: number; supply: number }>();
      const orderOrder = (await marketFairAllocation(env)) ? 'filled_quantity ASC, created_at ASC' : 'created_at ASC';
      const buy = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'buy' AND status IN ('open','partial') AND limit_price >= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
      const sell = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'sell' AND status IN ('open','partial') AND limit_price <= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
      if (!price || !buy || !sell || String(buy.human_id) === String(sell.human_id)) return Response.json({ ok: true, filled: false, reason: 'No eligible matched orders or price', persistence: 'cloudflare-d1' });
      const remaining = Math.min(Number(buy.quantity) - Number(buy.filled_quantity), Number(sell.quantity) - Number(sell.filled_quantity));
      const fill = Math.min(remaining, Number(price.supply));
      if (fill <= 0) return Response.json({ ok: true, filled: false, reason: 'No available supply', persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ?').bind(buy.human_id).first<{ account_id: string; balance: number }>();
      const total = Math.round(fill * Number(price.price) * 100) / 100;
      const feeRate = await marketFeeRate(env);
      const fee = Math.round(total * feeRate * 100) / 100;
      const payable = total + fee;
      const reserved = Number(buy.reserved_credits ?? 0);
      if (!account || (reserved <= 0 && Number(account.balance) < payable)) {
        await env.DB.prepare("UPDATE market_orders SET status = 'rejected' WHERE id = ?").bind(buy.id).run();
        return Response.json({ ok: false, error: 'Insufficient Credits', orderId: buy.id }, { status: 409 });
      }
      const reservationUsed = reserved > 0 ? Math.round(fill * Number(buy.limit_price) * (1 + feeRate) * 100) / 100 : payable;
      const reservationRefund = Math.max(0, Math.round((reservationUsed - payable) * 100) / 100);
      if (reserved > 0 && reserved < reservationUsed) return Response.json({ ok: false, error: 'Buy order reservation is inconsistent', orderId: buy.id }, { status: 409 });
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const tradeId = crypto.randomUUID();
      const newBuyFilled = Number(buy.filled_quantity) + fill;
      const newSellFilled = Number(sell.filled_quantity) + fill;
      const buyStatus = newBuyFilled >= Number(buy.quantity) ? 'filled' : 'partial';
      const sellStatus = newSellFilled >= Number(sell.quantity) ? 'filled' : 'partial';
      await env.DB.batch([
        ...(reserved > 0 ? [env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(reservationRefund, buy.human_id)] : [env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE owner_id = ? AND balance >= ?').bind(payable, buy.human_id, payable)]),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(fee, 'account-ouc-treasury'),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE owner_id = ?').bind(total, sell.human_id),
        env.DB.prepare("UPDATE business_financials SET revenue = revenue + ?, profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(total, total, gameDay, sell.human_id),
        env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(buy.human_id, product, fill),
        env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, reserved_credits = MAX(0, reserved_credits - ?), status = ? WHERE id = ?').bind(newBuyFilled, reservationUsed, buyStatus, buy.id),
        env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, status = ? WHERE id = ?').bind(newSellFilled, sellStatus, sell.id),
        env.DB.prepare('UPDATE market_prices SET supply = supply - ?, demand = MAX(0, demand - ?), game_day = ? WHERE product = ?').bind(fill, fill, gameDay, product),
        env.DB.prepare('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(tradeId, buy.id, product, fill, price.price, gameDay),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(buy.human_id), 'market', 'Market purchase filled', `${fill} ${product} acquired at ${price.price} Credits.`, tradeId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(sell.human_id), 'market', 'Market sale filled', `${fill} ${product} sold at ${price.price} Credits.`, tradeId),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(tradeId, gameDay, buy.human_id, sell.human_id, total, 'CREDIT', 'market_trade', buy.id, 'market-v2', tradeId),
        ...(fee > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), gameDay, buy.human_id, 'account-ouc-treasury', fee, 'CREDIT', 'market_fee', buy.id, 'market-v2', tradeId)] : []),
      ]);
      return Response.json({ ok: true, filled: true, buyOrderId: buy.id, sellOrderId: sell.id, tradeId, product, quantity: fill, clearingPrice: price.price, total, fee, payable, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        await withRepository(env, (repository) => resolveProposalsPostgres(repository));
        const result = await withRepository(env, (repository) => listGovernanceProposalsPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      await resolveGovernanceProposals(env);
      const proposals = await env.DB.prepare('SELECT * FROM proposals ORDER BY closes_at ASC').all();
      const ballots = await env.DB.prepare('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice').all();
      return Response.json({ proposals: proposals.results, voteCounts: ballots.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/rules' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listGovernanceRulesPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const rules = await env.DB.prepare("SELECT * FROM governance_rules WHERE status IN ('active','superseded') ORDER BY institution_id, category, version DESC").all();
      return Response.json({ rules: rules.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ institutionId?: string; title?: string; body?: string; durationHours?: number; ruleVersionId?: string; target?: { category?: string; value?: Record<string, unknown> }; correlationId?: string }>();
      const institutionId = body.institutionId?.trim() || 'OUC-001';
      const title = body.title?.trim();
      const proposalBody = body.body?.trim();
      const durationHours = Number(body.durationHours ?? 72);
      if (!title || title.length < 8 || title.length > 140) return Response.json({ ok: false, error: 'Proposal title must be 8–140 characters' }, { status: 400 });
      if (!proposalBody || proposalBody.length < 20 || proposalBody.length > 4000) return Response.json({ ok: false, error: 'Proposal body must be 20–4000 characters' }, { status: 400 });
      if (!Number.isInteger(durationHours) || durationHours < 24 || durationHours > 168) return Response.json({ ok: false, error: 'Decision window must be between 24 and 168 hours' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        const targetCategory = body.target?.category?.trim() || null;
        const targetValue = body.target?.value ?? null;
        if (targetCategory && !['market', 'finance', 'services', 'technology'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => createProposalPostgres(repository, { humanId: human.id, institutionId, title, body: proposalBody, durationHours, ruleVersionId: body.ruleVersionId, targetCategory, targetValue, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal creation failed' }, { status: 409 });
        }
      }
      const priorProposal = await env.DB.prepare('SELECT * FROM proposals WHERE institution_id = ? AND correlation_id = ?').bind(institutionId, correlationId).first();
      if (priorProposal) return Response.json({ ok: true, alreadyProcessed: true, proposal: priorProposal, correlationId, persistence: 'cloudflare-d1' });
      const institution = await env.DB.prepare("SELECT id, kind, status FROM institutions WHERE id = ? AND kind IN ('OUC','CITY','CORPORATION')").bind(institutionId).first<{ id: string; kind: string; status: string }>();
      if (!institution) return Response.json({ ok: false, error: 'Governable institution not found' }, { status: 404 });
      if (institution.status !== 'active') return Response.json({ ok: false, error: 'Institution is not active' }, { status: 409 });
      if (!(await eligibleForInstitution(env, human.id, institutionId))) return Response.json({ ok: false, error: 'Human is not eligible to propose at this institution' }, { status: 403 });
      const rule = body.ruleVersionId
        ? await env.DB.prepare("SELECT id, status, value_json FROM governance_rules WHERE id = ? AND institution_id = ?").bind(body.ruleVersionId, institutionId).first<{ id: string; status: string; value_json: string }>()
        : await env.DB.prepare("SELECT id, status, value_json FROM governance_rules WHERE institution_id = ? AND status = 'active' ORDER BY version DESC LIMIT 1").bind(institutionId).first<{ id: string; status: string; value_json: string }>();
      if (!rule || rule.status !== 'active') return Response.json({ ok: false, error: 'An active governance rule version is required' }, { status: 409 });
      const proposalId = `P-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      let ruleConfig: Record<string, unknown> = {};
      try { ruleConfig = JSON.parse(rule.value_json ?? '{}') as Record<string, unknown>; } catch (_error) { /* use engine defaults */ }
      const quorum = Number(ruleConfig.quorum ?? 0.25);
      const approvalThreshold = Number(ruleConfig.approvalThreshold ?? 0.5);
      const implementationDelay = Number(ruleConfig.implementationDelayDays ?? 1);
      if (!(quorum > 0 && quorum <= 1) || !(approvalThreshold > 0 && approvalThreshold <= 1) || !Number.isInteger(implementationDelay) || implementationDelay < 0 || implementationDelay > 30) return Response.json({ ok: false, error: 'Governance rule parameters are invalid' }, { status: 409 });
      const targetCategory = body.target?.category?.trim() || null;
      const targetValue = body.target?.value ? JSON.stringify(body.target.value) : null;
      if (targetCategory && !['market', 'finance', 'services', 'technology'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
      if (targetValue && targetValue.length > 2000) return Response.json({ ok: false, error: 'Target rule payload is too large' }, { status: 400 });
      await env.DB.prepare("INSERT INTO proposals (id, institution_id, title, body, status, opens_at, closes_at, rule_version_id, quorum, approval_threshold, implementation_delay_days, implementation_at, target_category, target_value_json, correlation_id) VALUES (?, ?, ?, ?, 'open', CURRENT_TIMESTAMP, datetime('now', ?), ?, ?, ?, ?, datetime('now', ?), ?, ?, ?)").bind(proposalId, institutionId, title, proposalBody, `+${durationHours} hours`, rule.id, quorum, approvalThreshold, implementationDelay, `+${durationHours + implementationDelay * 24} hours`, targetCategory, targetValue, correlationId).run();
      return Response.json({ ok: true, proposal: await env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind(proposalId).first(), createdBy: human.id, correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const voteMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
    if (voteMatch && request.method === 'POST') {
      const proposalId = voteMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ vote?: string }>();
        const human = await currentHuman(request, env);
        if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
        if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => castVotePostgres(repository, { proposalId, humanId: human.id, choice: body.vote! }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Ballot failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('already') ? 409 : 403 });
        }
      }
      await resolveGovernanceProposals(env);
      const body = await request.json<{ vote?: string }>();
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const humanId = human.id;
      if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM proposals WHERE id = ? AND status = ?').bind(proposalId, 'open').first())) return Response.json({ ok: false, error: 'Open proposal not found' }, { status: 404 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const proposal = await env.DB.prepare('SELECT institution_id FROM proposals WHERE id = ?').bind(proposalId).first<{ institution_id: string }>();
      if (!(await canExerciseDelegatedRole(env, humanId, proposal?.institution_id ?? ''))) return Response.json({ ok: false, error: 'Human is not eligible to vote at this institution' }, { status: 403 });
      const weight = await votingWeight(env, humanId, proposal?.institution_id ?? '');
      try {
        await env.DB.prepare('INSERT INTO ballots (proposal_id, human_id, choice, weight) VALUES (?, ?, ?, ?)').bind(proposalId, humanId, body.vote, weight).run();
      } catch (_error) {
        return Response.json({ ok: false, error: 'Ballot already recorded' }, { status: 409 });
      }
      const counts = await env.DB.prepare('SELECT choice, ROUND(SUM(weight), 3) AS count FROM ballots WHERE proposal_id = ? GROUP BY choice').bind(proposalId).all();
      return Response.json({ ok: true, proposalId, humanId, vote: body.vote, weight, counts: counts.results, persistence: 'cloudflare-d1' });
    }
    const executeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/execute$/);
    if (executeProposalMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => executeProposalPostgres(repository, { proposalId: executeProposalMatch[1], humanId: viewer.id }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal execution failed' }, { status: 409 });
        }
      }
      const proposal = await env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind(executeProposalMatch[1]).first<Record<string, unknown>>();
      if (!proposal) return Response.json({ ok: false, error: 'Proposal not found' }, { status: 404 });
      if (proposal.outcome !== 'passed') return Response.json({ ok: false, error: 'Only passed proposals can be executed' }, { status: 409 });
      if (proposal.executed_at) return Response.json({ ok: true, executionStatus: 'executed', proposal, persistence: 'cloudflare-d1' });
      if (new Date(String(proposal.implementation_at ?? '')).getTime() > Date.now()) return Response.json({ ok: false, error: 'Implementation delay has not elapsed' }, { status: 409 });
      if (!(await canExerciseDelegatedRole(env, viewer.id, String(proposal.institution_id)))) return Response.json({ ok: false, error: 'Human is not authorized to execute this institution rule' }, { status: 403 });
      const category = String(proposal.target_category ?? '').trim();
      const valueJson = String(proposal.target_value_json ?? '');
      if (!category || !valueJson) {
        await env.DB.prepare("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = ?").bind(proposal.id).run();
        return Response.json({ ok: true, executionStatus: 'skipped', reason: 'Proposal has no target rule payload', persistence: 'cloudflare-d1' });
      }
      if (!['market', 'finance', 'services', 'technology'].includes(category) || valueJson.length > 2000) return Response.json({ ok: false, error: 'Target rule is outside engine bounds' }, { status: 409 });
      let targetValue: Record<string, unknown>;
      try { targetValue = JSON.parse(valueJson) as Record<string, unknown>; } catch (_error) { return Response.json({ ok: false, error: 'Target rule payload is invalid JSON' }, { status: 409 }); }
      if (category === 'finance' && targetValue.rate !== undefined && (!(typeof targetValue.rate === 'number') || Number(targetValue.rate) < 0 || Number(targetValue.rate) > 0.25)) return Response.json({ ok: false, error: 'Finance rule rate must be between 0 and 0.25' }, { status: 409 });
      const prior = await env.DB.prepare("SELECT version FROM governance_rules WHERE institution_id = ? AND category = ? ORDER BY version DESC LIMIT 1").bind(proposal.institution_id, category).first<{ version: number }>();
      const ruleId = `RULE-${String(proposal.institution_id)}-${category}-${Number(prior?.version ?? 0) + 1}`;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO governance_rules (id, institution_id, name, category, value_json, version, status, created_by) VALUES (?, ?, ?, ?, ?, ?, 'active', ?)").bind(ruleId, proposal.institution_id, String(proposal.title), category, JSON.stringify(targetValue), Number(prior?.version ?? 0) + 1, viewer.id),
        env.DB.prepare("UPDATE governance_rules SET status = 'superseded' WHERE institution_id = ? AND category = ? AND status = 'active'").bind(proposal.institution_id, category),
        env.DB.prepare("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'executed' WHERE id = ?").bind(proposal.id),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, (SELECT game_day FROM world_state WHERE id = \'WORLD\'), ?, ?, ?)').bind(crypto.randomUUID(), 'rule.changed', `Rule ${category} changed`, JSON.stringify({ proposalId: proposal.id, ruleId })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'governance', 'Rule executed', `Your institution executed ${category}.`, ruleId),
      ]);
      return Response.json({ ok: true, executionStatus: 'executed', rule: await env.DB.prepare('SELECT * FROM governance_rules WHERE id = ?').bind(ruleId).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/businesses' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; sector?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const sector = body.sector?.trim() ?? 'maintenance';
      const sectors = ['energy', 'extraction', 'components', 'machines', 'maintenance', 'housing', 'compute', 'r-and-d'];
      if (!name || name.length < 3 || name.length > 80 || !sectors.includes(sector)) return Response.json({ ok: false, error: 'Business name or sector is invalid' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createBusinessPostgres(repository, { ownerId: viewer.id, name, sector, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Business registration failed';
          return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /requires/i.test(message) ? 409 : 400 });
        }
      }
      const priorRegistration = await env.DB.prepare("SELECT reason_id FROM ledger_entries WHERE reason_type = 'business_registration' AND correlation_id = ?").bind(correlationId).first<{ reason_id: string }>();
      if (priorRegistration) return Response.json({ ok: true, alreadyProcessed: true, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(priorRegistration.reason_id).first(), shares: 100, correlationId, persistence: 'cloudflare-d1' });
      if (await env.DB.prepare('SELECT id FROM institutions WHERE name = ?').bind(name).first()) return Response.json({ ok: false, error: 'Business name already exists' }, { status: 409 });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      const fee = 250;
      if (!account || Number(account.balance) < fee) return Response.json({ ok: false, error: 'Business registration requires 250 Credits' }, { status: 409 });
      const businessId = `B-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(fee, account.account_id, fee),
        env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(fee),
        env.DB.prepare("INSERT INTO institutions (id, kind, name, status) VALUES (?, 'BUSINESS', ?, 'active')").bind(businessId, name),
        env.DB.prepare('INSERT INTO businesses (id, owner_id, name, policy, condition, sector) VALUES (?, ?, ?, \'reliability\', 100, ?)').bind(businessId, viewer.id, name, sector),
        env.DB.prepare('INSERT INTO business_financials (business_id, last_game_day) VALUES (?, ?)').bind(businessId, day),
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, 100)').bind(businessId, viewer.id),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, account.account_id, 'account-ouc-treasury', fee, 'CREDIT', 'business_registration', businessId, 'business-v1', correlationId),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.formed', `${name} was registered`, JSON.stringify({ businessId, sector, founder: viewer.id })),
      ]);
      return Response.json({ ok: true, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(businessId).first(), shares: 100, fee, correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    if ((url.pathname === '/api/businesses/kline-works/policy' || url.pathname === '/api/businesses/me/policy') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ policy?: string }>();
      if (!['reliability', 'margin', 'capacity'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Unknown business policy' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => setBusinessPolicyPostgres(repository, { humanId: viewer.id, policy: body.policy! }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business policy update failed' }, { status: 404 }); }
      }
      const business = await env.DB.prepare("SELECT businesses.id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.owner_id = ? OR business_management.manager_id = ? ORDER BY businesses.id LIMIT 1").bind(viewer.id, viewer.id).first<{ id: string }>();
      if (!business) return Response.json({ ok: false, error: 'No managed business is available to this Human' }, { status: 404 });
      await env.DB.prepare('UPDATE businesses SET policy = ? WHERE id = ?').bind(body.policy, business.id).run();
      return Response.json({ ok: true, policy: body.policy, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const managerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/manager$/);
    if (managerMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ managerId?: string }>();
        try {
          const result = await withRepository(env, (repository) => appointManagerPostgres(repository, { ownerId: viewer.id, businessId: managerMatch[1], managerId: body.managerId?.trim() ?? '' }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Manager appointment failed' }, { status: 403 }); }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(managerMatch[1]).first<{ id: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may appoint its manager' }, { status: 403 });
      const body = await request.json<{ managerId?: string }>();
      const managerId = body.managerId?.trim() ?? '';
      const manager = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(managerId).first();
      if (!manager) return Response.json({ ok: false, error: 'Active manager Human not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 0;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO business_management (business_id, manager_id, appointed_by, appointed_game_day) VALUES (?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET manager_id = excluded.manager_id, appointed_by = excluded.appointed_by, appointed_game_day = excluded.appointed_game_day, updated_at = CURRENT_TIMESTAMP').bind(business.id, managerId, viewer.id, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.manager_appointed', `Manager appointed for ${business.id}`, JSON.stringify({ businessId: business.id, managerId, appointedBy: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), managerId, 'governance', 'Business management appointment', `You were appointed manager of ${business.id}.`, business.id),
      ]);
      return Response.json({ ok: true, management: await env.DB.prepare('SELECT * FROM business_management WHERE business_id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const ownershipRegistryMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/ownership$/);
    if (ownershipRegistryMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => ownershipRegistryPostgres(repository, ownershipRegistryMatch[1]));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business not found' }, { status: 404 }); }
      }
      const business = await env.DB.prepare('SELECT id, name, owner_id FROM businesses WHERE id = ?').bind(ownershipRegistryMatch[1]).first<{ id: string; name: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      const holders = await env.DB.prepare('SELECT business_shares.holder_id, humans.display_name, business_shares.shares FROM business_shares JOIN humans ON humans.id = business_shares.holder_id WHERE business_shares.business_id = ? ORDER BY business_shares.shares DESC, business_shares.holder_id').bind(business.id).all<{ holder_id: string; display_name: string; shares: number }>();
      const total = holders.results.reduce((sum, holder) => sum + Number(holder.shares), 0);
      const registry = holders.results.map((holder) => ({ ...holder, percentage: total > 0 ? Math.round(Number(holder.shares) / total * 10000) / 100 : 0 }));
      return Response.json({ business, totalIssuedShares: total, controllingHumanId: registry[0]?.holder_id ?? null, holders: registry, ownershipAndManagementAreSeparate: true, persistence: 'cloudflare-d1' });
    }
    const financialsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/financials$/);
    if (financialsMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => readBusinessPostgres(repository, financialsMatch[1], viewer.id));
        if (result?.business) return Response.json({ ...result, accounting: { revenue: 'market-cleared sales and accepted contract income', operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax', profit: 'revenue minus operating costs' }, persistence: 'planetscale-postgres' });
        return Response.json({ ok: false, error: result?.error ?? 'Business financial statement is not available to this Human' }, { status: 403 });
      }
      const business = await env.DB.prepare("SELECT businesses.id, businesses.name, businesses.owner_id, businesses.status, business_financials.revenue, business_financials.operating_costs, business_financials.profit, business_financials.taxed_revenue, business_financials.last_game_day, business_financials.updated_at FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = ? AND (businesses.owner_id = ? OR business_management.manager_id = ? OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = ?))").bind(financialsMatch[1], viewer.id, viewer.id, viewer.id).first();
      if (!business) return Response.json({ ok: false, error: 'Business financial statement is not available to this Human' }, { status: 403 });
      return Response.json({ business, accounting: { revenue: 'market-cleared sales and accepted contract income', operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax', profit: 'revenue minus operating costs' }, persistence: 'cloudflare-d1' });
    }
    const constitutionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/constitution$/);
    if (constitutionMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = $1', [constitutionMatch[1]]));
        if (result?.rows[0]) return Response.json({ constitution: result.rows[0], management: { ownerId: result.rows[0].owner_id, ownershipAndManagementAreSeparate: true }, persistence: 'planetscale-postgres' });
        return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
      }
      const constitution = await env.DB.prepare('SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = ?').bind(constitutionMatch[1]).first<Record<string, unknown>>();
      if (!constitution) return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
      return Response.json({ constitution, management: { ownerId: constitution.owner_id, ownershipAndManagementAreSeparate: true }, persistence: 'cloudflare-d1' });
    }
    if (constitutionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>();
        const shareholderVoteThreshold = Number(body.shareholderVoteThreshold); const boardApprovalThreshold = Number(body.boardApprovalThreshold); const dilutionNoticeDays = Number(body.dilutionNoticeDays);
        if (!(shareholderVoteThreshold > 0 && shareholderVoteThreshold <= 1) || !(boardApprovalThreshold > 0 && boardApprovalThreshold <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 0 || dilutionNoticeDays > 30) return Response.json({ ok: false, error: 'Constitution thresholds or notice period are invalid' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => updateConstitutionPostgres(repository, { ownerId: viewer.id, businessId: constitutionMatch[1], shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Constitution update failed' }, { status: 403 }); }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(constitutionMatch[1]).first<{ id: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may update its constitution' }, { status: 403 });
      const body = await request.json<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>();
      const shareholderVoteThreshold = Number(body.shareholderVoteThreshold);
      const boardApprovalThreshold = Number(body.boardApprovalThreshold);
      const dilutionNoticeDays = Number(body.dilutionNoticeDays);
      if (!(shareholderVoteThreshold > 0 && shareholderVoteThreshold <= 1) || !(boardApprovalThreshold > 0 && boardApprovalThreshold <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 0 || dilutionNoticeDays > 30) return Response.json({ ok: false, error: 'Constitution thresholds or notice period are invalid' }, { status: 400 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 0;
      const current = await env.DB.prepare('SELECT version FROM business_constitutions WHERE business_id = ?').bind(business.id).first<{ version: number }>();
      const version = Number(current?.version ?? 0) + 1;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO business_constitutions (business_id, version, shareholder_vote_threshold, board_approval_threshold, dilution_notice_days, updated_by, updated_game_day) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET version = excluded.version, shareholder_vote_threshold = excluded.shareholder_vote_threshold, board_approval_threshold = excluded.board_approval_threshold, dilution_notice_days = excluded.dilution_notice_days, updated_by = excluded.updated_by, updated_game_day = excluded.updated_game_day, updated_at = CURRENT_TIMESTAMP').bind(business.id, version, shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays, viewer.id, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.constitution_changed', `Business Constitution updated for ${business.id}`, JSON.stringify({ businessId: business.id, version, shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays, updatedBy: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'governance', 'Business Constitution updated', `${business.id} now operates under Constitution version ${version}.`, business.id),
      ]);
      return Response.json({ ok: true, constitution: await env.DB.prepare('SELECT * FROM business_constitutions WHERE business_id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const shareTransferMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/transfer$/);
    if (shareTransferMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ recipientId?: string; shares?: number; otp?: string; correlationId?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for ownership transfers' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const recipientId = body.recipientId?.trim() ?? '';
        const shares = Number(body.shares);
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares <= 0 || correlationId.length > 160) return Response.json({ ok: false, error: 'A valid recipient, positive whole-share amount, and correlation ID are required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => transferSharesPostgres(repository, { holderId: viewer.id, businessId: shareTransferMatch[1] === 'me' ? null : shareTransferMatch[1], recipientId, shares, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share transfer failed' }, { status: 409 });
        }
      }
      const businessId = shareTransferMatch[1] === 'me'
        ? (await env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first<{ id: string }>())?.id
        : shareTransferMatch[1];
      const recipientId = body.recipientId?.trim();
      const shares = Number(body.shares);
      if (!businessId || !recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares <= 0) return Response.json({ ok: false, error: 'A valid recipient and positive whole-share amount are required' }, { status: 400 });
      const [business, recipient, holding] = await Promise.all([
        env.DB.prepare('SELECT id FROM businesses WHERE id = ?').bind(businessId).first(),
        env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(recipientId).first(),
        env.DB.prepare('SELECT shares FROM business_shares WHERE business_id = ? AND holder_id = ?').bind(businessId, viewer.id).first<{ shares: number }>(),
      ]);
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (!recipient) return Response.json({ ok: false, error: 'Recipient Human not found' }, { status: 404 });
      if (!holding || Number(holding.shares) < shares) return Response.json({ ok: false, error: 'Insufficient shares' }, { status: 409 });
      const transferDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const senderUpdate = Number(holding.shares) === shares
        ? env.DB.prepare('DELETE FROM business_shares WHERE business_id = ? AND holder_id = ?').bind(businessId, viewer.id)
        : env.DB.prepare('UPDATE business_shares SET shares = shares - ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ? AND holder_id = ?').bind(shares, businessId, viewer.id);
      await env.DB.batch([
        senderUpdate,
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, ?) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = shares + excluded.shares, updated_at = CURRENT_TIMESTAMP').bind(businessId, recipientId, shares),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', businessId, viewer.id, recipientId, shares, 'share_transfer', businessId, transferDay),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'ownership', 'Business shares transferred', `${shares} shares in ${businessId} were transferred to ${recipientId}.`, businessId, crypto.randomUUID(), recipientId, 'ownership', 'Business shares received', `${shares} shares in ${businessId} were transferred to you by ${viewer.id}.`, businessId),
      ]);
      return Response.json({ ok: true, businessId, from: viewer.id, to: recipientId, shares, holdings: (await env.DB.prepare('SELECT holder_id, shares FROM business_shares WHERE business_id = ? ORDER BY shares DESC').bind(businessId).all()).results, persistence: 'cloudflare-d1' });
    }
    const shareIssueMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/issue$/);
    if (shareIssueMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ recipientId?: string; shares?: number; pricePerShare?: number; otp?: string; correlationId?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for share issuance' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const recipientId = body.recipientId?.trim() ?? '';
        const shares = Number(body.shares);
        const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000 || correlationId.length > 160) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => issueSharesPostgres(repository, { ownerId: viewer.id, businessId: shareIssueMatch[1], recipientId, shares, pricePerShare, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share issuance failed' }, { status: 409 });
        }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(shareIssueMatch[1]).first<{ id: string; owner_id: string }>();
      const recipientId = body.recipientId?.trim();
      const shares = Number(body.shares);
      const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
      if (!business || business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may issue shares' }, { status: 403 });
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
      const recipient = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(recipientId).first();
      if (!recipient) return Response.json({ ok: false, error: 'Recipient Human not found' }, { status: 404 });
      const buyerAccount = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(recipientId).first<{ account_id: string; balance: number }>();
      const total = Math.round(shares * pricePerShare * 100) / 100;
      if (!buyerAccount || Number(buyerAccount.balance) < total) return Response.json({ ok: false, error: 'Recipient has insufficient Credits' }, { status: 409 });
      const ownerAccount = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string }>();
      if (!ownerAccount) return Response.json({ ok: false, error: 'Owner account not found' }, { status: 404 });
      const existingHolders = (await env.DB.prepare('SELECT holder_id FROM business_shares WHERE business_id = ? AND holder_id != ?').bind(business.id, recipientId).all<{ holder_id: string }>()).results;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(total, buyerAccount.account_id, total),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(total, ownerAccount.account_id),
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, ?) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = shares + excluded.shares, updated_at = CURRENT_TIMESTAMP').bind(business.id, recipientId, shares),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, buyerAccount.account_id, ownerAccount.account_id, total, 'CREDIT', 'share_issuance', business.id, 'shares-v1', correlationId),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', business.id, business.owner_id, recipientId, shares, 'share_issuance', correlationId, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.shares_issued', `Shares issued by ${business.id}`, JSON.stringify({ businessId: business.id, recipientId, shares, pricePerShare, total })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), recipientId, 'ownership', 'Business shares received', `You acquired ${shares} shares in ${business.id}.`, business.id),
        ...existingHolders.map((holder) => env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), holder.holder_id, 'ownership', 'Business share issuance notice', `${shares} new shares were issued in ${business.id} at ${pricePerShare} Credits per share. Review your ownership percentage.`, business.id)),
      ]);
      return Response.json({ ok: true, businessId: business.id, recipientId, shares, pricePerShare, total, correlationId, holdings: (await env.DB.prepare('SELECT holder_id, shares FROM business_shares WHERE business_id = ? ORDER BY shares DESC').bind(business.id).all()).results, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => getSuccessorPostgres(repository, viewer.id));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      return Response.json({ successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/life/status' && request.method === 'GET') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => getLifeStatusPostgres(repository, viewer.id));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [human, succession, events] = await Promise.all([
        env.DB.prepare('SELECT id, display_name, age_years, life_status, death_game_day, standing, legacy FROM humans WHERE id = ?').bind(viewer.id).first(),
        env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(),
        env.DB.prepare('SELECT * FROM life_events WHERE human_id = ? ORDER BY game_day DESC LIMIT 20').bind(viewer.id).all(),
      ]);
      return Response.json({ ok: true, human, succession, events: events.results, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'POST') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; estatePeriodDays?: number; successorHumanId?: string }>();
      const successorName = body.name?.trim();
      const estatePeriodDays = Number(body.estatePeriodDays ?? 30);
      if (!successorName || successorName.length < 2) return Response.json({ ok: false, error: 'Successor name is required' }, { status: 400 });
      if (!Number.isInteger(estatePeriodDays) || estatePeriodDays < 7 || estatePeriodDays > 90) return Response.json({ ok: false, error: 'Estate period must be between 7 and 90 days' }, { status: 400 });
      const successorHumanId = body.successorHumanId?.trim() || null;
      if (authorityMode(env) === 'postgres') {
        try {
          if (viewer.life_status === 'estate') {
            if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
            const world = await withRepository(env, (repository) => repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'"));
            const day = Number(world?.rows[0]?.game_day ?? 0);
            const result = await withRepository(env, (repository) => settleInheritancePostgres(repository, { predecessorId: viewer.id, successorId: successorHumanId, successorName, day }));
            if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
          }
          const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName, estatePeriodDays, successorHumanId, currentLifeStatus: viewer.life_status }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Successor registration failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('another active') ? 400 : 409 });
        }
      }
      if (successorHumanId && (successorHumanId === viewer.id || !(await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(successorHumanId).first()))) return Response.json({ ok: false, error: 'Successor Human must be another active Human' }, { status: 400 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      if (viewer.life_status === 'estate') {
        if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
        const [account, machines, businesses, shares, resources] = await Promise.all([
          env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>(),
          env.DB.prepare('SELECT id FROM machines WHERE owner_id = ?').bind(viewer.id).all<{ id: string }>(),
          env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ?').bind(viewer.id).all<{ id: string }>(),
          env.DB.prepare('SELECT business_id, shares FROM business_shares WHERE holder_id = ?').bind(viewer.id).all<{ business_id: string; shares: number }>(),
          env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(viewer.id).all<{ resource: string; amount: number }>(),
        ]);
        const gross = Math.max(0, Number(account?.balance ?? 0));
        const tax = Math.round(gross * 0.2 * 100) / 100;
        const inherited = Math.max(0, gross - tax);
        const eventId = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare("UPDATE account_balances SET balance = 0 WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id),
          env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(inherited, successorHumanId),
          ...(tax > 0 ? [env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(tax)] : []),
          env.DB.prepare('UPDATE humans SET standing = 0, legacy = legacy + 1 WHERE id = ?').bind(successorHumanId),
          env.DB.prepare('UPDATE machines SET owner_id = ? WHERE owner_id = ?').bind(successorHumanId, viewer.id),
          env.DB.prepare('UPDATE businesses SET owner_id = ? WHERE owner_id = ?').bind(successorHumanId, viewer.id),
          env.DB.prepare('UPDATE business_shares SET holder_id = ? WHERE holder_id = ?').bind(successorHumanId, viewer.id),
          ...resources.results.map((row) => env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(successorHumanId, row.resource, row.amount)),
          env.DB.prepare('DELETE FROM resource_balances WHERE owner_id = ?').bind(viewer.id),
          env.DB.prepare("UPDATE humans SET life_status = 'deceased' WHERE id = ?").bind(viewer.id),
          env.DB.prepare('INSERT OR REPLACE INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, ? FROM humans WHERE id = ?').bind(successorName, viewer.id),
          env.DB.prepare('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES (?, ?, ?, ?, ?, ?)').bind(eventId, successorHumanId, 'inheritance', day, successorName, inherited),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, viewer.id, successorHumanId, inherited, 'CREDIT', 'late_inheritance', eventId, 'life-v2', eventId),
          ...(tax > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, viewer.id, 'account-ouc-treasury', tax, 'CREDIT', 'late_inheritance_tax', eventId, 'life-v2', eventId)] : []),
          ...machines.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', asset.id, viewer.id, successorHumanId, 1, 'late_inheritance', eventId, day)),
          ...businesses.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS', asset.id, viewer.id, successorHumanId, 1, 'late_inheritance', eventId, day)),
          ...shares.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', asset.business_id, viewer.id, successorHumanId, asset.shares, 'late_inheritance', eventId, day)),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), successorHumanId, 'life', 'Late inheritance received', `${inherited} Credits and your predecessor’s registered assets were transferred after the Estate Period.`, eventId),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`LATE-INHERITANCE-${viewer.id}-${day}`, day, 'human.life_event', 'An Estate completed late succession', JSON.stringify({ predecessor: viewer.id, successor: successorHumanId, tax })),
          env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(viewer.id),
        ]);
        return Response.json({ ok: true, lateSuccession: true, successorHumanId, inherited, tax, eventId, persistence: 'cloudflare-d1' });
      }
      await env.DB.prepare('INSERT INTO succession_plans (human_id, successor_name, registered_game_day, estate_period_days, successor_human_id) VALUES (?, ?, ?, ?, ?) ON CONFLICT(human_id) DO UPDATE SET successor_name = excluded.successor_name, registered_game_day = excluded.registered_game_day, estate_period_days = excluded.estate_period_days, successor_human_id = excluded.successor_human_id').bind(viewer.id, successorName, day, estatePeriodDays, successorHumanId).run();
      return Response.json({ ok: true, successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
    }
    const maintenanceMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/maintenance$/);
    if (maintenanceMatch && request.method === 'POST') {
      const machineId = maintenanceMatch[1];
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ amount?: number; correlationId?: string }>();
        const amount = Number(body.amount ?? 10);
        const correlationId = String(body.correlationId ?? '').trim();
        if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Maintenance amount must be positive' }, { status: 400 });
        if (!correlationId || correlationId.length > 160) return Response.json({ ok: false, error: 'A valid maintenance correlationId is required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => maintainMachinePostgres(repository, { machineId, ownerId: viewer.id, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Machine maintenance failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
        }
      }
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found' }, { status: 404 });
      if (machine.owner_id !== viewer.id) return Response.json({ ok: false, error: 'This machine belongs to another Human' }, { status: 403 });
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Number(body.amount ?? 10);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Maintenance amount must be positive' }, { status: 400 });
      const correlationId = String(body.correlationId ?? '').trim();
      if (!correlationId || correlationId.length > 160) return Response.json({ ok: false, error: 'A valid maintenance correlationId is required' }, { status: 400 });
      const existing = await env.DB.prepare('SELECT id, amount, game_day FROM maintenance_events WHERE machine_id = ? AND correlation_id = ?').bind(machineId, correlationId).first<{ id: string; amount: number; game_day: number }>();
      if (existing) return Response.json({ ok: true, alreadyProcessed: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first(), eventId: existing.id, amount: existing.amount, gameDay: existing.game_day, correlationId, persistence: 'cloudflare-d1' });
      const before = Number(machine.condition);
      const after = Math.min(100, before + amount * 0.8);
      const components = await env.DB.prepare("SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = 'components'").bind(viewer.id).first<{ amount: number }>();
      if (!components || Number(components.amount) < amount) return Response.json({ ok: false, error: 'Insufficient Components for maintenance' }, { status: 409 });
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const [componentPrice, asset] = await Promise.all([
        env.DB.prepare("SELECT price FROM market_prices WHERE product = 'components'").first<{ price: number }>(),
        env.DB.prepare('SELECT business_id FROM business_assets WHERE machine_id = ?').bind(machineId).first<{ business_id: string }>(),
      ]);
      const maintenanceCost = Math.round(amount * Number(componentPrice?.price ?? 0) * 100) / 100;
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare("UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = 'components' AND amount >= ?").bind(amount, viewer.id, amount),
        env.DB.prepare('UPDATE machines SET condition = ?, maintenance_due = MAX(0, maintenance_due - ?) WHERE id = ?').bind(after, amount, machineId),
        env.DB.prepare('INSERT INTO maintenance_events (id, machine_id, owner_id, resource, amount, condition_before, condition_after, game_day, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(eventId, machineId, machine.owner_id, 'components', amount, before, after, gameDay, correlationId),
        ...(asset?.business_id ? [env.DB.prepare('UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?').bind(maintenanceCost, maintenanceCost, gameDay, asset.business_id)] : []),
      ]);
      return Response.json({ ok: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first(), eventId, amount, gameDay, correlationId, persistence: 'cloudflare-d1' });
    }
    const decommissionMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/decommission$/);
    if (decommissionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ? AND owner_id = ?').bind(decommissionMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found for this Human' }, { status: 404 });
      const body = await request.json<{ otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for decommissioning an asset' }, { status: 401 });
      const embeddedMaterial: Record<string, number> = { extractor: 80, 'energy-array': 60, 'compute-node': 100, fabricator: 90, 'housing-fabricator': 110, 'research-cluster': 140, 'service-robot': 45 };
      const efficiency = Math.min(0.8, Math.max(0.2, 0.25 + Number(machine.condition ?? 0) / 200));
      const materialReturned = Math.round((embeddedMaterial[String(machine.machine_type)] ?? 60) * efficiency * 100) / 100;
      const componentsReturned = Math.round((Number(machine.productive_capacity ?? 1) * 25 * efficiency) * 100) / 100;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('DELETE FROM business_assets WHERE machine_id = ?').bind(machine.id),
        env.DB.prepare('DELETE FROM machines WHERE id = ? AND owner_id = ?').bind(machine.id, viewer.id),
        env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, \'material\', ?), (?, \'components\', ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(viewer.id, materialReturned, viewer.id, componentsReturned),
        env.DB.prepare('INSERT INTO recycling_events (id, machine_id, owner_id, material_returned, components_returned, efficiency, game_day) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(eventId, machine.id, viewer.id, materialReturned, componentsReturned, efficiency, day),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', machine.id, viewer.id, null, 1, 'recycling', eventId, day),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'production', 'Machine recycled', `${materialReturned} Material and ${componentsReturned} Components returned at ${Math.round(efficiency * 100)}% efficiency.`, machine.id),
      ]);
      return Response.json({ ok: true, eventId, machineId: machine.id, materialReturned, componentsReturned, efficiency, persistence: 'cloudflare-d1' });
    }
    const utilizationMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/utilization$/);
    if (utilizationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ utilization?: number }>();
        const utilization = Number(body.utilization);
        if (!Number.isInteger(utilization) || utilization < 0 || utilization > 100) return Response.json({ ok: false, error: 'Utilization must be a whole percentage from 0 to 100' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => setMachineUtilizationPostgres(repository, { machineId: utilizationMatch[1], ownerId: viewer.id, utilization }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Machine utilization update failed' }, { status: 404 });
        }
      }
      const machine = await env.DB.prepare('SELECT owner_id FROM machines WHERE id = ?').bind(utilizationMatch[1]).first<{ owner_id: string }>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found' }, { status: 404 });
      if (machine.owner_id !== viewer.id) return Response.json({ ok: false, error: 'This machine belongs to another Human' }, { status: 403 });
      const body = await request.json<{ utilization?: number }>();
      const utilization = Number(body.utilization);
      if (!Number.isInteger(utilization) || utilization < 0 || utilization > 100) return Response.json({ ok: false, error: 'Utilization must be a whole percentage from 0 to 100' }, { status: 400 });
      await env.DB.prepare('UPDATE machines SET utilization = ? WHERE id = ? AND owner_id = ?').bind(utilization, utilizationMatch[1], viewer.id).run();
      return Response.json({ ok: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(utilizationMatch[1]).first(), persistence: 'cloudflare-d1' });
    }
    const upgradeMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/upgrade$/);
    if (upgradeMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ otp?: string; correlationId?: string }>();
        if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine upgrades' }, { status: 401 });
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (correlationId.length > 160) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => upgradeMachinePostgres(repository, { machineId: upgradeMatch[1], ownerId: viewer.id, correlationId, creditCost: 600, componentsCost: 20 }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Machine upgrade failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
        }
      }
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ? AND owner_id = ?').bind(upgradeMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found for this Human' }, { status: 404 });
      const body = await request.json<{ otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine upgrades' }, { status: 401 });
      const creditCost = 600;
      const componentsCost = 20;
      const capacityBefore = Number(machine.productive_capacity ?? 1);
      if (capacityBefore >= 5) return Response.json({ ok: false, error: 'Machine has reached the engine upgrade ceiling' }, { status: 409 });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      const components = await env.DB.prepare("SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = 'components'").bind(viewer.id).first<{ amount: number }>();
      if (!account || Number(account.balance) < creditCost) return Response.json({ ok: false, error: 'Insufficient Credits for machine upgrade' }, { status: 409 });
      if (!components || Number(components.amount) < componentsCost) return Response.json({ ok: false, error: 'Insufficient Components for machine upgrade' }, { status: 409 });
      const capacityAfter = Math.min(5, Math.round((capacityBefore + 0.2) * 100) / 100);
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(creditCost, account.account_id, creditCost),
        env.DB.prepare("UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = 'components' AND amount >= ?").bind(componentsCost, viewer.id, componentsCost),
        env.DB.prepare('UPDATE machines SET productive_capacity = ?, condition = MAX(0, condition - 5) WHERE id = ? AND owner_id = ?').bind(capacityAfter, machine.id, viewer.id),
        env.DB.prepare('INSERT INTO machine_upgrade_events (id, machine_id, owner_id, credit_cost, components_cost, capacity_before, capacity_after, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').bind(eventId, machine.id, viewer.id, creditCost, componentsCost, capacityBefore, capacityAfter, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, account.account_id, 'account-ouc-treasury', creditCost, 'CREDIT', 'machine_upgrade', machine.id, 'machine-v2', eventId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'production', 'Machine upgraded', `${machine.name} capacity increased to ${capacityAfter}; condition requires maintenance after installation.`, machine.id),
      ]);
      return Response.json({ ok: true, eventId, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machine.id).first(), creditCost, componentsCost, persistence: 'cloudflare-d1' });
    }
    const saleMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/sell$/);
    if (saleMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ buyerId?: string; price?: number; otp?: string; correlationId?: string }>();
        const buyerId = body.buyerId?.trim();
        const price = Math.round(Number(body.price) * 100) / 100;
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!buyerId || buyerId === viewer.id || !Number.isFinite(price) || price <= 0 || price > 1000000) return Response.json({ ok: false, error: 'Buyer and sale price are invalid' }, { status: 400 });
        if (correlationId.length > 160) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
        if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine sale' }, { status: 401 });
        try {
          const result = await withRepository(env, (repository) => sellMachinePostgres(repository, { machineId: saleMatch[1], sellerId: viewer.id, buyerId, price, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Machine sale failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
        }
      }
      const body = await request.json<{ buyerId?: string; price?: number; otp?: string }>();
      const buyerId = body.buyerId?.trim();
      const price = Math.round(Number(body.price) * 100) / 100;
      if (!buyerId || buyerId === viewer.id || !Number.isFinite(price) || price <= 0 || price > 1000000) return Response.json({ ok: false, error: 'Buyer and sale price are invalid' }, { status: 400 });
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine sale' }, { status: 401 });
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ? AND owner_id = ?').bind(saleMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found for this Human' }, { status: 404 });
      const buyer = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(buyerId).first();
      const buyerAccount = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(buyerId).first<{ account_id: string; balance: number }>();
      const sellerAccount = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string }>();
      if (!buyer || !buyerAccount || !sellerAccount) return Response.json({ ok: false, error: 'Active buyer account not found' }, { status: 404 });
      if (Number(buyerAccount.balance) < price) return Response.json({ ok: false, error: 'Buyer has insufficient Credits' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const saleId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(price, buyerAccount.account_id, price),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(price, sellerAccount.account_id),
        env.DB.prepare('UPDATE machines SET owner_id = ? WHERE id = ? AND owner_id = ?').bind(buyerId, machine.id, viewer.id),
        env.DB.prepare('DELETE FROM business_assets WHERE machine_id = ?').bind(machine.id),
        env.DB.prepare("INSERT INTO business_assets (business_id, machine_id, assigned_game_day, assigned_by) SELECT id, ?, ?, 'secondary-sale' FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1").bind(machine.id, day, buyerId),
        env.DB.prepare('INSERT INTO machine_sales (id, machine_id, seller_id, buyer_id, price, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(saleId, machine.id, viewer.id, buyerId, price, day),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', machine.id, viewer.id, buyerId, 1, 'secondary_sale', saleId, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, buyerAccount.account_id, sellerAccount.account_id, price, 'CREDIT', 'machine_sale', machine.id, 'machine-v2', saleId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'market', 'Machine sold', `${machine.name} sold for ${price} Credits.`, machine.id, crypto.randomUUID(), buyerId, 'market', 'Machine acquired', `${machine.name} acquired for ${price} Credits.`, machine.id),
      ]);
      return Response.json({ ok: true, saleId, machineId: machine.id, buyerId, price, persistence: 'cloudflare-d1' });
    }
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    if (authorityMode(env) === 'postgres') {
      const result = await withRepository(env, async (repository) => {
        await resolveProposalsPostgres(repository);
        const world = await advanceWorldPostgres(repository, 5, String(_event.scheduledTime));
        const delivered = await deliverOutbox(repository, (event) => env.MARKET_COORDINATOR.getByName('events-global').broadcast(event.payload));
        return { ...world, outboxDelivered: delivered };
      });
      if (result) {
        await env.MARKET_COORDINATOR.getByName('events-global').broadcast({ type: result.newDay ? 'world_day_started' : 'world_tick', gameDay: result.day, gameMinute: result.minute, productionEvents: result.productionEvents, marketSettlements: result.marketSettlements, at: new Date().toISOString() });
        return;
      }
    }
    await resolveGovernanceProposals(env);
    const currentDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
    await completeNegotiatedContracts(env, currentDay);
    const expiringRoles = (await env.DB.prepare("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= ?").bind(currentDay).all<{ id: string; human_id: string; institution_id: string; role_id: string }>()).results;
    await env.DB.prepare("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= ?").bind(currentDay).run();
    if (expiringRoles.length) {
      await env.DB.batch(expiringRoles.flatMap((role) => [
        env.DB.prepare('INSERT OR IGNORE INTO authority_events (id, human_id, institution_id, role_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), role.human_id, role.institution_id, role.role_id, 'expired', currentDay, 'term_completed'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${currentDay}`, role.human_id, 'governance', 'Role term completed', `Your term for role ${role.role_id} has ended. You may claim an eligible role again when available.`, role.role_id),
      ]));
    }
    const world = await env.DB.prepare('SELECT game_day, game_minute FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number; game_minute: number }>();
    const minute = Number(world?.game_minute ?? 0) + 5;
    const day = Number(world?.game_day ?? 184) + (minute >= 1440 ? 1 : 0);
    const newDay = minute >= 1440;
    await completeNegotiatedContracts(env, day);
    await env.DB.batch([
      env.DB.prepare('UPDATE world_state SET game_day = ?, game_minute = ? WHERE id = ?').bind(day, minute % 1440, 'WORLD'),
      env.DB.prepare("UPDATE machines SET condition = MAX(0, condition - MAX(0.05, utilization * 0.005 * CASE COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC LIMIT 1), 'efficiency') WHEN 'durability' THEN 0.7 WHEN 'safety' THEN 0.8 ELSE 1 END)), maintenance_due = maintenance_due + MAX(1, utilization * 0.25)"),
      env.DB.prepare("UPDATE market_prices SET price = MAX(1, ROUND(price * (1 + MIN(0.05, MAX(-0.05, (demand - supply) / MAX(1, supply + demand)))) , 2)), game_day = ?").bind(day),
      env.DB.prepare("UPDATE world_state SET health = CAST(MAX(0, MIN(100, (SELECT COALESCE(AVG(condition), 68) FROM machines) * (SELECT COALESCE(MIN(MIN(1, housing_capacity / MAX(1, residents)), MIN(1, energy_capacity / MAX(1, residents)), MIN(1, connectivity_capacity / MAX(1, residents)), MIN(1, health_capacity / 100.0)), 0) FROM cities))) AS INTEGER) WHERE id = 'WORLD'"),
      ...(minute >= 1440 ? [
        env.DB.prepare("UPDATE cities SET housing_capacity = housing_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000), energy_capacity = energy_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000), connectivity_capacity = connectivity_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000), health_capacity = health_capacity + MIN(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000)"),
        env.DB.prepare("UPDATE budgets SET amount = MAX(0, amount - 100), game_day = ? WHERE amount > 0").bind(day),
      ] : []),
      env.DB.prepare("UPDATE world_state SET living_cost_index = ROUND(MAX(0.5, MIN(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50)), 3), essential_services_index = ROUND(MAX(0, MIN(1, (SELECT COALESCE(MIN(MIN(1, housing_capacity / MAX(1, residents)), MIN(1, energy_capacity / MAX(1, residents)), MIN(1, connectivity_capacity / MAX(1, residents)), MIN(1, health_capacity / 100.0)), 0) FROM cities))), 3) WHERE id = 'WORLD'"),
      env.DB.prepare("UPDATE cities SET health_capacity = CAST(MAX(0, MIN(100, MAX(health_capacity, (SELECT health FROM world_state WHERE id = 'WORLD')))) AS INTEGER)"),
      env.DB.prepare("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND closes_at <= CURRENT_TIMESTAMP"),
      ...(minute >= 1440 ? [
        env.DB.prepare("UPDATE research_projects SET progress = MIN(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'"),
        env.DB.prepare("UPDATE technologies SET progress = MIN(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)"),
      ] : []),
      ...(day % 365 === 0 && newDay ? [env.DB.prepare("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active'")]: []),
    ]);
    if (newDay) {
      await settleBusinessDepreciation(env, day);
      await settleBusinessTaxes(env, day);
      await settleBasicLevies(env, day);
      const [businessRows, cityRows, corporationRows] = await Promise.all([
        env.DB.prepare('SELECT id, condition, status FROM businesses').all<{ id: string; condition: number; status: string }>(),
        env.DB.prepare('SELECT id, treasury FROM cities').all<{ id: string; treasury: number }>(),
        env.DB.prepare('SELECT id, treasury FROM corporations').all<{ id: string; treasury: number }>(),
      ]);
      const candidates = [
        ...businessRows.results.map((row) => ({ id: row.id, kind: 'BUSINESS', value: Number(row.condition), current: row.status, distressed: Number(row.condition) <= 20, bankrupt: Number(row.condition) <= 0 })),
        ...cityRows.results.map((row) => ({ id: row.id, kind: 'CITY', value: Number(row.treasury), current: 'active', distressed: Number(row.treasury) <= 0, bankrupt: Number(row.treasury) < -1000 })),
        ...corporationRows.results.map((row) => ({ id: row.id, kind: 'CORPORATION', value: Number(row.treasury), current: 'active', distressed: Number(row.treasury) <= 0, bankrupt: Number(row.treasury) < -1000 })),
      ];
      for (const candidate of candidates) {
        const existing = await env.DB.prepare('SELECT status, since_game_day FROM financial_states WHERE institution_id = ?').bind(candidate.id).first<{ status: string; since_game_day: number }>();
        if (existing?.status === 'dissolved') continue;
        const current = existing?.status ?? candidate.current;
        if (existing?.status === 'insolvent' && day - Number(existing.since_game_day) >= 30 && (candidate.kind === 'CORPORATION' || candidate.kind === 'CITY')) {
          const members = await env.DB.prepare('SELECT human_id FROM memberships WHERE corporation_id = ? OR city_id = ?').bind(candidate.kind === 'CORPORATION' ? candidate.id : '', candidate.kind === 'CITY' ? candidate.id : '').all<{ human_id: string }>();
          await env.DB.batch([
            env.DB.prepare("UPDATE financial_states SET status = 'dissolved', recovery_game_day = ?, last_reason = 'Institution remained insolvent beyond the engine resolution window', updated_at = CURRENT_TIMESTAMP WHERE institution_id = ?").bind(day, candidate.id),
            env.DB.prepare("UPDATE institutions SET status = 'dissolved' WHERE id = ?").bind(candidate.id),
            ...(candidate.kind === 'CORPORATION' ? [env.DB.prepare('UPDATE memberships SET corporation_id = NULL WHERE corporation_id = ?').bind(candidate.id)] : [env.DB.prepare('UPDATE memberships SET city_id = NULL WHERE city_id = ?').bind(candidate.id)]),
            env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), candidate.id, candidate.kind, 'insolvent', 'dissolved', day, 'Institution remained insolvent beyond the engine resolution window'),
            env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`DISSOLVE-${candidate.id}-${day}`, day, 'institution.dissolved', `${candidate.kind} ${candidate.id} was dissolved`, JSON.stringify({ institutionId: candidate.id, releasedMembers: members.results.length })),
            ...members.results.map((member) => env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), member.human_id, 'institution', `${candidate.kind} dissolved`, `${candidate.kind} ${candidate.id} was dissolved after prolonged insolvency. Your institutional membership was released.`, candidate.id)),
          ]);
          continue;
        }
        const baseTarget = candidate.bankrupt ? 'bankrupt' : candidate.distressed ? 'distressed' : 'active';
        const target = baseTarget === 'distressed' && current === 'distressed' && day - Number(existing?.since_game_day ?? day) >= 7 ? 'insolvent' : baseTarget;
        if (target !== current) {
          const reason = target === 'active' ? 'Positive operating position restored' : candidate.bankrupt ? 'Capital or productive capacity exhausted' : 'Operating reserve is depleted';
          await env.DB.batch([
            env.DB.prepare('INSERT INTO financial_states (institution_id, institution_kind, status, since_game_day, recovery_game_day, last_reason) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(institution_id) DO UPDATE SET status = excluded.status, recovery_game_day = excluded.recovery_game_day, last_reason = excluded.last_reason, updated_at = CURRENT_TIMESTAMP').bind(candidate.id, candidate.kind, target, existing?.since_game_day ?? day, target === 'active' ? day : null, reason),
            env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), candidate.id, candidate.kind, current, target, day, reason),
            ...(candidate.kind === 'BUSINESS' ? [env.DB.prepare('UPDATE businesses SET status = ? WHERE id = ?').bind(target === 'bankrupt' ? 'bankrupt' : target === 'distressed' || target === 'insolvent' ? 'distressed' : 'active', candidate.id)] : []),
            env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`FIN-${candidate.id}-${day}-${target}`, day, 'financial_event', `${candidate.kind} ${candidate.id} is ${target}`, JSON.stringify({ institutionId: candidate.id, from: current, to: target })),
          ]);
        } else if (existing) {
          await env.DB.prepare('UPDATE financial_states SET updated_at = CURRENT_TIMESTAMP WHERE institution_id = ?').bind(candidate.id).run();
        } else {
          await env.DB.prepare('INSERT OR IGNORE INTO financial_states (institution_id, institution_kind, status, since_game_day, last_reason) VALUES (?, ?, ?, ?, ?)').bind(candidate.id, candidate.kind, target, day, 'Initial financial assessment').run();
        }
      }
      const snapshotDay = day;
      const [topCities, topCorporations] = await Promise.all([
        env.DB.prepare('SELECT id, treasury FROM cities ORDER BY treasury DESC LIMIT 10').all<{ id: string; treasury: number }>(),
        env.DB.prepare('SELECT id, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10').all<{ id: string; treasury: number }>(),
      ]);
      await env.DB.batch([
        env.DB.prepare('INSERT OR IGNORE INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`CLOCK-${snapshotDay}`, snapshotDay, 'world_clock', 'A new game day begins', JSON.stringify({ market: true, history: true })),
        ...topCities.results.map((row, index) => env.DB.prepare('INSERT OR REPLACE INTO rankings_snapshots (id, game_day, ranking_type, entity_id, rank, score) VALUES (?, ?, ?, ?, ?, ?)').bind(`CITY-${snapshotDay}-${row.id}`, snapshotDay, 'city_treasury', row.id, index + 1, row.treasury)),
        ...topCorporations.results.map((row, index) => env.DB.prepare('INSERT OR REPLACE INTO rankings_snapshots (id, game_day, ranking_type, entity_id, rank, score) VALUES (?, ?, ?, ?, ?, ?)').bind(`CORP-${snapshotDay}-${row.id}`, snapshotDay, 'corporation_treasury', row.id, index + 1, row.treasury)),
      ]);
      const maintenanceAssistants = await env.DB.prepare("SELECT ai_assistants.owner_id, machines.id AS machine_id FROM ai_assistants JOIN machines ON machines.owner_id = ai_assistants.owner_id WHERE ai_assistants.enabled = 1 AND ai_assistants.policy = 'maintenance' AND machines.maintenance_due > 0 AND machines.condition < 100").all<{ owner_id: string; machine_id: string }>();
      for (const assistant of maintenanceAssistants.results) {
        const components = await env.DB.prepare("SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = 'components'").bind(assistant.owner_id).first<{ amount: number }>();
        const amount = Math.min(5, Number(components?.amount ?? 0));
        if (amount <= 0) continue;
        await env.DB.batch([
          env.DB.prepare("UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = 'components' AND amount >= ?").bind(amount, assistant.owner_id, amount),
          env.DB.prepare('UPDATE machines SET condition = MIN(100, condition + ? * 0.8), maintenance_due = MAX(0, maintenance_due - ?) WHERE id = ? AND owner_id = ?').bind(amount, amount, assistant.machine_id, assistant.owner_id),
          env.DB.prepare('INSERT INTO maintenance_events (id, machine_id, owner_id, resource, amount, condition_before, condition_after, game_day) SELECT ?, id, owner_id, \'components\', ?, condition, MIN(100, condition + ? * 0.8), ? FROM machines WHERE id = ?').bind(crypto.randomUUID(), amount, amount, day, assistant.machine_id),
        ]);
      }
      for (const product of ['material', 'components', 'energy', 'compute']) {
        // Continue matching each product book in bounded batches.
        for (let match = 0; match < 100; match += 1) {
        const price = await env.DB.prepare('SELECT price, supply FROM market_prices WHERE product = ?').bind(product).first<{ price: number; supply: number }>();
        const orderOrder = (await marketFairAllocation(env)) ? 'filled_quantity ASC, created_at ASC' : 'created_at ASC';
        const buy = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'buy' AND status IN ('open','partial') AND limit_price >= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
        const sell = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'sell' AND status IN ('open','partial') AND limit_price <= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
        if (!price || !buy || !sell || String(buy.human_id) === String(sell.human_id)) continue;
        const fill = Math.min(Number(buy.quantity) - Number(buy.filled_quantity), Number(sell.quantity) - Number(sell.filled_quantity), Number(price.supply));
        const total = Math.round(fill * Number(price.price) * 100) / 100;
        const feeRate = await marketFeeRate(env);
        const fee = Math.round(total * feeRate * 100) / 100;
        const payable = total + fee;
        const account = await env.DB.prepare('SELECT balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(buy.human_id, 'CREDIT').first<{ balance: number }>();
        const reserved = Number(buy.reserved_credits ?? 0);
        if (fill <= 0) continue;
        if (!account || (reserved <= 0 && Number(account.balance) < payable)) {
          await env.DB.prepare("UPDATE market_orders SET status = 'rejected' WHERE id = ?").bind(buy.id).run();
          continue;
        }
        const reservationUsed = reserved > 0 ? Math.round(fill * Number(buy.limit_price) * (1 + feeRate) * 100) / 100 : payable;
        const reservationRefund = Math.max(0, Math.round((reservationUsed - payable) * 100) / 100);
        if (reserved > 0 && reserved < reservationUsed) {
          await env.DB.prepare("UPDATE market_orders SET status = 'rejected', reserved_credits = 0 WHERE id = ?").bind(buy.id).run();
          await env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(reserved, buy.human_id).run();
          continue;
        }
        const tradeId = crypto.randomUUID();
        const buyFilledQuantity = Number(buy.filled_quantity) + fill;
        const sellFilledQuantity = Number(sell.filled_quantity) + fill;
        await env.DB.batch([
          ...(reserved > 0 ? [env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(reservationRefund, buy.human_id)] : [env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE owner_id = ? AND balance >= ?').bind(payable, buy.human_id, payable)]),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(fee, 'account-ouc-treasury'),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE owner_id = ?').bind(total, sell.human_id),
          env.DB.prepare("UPDATE business_financials SET revenue = revenue + ?, profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(total, total, day, sell.human_id),
          env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(buy.human_id, product, fill),
          env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, reserved_credits = MAX(0, reserved_credits - ?), status = ? WHERE id = ?').bind(buyFilledQuantity, reservationUsed, buyFilledQuantity >= Number(buy.quantity) ? 'filled' : 'partial', buy.id),
          env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, status = ? WHERE id = ?').bind(sellFilledQuantity, sellFilledQuantity >= Number(sell.quantity) ? 'filled' : 'partial', sell.id),
          env.DB.prepare('UPDATE market_prices SET supply = supply - ?, demand = MAX(0, demand - ?), game_day = ? WHERE product = ?').bind(fill, fill, day, product),
          env.DB.prepare('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(tradeId, buy.id, product, fill, price.price, day),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(buy.human_id), 'market', 'Market purchase filled', `${fill} ${product} acquired at ${price.price} Credits.`, tradeId),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(sell.human_id), 'market', 'Market sale filled', `${fill} ${product} sold at ${price.price} Credits.`, tradeId),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(tradeId, day, buy.human_id, sell.human_id, total, 'CREDIT', 'market_trade', buy.id, 'market-v2', tradeId),
          ...(fee > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, buy.human_id, 'account-ouc-treasury', fee, 'CREDIT', 'market_fee', buy.id, 'market-v2', tradeId)] : []),
        ]);
        await env.MARKET_COORDINATOR.getByName('events-global').broadcast({ type: 'world_activity', gameDay: day, category: 'market' });
        }
      }
      const producers = await env.DB.prepare("SELECT machines.id, machines.owner_id, business_assets.business_id, machines.productive_capacity, machines.utilization, machines.condition, machines.output_resource, machines.input_resource, machines.input_per_output, COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC, started_game_day DESC LIMIT 1), 'efficiency') AS research_focus FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE machines.condition > 0 AND machines.utilization > 0").all<{ id: string; owner_id: string; business_id?: string; productive_capacity: number; utilization: number; condition: number; output_resource: string; input_resource: string; input_per_output: number; research_focus: string }>();
      for (const machine of producers.results) {
        const focus = String(machine.research_focus);
        const outputFactor = focus === 'efficiency' ? 1.1 : focus === 'cost' ? 1 : 0.9;
        const inputFactor = focus === 'cost' ? 0.85 : 1;
        const theoreticalOutput = Math.max(0, Number(machine.productive_capacity) * Number(machine.utilization) / 100 * Math.min(1, Number(machine.condition) / 100) * 2 * outputFactor);
        const inputBalance = await env.DB.prepare('SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = ?').bind(machine.owner_id, machine.input_resource).first<{ amount: number }>();
        const availableInput = Number(inputBalance?.amount ?? 0);
        const effectiveInputPerOutput = Number(machine.input_per_output) * inputFactor;
        const output = Math.round(Math.min(theoreticalOutput, effectiveInputPerOutput > 0 ? availableInput / effectiveInputPerOutput : theoreticalOutput) * 100) / 100;
        const consumedInput = Math.round(output * effectiveInputPerOutput * 100) / 100;
        const inputMarket = await env.DB.prepare('SELECT price FROM market_prices WHERE product = ?').bind(machine.input_resource).first<{ price: number }>();
        const inputCostCredits = Math.round(consumedInput * Number(inputMarket?.price ?? 0) * 100) / 100;
        if (output <= 0) continue;
        const eventId = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare('UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = ? AND amount >= ?').bind(consumedInput, machine.owner_id, machine.input_resource, consumedInput),
          env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(machine.owner_id, machine.output_resource, output),
          env.DB.prepare('INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(eventId, machine.id, machine.owner_id, machine.output_resource, output, day),
          ...(machine.business_id ? [env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ?").bind(inputCostCredits, inputCostCredits, day, machine.business_id)] : []),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), machine.owner_id, 'production', 'Production completed', `${output} ${machine.output_resource} produced by ${machine.id}.`, machine.id),
          env.DB.prepare('UPDATE businesses SET condition = MAX(0, condition - ?) WHERE owner_id = ?').bind(Math.min(2, output * 0.05), machine.owner_id),
        ]);
        await env.MARKET_COORDINATOR.getByName('events-global').broadcast({ type: 'world_activity', gameDay: day, category: 'production' });
      }
      // Settle usage-based royalties once per game day. Production events are the
      // authoritative usage signal, and the ledger correlation key makes this
      // idempotent if the scheduled invocation is retried.
      const licenses = await env.DB.prepare("SELECT technology_licenses.id, technology_licenses.licensor_id, technology_licenses.licensee_id, technology_licenses.royalty_rate FROM technology_licenses JOIN patents ON patents.id = technology_licenses.patent_id WHERE technology_licenses.status = 'active' AND patents.status = 'active' AND technology_licenses.licensor_id != technology_licenses.licensee_id").all<{ id: string; licensor_id: string; licensee_id: string; royalty_rate: number }>();
      for (const license of licenses.results) {
        const usage = await env.DB.prepare('SELECT COALESCE(SUM(amount), 0) AS amount FROM production_events WHERE owner_id = ? AND game_day = ?').bind(license.licensee_id, day).first<{ amount: number }>();
        const royalty = Math.round(Number(usage?.amount ?? 0) * Math.max(0, Number(license.royalty_rate)) * 0.1 * 100) / 100;
        if (royalty <= 0) continue;
        const correlationId = `ROYALTY-${license.id}-${day}`;
        const existingSettlement = await env.DB.prepare('SELECT id FROM ledger_entries WHERE correlation_id = ? AND reason_type = ?').bind(correlationId, 'technology_royalty').first();
        if (existingSettlement) continue;
        const buyer = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(license.licensee_id).first<{ account_id: string; balance: number }>();
        const owner = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(license.licensor_id).first<{ account_id: string }>();
        if (!buyer || !owner || Number(buyer.balance) < royalty) {
          await env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), license.licensee_id, 'technology', 'Royalty payment pending', `The ${royalty} Credit royalty for technology license ${license.id} could not be settled because your balance is insufficient.`, license.id).run();
          continue;
        }
        const ledgerId = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(royalty, buyer.account_id, royalty),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(royalty, owner.account_id),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, buyer.account_id, owner.account_id, royalty, 'CREDIT', 'technology_royalty', license.id, 'technology-v2', correlationId),
          env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(royalty, royalty, day, license.licensee_id),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), license.licensee_id, 'technology', 'Technology royalty paid', `${royalty} Credits paid for licensed technology usage.`, license.id),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), license.licensor_id, 'technology', 'Technology royalty received', `${royalty} Credits received from licensed technology usage.`, license.id),
        ]);
      }
    }
    // Keep unclaimed estates available during their configured recovery window;
    // liquidation happens only after that window expires.
    if (authorityMode(env) === 'postgres') {
      await withRepository(env, (repository) => liquidateExpiredEstatesPostgres(repository, day));
    } else {
      const expiredEstates = await env.DB.prepare("SELECT humans.id, humans.display_name, humans.standing, humans.legacy, COALESCE(account_balances.balance, 0) AS balance FROM humans JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'estate' AND humans.death_game_day + succession_plans.estate_period_days <= ?").bind(day).all<{ id: string; display_name: string; standing: number; legacy: number; balance: number }>();
      for (const estate of expiredEstates.results) {
      const liquidationId = crypto.randomUUID();
      const businesses = (await env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ?').bind(estate.id).all<{ id: string }>()).results;
      const balance = Math.max(0, Number(estate.balance ?? 0));
      await env.DB.batch([
        ...(balance > 0 ? [
          env.DB.prepare("UPDATE account_balances SET balance = 0 WHERE owner_id = ? AND currency = 'CREDIT'").bind(estate.id),
          env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(balance),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, estate.id, 'account-ouc-treasury', balance, 'CREDIT', 'estate_liquidation', estate.id, 'life-v2', liquidationId),
        ] : []),
        env.DB.prepare('DELETE FROM business_assets WHERE machine_id IN (SELECT id FROM machines WHERE owner_id = ?)').bind(estate.id),
        env.DB.prepare('DELETE FROM machines WHERE owner_id = ?').bind(estate.id),
        ...businesses.map((business) => env.DB.prepare('DELETE FROM business_shares WHERE business_id = ?').bind(business.id)),
        env.DB.prepare('DELETE FROM business_shares WHERE holder_id = ?').bind(estate.id),
        env.DB.prepare('DELETE FROM businesses WHERE owner_id = ?').bind(estate.id),
        ...businesses.map((business) => env.DB.prepare("DELETE FROM institutions WHERE id = ? AND kind = 'BUSINESS'").bind(business.id)),
        env.DB.prepare('DELETE FROM resource_balances WHERE owner_id = ?').bind(estate.id),
        env.DB.prepare("UPDATE humans SET life_status = 'deceased' WHERE id = ?").bind(estate.id),
        env.DB.prepare('INSERT OR REPLACE INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, NULL FROM humans WHERE id = ?').bind(estate.id),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`ESTATE-LIQUIDATION-${estate.id}-${day}`, day, 'human.estate_liquidated', 'An unclaimed estate was liquidated', JSON.stringify({ humanId: estate.id, credits: balance, businessCount: businesses.length })),
        env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(estate.id),
      ]);
      }
    }
    if (day % 365 === 0 && newDay) {
      const serviceIndex = Number((await env.DB.prepare('SELECT essential_services_index FROM world_state WHERE id = ?').bind('WORLD').first<{ essential_services_index: number }>())?.essential_services_index ?? 0.68);
      const mortalityAge = Math.round(90 + Math.max(-5, Math.min(5, (serviceIndex - 0.68) * 10)));
      const mortalHumans = await env.DB.prepare("SELECT humans.id, humans.age_years, humans.legacy, succession_plans.successor_name, succession_plans.successor_human_id, succession_plans.estate_period_days, COALESCE(account_balances.balance, 0) AS balance FROM humans LEFT JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'active' AND humans.age_years >= ?").bind(mortalityAge).all<{ id: string; age_years: number; legacy: number; successor_name: string | null; successor_human_id: string | null; estate_period_days: number | null; balance: number }>();
      for (const human of mortalHumans.results) {
        const eventId = crypto.randomUUID();
        const inheritanceTax = Math.round(Number(human.balance ?? 0) * 0.1 * 100) / 100;
        const inheritedCredits = Math.max(0, Number(human.balance ?? 0) - inheritanceTax);
        const successor = human.successor_human_id ? await env.DB.prepare("SELECT account_id FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.id = ? AND humans.life_status = 'active'").bind(human.successor_human_id).first<{ account_id: string }>() : null;
        const inheritedMachines = successor ? (await env.DB.prepare('SELECT id FROM machines WHERE owner_id = ?').bind(human.id).all<{ id: string }>()).results : [];
        const inheritedBusinesses = successor ? (await env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ?').bind(human.id).all<{ id: string }>()).results : [];
        const inheritedShares = successor ? (await env.DB.prepare('SELECT business_id, shares FROM business_shares WHERE holder_id = ?').bind(human.id).all<{ business_id: string; shares: number }>()).results : [];
        const releasedMemberships = (await env.DB.prepare('SELECT corporation_id, city_id FROM memberships WHERE human_id = ?').bind(human.id).first<{ corporation_id: string | null; city_id: string | null }>()) ?? { corporation_id: null, city_id: null };
        const successorResources = human.successor_human_id ? (await env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(human.id).all<{ resource: string; amount: number }>()).results : [];
        const inheritanceStatements = successor ? [
          env.DB.prepare('UPDATE account_balances SET balance = 0 WHERE owner_id = ? AND currency = \'CREDIT\'').bind(human.id),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = \'CREDIT\'').bind(inheritedCredits, human.successor_human_id),
          env.DB.prepare('UPDATE humans SET legacy = legacy + ? WHERE id = ?').bind(Number(human.legacy ?? 0) + (Number(human.balance ?? 0) > 0 ? 1 : 0), human.successor_human_id),
          ...(inheritanceTax > 0 ? [env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = \'account-ouc-treasury\'').bind(inheritanceTax)] : []),
          env.DB.prepare('UPDATE machines SET owner_id = ? WHERE owner_id = ?').bind(human.successor_human_id, human.id),
          env.DB.prepare('UPDATE businesses SET owner_id = ? WHERE owner_id = ?').bind(human.successor_human_id, human.id),
          env.DB.prepare('UPDATE business_shares SET holder_id = ? WHERE holder_id = ?').bind(human.successor_human_id, human.id),
          ...inheritedMachines.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', asset.id, human.id, human.successor_human_id, 1, 'inheritance', eventId, day)),
          ...inheritedBusinesses.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS', asset.id, human.id, human.successor_human_id, 1, 'inheritance', eventId, day)),
          ...inheritedShares.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', asset.business_id, human.id, human.successor_human_id, asset.shares, 'inheritance', eventId, day)),
          ...successorResources.map((row) => env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(human.successor_human_id, row.resource, row.amount)),
          ...(successorResources.length ? [env.DB.prepare('DELETE FROM resource_balances WHERE owner_id = ?').bind(human.id)] : []),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, human.id, human.successor_human_id, inheritedCredits, 'CREDIT', 'inheritance', eventId, 'life-v2', eventId),
          ...(inheritanceTax > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, human.id, 'account-ouc-treasury', inheritanceTax, 'CREDIT', 'inheritance_tax', eventId, 'life-v2', eventId)] : []),
          env.DB.prepare('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), human.successor_human_id, 'inheritance', day, human.successor_name, inheritedCredits),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), human.successor_human_id, 'life', 'Inheritance received', `${inheritedCredits} Credits and productive assets were transferred from your predecessor.`, eventId),
        ] : [];
        await env.DB.batch([
          ...inheritanceStatements,
          env.DB.prepare("UPDATE role_assignments SET status = 'expired' WHERE human_id = ? AND status = 'active'").bind(human.id),
          env.DB.prepare('UPDATE memberships SET city_id = NULL, corporation_id = NULL WHERE human_id = ?').bind(human.id),
          ...(releasedMemberships.corporation_id ? [env.DB.prepare('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = ?) WHERE id = ?').bind(releasedMemberships.corporation_id, releasedMemberships.corporation_id)] : []),
          ...(releasedMemberships.city_id ? [env.DB.prepare('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = ?) WHERE id = ?').bind(releasedMemberships.city_id, releasedMemberships.city_id)] : []),
          ...(releasedMemberships.corporation_id ? [env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), human.id, 'CORPORATION', releasedMemberships.corporation_id, 'released', day, 'mortality')] : []),
          ...(releasedMemberships.city_id ? [env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), human.id, 'CITY', releasedMemberships.city_id, 'released', day, 'mortality')] : []),
          env.DB.prepare("UPDATE humans SET life_status = ?, death_game_day = ? WHERE id = ?").bind(successor ? 'deceased' : 'estate', day, human.id),
          env.DB.prepare('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES (?, ?, ?, ?, ?, ?)').bind(eventId, human.id, 'death', day, human.successor_name, human.balance ?? 0),
          ...(successor ? [
            env.DB.prepare('INSERT OR REPLACE INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, ?, standing, legacy, ? FROM humans WHERE id = ?').bind(day, human.successor_name, human.id),
            env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`DEATH-${human.id}-${day}`, day, 'human.life_event', 'A Human entered the archive', JSON.stringify({ humanId: human.id, successor: human.successor_name })),
            env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(human.id),
          ] : [
            env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`ESTATE-${human.id}-${day}`, day, 'human.life_event', 'A Human entered an Estate Period', JSON.stringify({ humanId: human.id, estatePeriodDays: human.estate_period_days ?? 30 })),
            env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), human.id, 'life', 'Estate Period started', `Your estate remains available for ${human.estate_period_days ?? 30} game days before liquidation.`, human.id),
          ]),
        ]);
      }
    }
    await env.MARKET_COORDINATOR.getByName('events-global').broadcast({
      type: newDay ? 'world_day_started' : 'world_tick',
      gameDay: day,
      gameMinute: minute % 1440,
      at: new Date().toISOString(),
    });
  }
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const requestId = request.headers.get('X-Request-ID') || crypto.randomUUID();
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: {
        'Access-Control-Allow-Origin': request.headers.get('Origin') ?? '*',
        'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Expose-Headers': 'X-Request-ID',
        'Access-Control-Max-Age': '86400',
        'X-Request-ID': requestId,
      } });
    }
    const url = new URL(request.url);
    const isDataRequest = url.pathname.startsWith('/api/') || url.pathname.startsWith('/edge/') || url.pathname === '/health';
    // The handler still contains historical D1 compatibility branches. Keep
    // the provider boundary at the edge so no data request can reach one when
    // PostgreSQL is not explicitly configured as the authority.
    if (isDataRequest) authorityMode(env);
    const response = isDataRequest
      ? await worker.fetch(request, env, ctx)
      : url.pathname === '/'
        ? await env.ASSETS.fetch(new Request(new URL('/landing.html', request.url), request))
      : url.pathname === '/landing'
        ? await env.ASSETS.fetch(new Request(new URL(`/landing.html?v=${WEB_ASSET_VERSION}`, request.url), request))
      : url.pathname === '/app'
          ? await env.ASSETS.fetch(new Request(new URL(`/app.html?v=${WEB_ASSET_VERSION}`, request.url), request))
        : url.pathname.startsWith('/app/')
          ? await env.ASSETS.fetch(new Request(new URL(`${url.pathname.slice(4)}?v=${WEB_ASSET_VERSION}`, request.url), request))
          : await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    const origin = request.headers.get('Origin');
    if (origin === 'https://earth-client.pages.dev' || origin?.endsWith('.earth-client.pages.dev')) {
      headers.set('Access-Control-Allow-Origin', origin);
      headers.set('Vary', 'Origin');
    }
    headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    headers.set('Access-Control-Expose-Headers', 'X-Request-ID');
    headers.set('X-Request-ID', requestId);
    headers.set('X-EARTH-API-Version', '2026-08');
    if (response.status >= 400 && response.headers.get('content-type')?.includes('application/json')) {
      try {
        const payload = await response.clone().json() as Record<string, unknown>;
        if (payload && typeof payload === 'object') {
          const codeByStatus: Record<number, string> = {
            400: 'VALIDATION_ERROR',
            401: 'AUTHENTICATION_REQUIRED',
            403: 'FORBIDDEN',
            404: 'NOT_FOUND',
            409: 'CONFLICT',
            429: 'RATE_LIMITED',
            500: 'INTERNAL_ERROR',
            503: 'SERVICE_UNAVAILABLE',
          };
          if (typeof payload.code !== 'string' || !payload.code) payload.code = codeByStatus[response.status] ?? 'REQUEST_FAILED';
          if (typeof payload.correlationId !== 'string' || !payload.correlationId) payload.correlationId = requestId;
          headers.set('content-type', 'application/json');
          return new Response(JSON.stringify(payload), { status: response.status, statusText: response.statusText, headers });
        }
      } catch {
        // Preserve non-JSON or malformed error responses unchanged.
      }
    }
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    return worker.scheduled(event, env, ctx);
  },
};
