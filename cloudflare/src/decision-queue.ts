export type DecisionCategory =
  | 'business'
  | 'contracts'
  | 'governance'
  | 'civic'
  | 'technology'
  | 'machines'
  | 'dynasty'
  | 'market'
  | 'finance'
  | 'social';

export type DecisionRiskLevel = 'critical' | 'high' | 'medium' | 'low';

export interface DecisionQueueItem {
  id: string;
  category: DecisionCategory;
  title: string;
  whyItMatters: string;
  deadline: string;
  expectedImpact: string;
  riskLevel: DecisionRiskLevel;
  primaryActionLabel: string;
  targetSection: string;
  urgencyScore: number;
}

export interface DecisionQueueInput {
  resources?: Record<string, unknown>;
  machines?: Array<{ id: string; name?: string; condition?: unknown; utilization?: unknown; output_resource?: string }>;
  contracts?: Array<{ id: string; title?: string; status?: string; delivery_tick?: unknown; terms?: string }>;
  proposals?: Array<{ id: string; title?: string; status?: string; closes_game_day?: unknown; closes_game_minute?: unknown }>;
  technology?: { progress?: unknown; active_patents?: unknown; is_funding_open?: boolean };
  dynasty?: { successor_id?: string | null; heirloom_unlocked?: boolean; perks_available?: boolean };
  business?: { id?: string; name?: string; profit?: unknown; net_income?: unknown; condition?: unknown };
  finance?: { unpaid_tax?: unknown; status?: string; debt?: unknown };
  social?: Array<{ id: string; title?: string; status?: string; deadline_game_day?: unknown; member_status?: string }>;
  city?: { id?: string; residents?: unknown; housing_capacity?: unknown; energy_capacity?: unknown; connectivity_capacity?: unknown; health_capacity?: unknown };
  market?: Array<{ product: string; supply?: unknown; demand?: unknown; price?: unknown }>;
  gameDay?: number;
}

const num = (v: unknown): number => Number(v ?? 0);

/**
 * Generates a unified, prioritized decision queue aggregating critical
 * alerts across operational, financial, civic, and dynasty domains.
 */
export function generateDecisionQueue(input: DecisionQueueInput): DecisionQueueItem[] {
  const items: DecisionQueueItem[] = [];
  const gameDay = input.gameDay ?? 184;

  const socialDecision = (input.social ?? []).find((initiative) => initiative.member_status === 'invited' || initiative.status === 'proposed');
  if (socialDecision) items.push({
    id: `decision-social-${socialDecision.id}`, category: 'social',
    title: socialDecision.title ?? 'A social initiative needs your response',
    whyItMatters: 'Accepting builds trust and unlocks shared civic, corporate, or diplomatic outcomes.',
    deadline: socialDecision.deadline_game_day ? `By game day ${socialDecision.deadline_game_day}` : 'Before the initiative expires',
    expectedImpact: 'Shape an alliance or shared project and improve relationship standing.', riskLevel: 'medium',
    primaryActionLabel: 'Open Social Commons', targetSection: 'messages', urgencyScore: 58,
  });

  const city = input.city;
  if (city?.id) {
    const residents = Math.max(1, num(city.residents));
    const energyRatio = num(city.energy_capacity) / residents;
    const healthRatio = num(city.health_capacity) / 100;
    if (energyRatio < 1) items.push({
      id: `decision-city-energy-${city.id}`, category: 'civic',
      title: 'Your city needs an energy recovery plan',
      whyItMatters: `The grid provides ${Math.round(num(city.energy_capacity))} capacity for ${Math.round(residents)} residents.`,
      deadline: 'Before the next civic cycle',
      expectedImpact: 'Restore reliable city services and protect local production from brownouts.',
      riskLevel: energyRatio < 0.75 ? 'critical' : 'high',
      primaryActionLabel: 'Open City Projects', targetSection: 'city',
      urgencyScore: Math.round(85 + Math.max(0, 1 - energyRatio) * 15),
    });
    if (healthRatio < 0.5) items.push({
      id: `decision-city-health-${city.id}`, category: 'civic',
      title: 'Your city needs a health recovery plan',
      whyItMatters: `Health capacity is at ${Math.round(healthRatio * 100)}%; a prolonged deficit can trigger relocation pressure.`,
      deadline: 'Before the next civic cycle',
      expectedImpact: 'Raise health capacity and keep your household and workforce in place.',
      riskLevel: 'critical', primaryActionLabel: 'Open City Projects', targetSection: 'city', urgencyScore: 92,
    });
  }

  // 1. Corporation Resource Deficit / Energy Drain
  const energy = num(input.resources?.energy ?? 100);
  const materials = num(input.resources?.material ?? input.resources?.materials ?? 100);
  const profit = num(input.business?.profit ?? input.business?.net_income ?? 0);

  if (energy <= 50) {
    items.push({
      id: 'decision-corp-energy-deficit',
      category: 'business',
      title: 'Your corporation is losing energy',
      whyItMatters: 'Energy reserves are dangerously depleted; factory operations and machinery will halt if energy drops to zero.',
      deadline: energy <= 20 ? 'Immediate (Next Tick)' : 'Next Game Day',
      expectedImpact: 'Prevent emergency production blackout and avoid idle capacity penalties.',
      riskLevel: energy <= 20 ? 'critical' : 'high',
      primaryActionLabel: 'Procure Energy',
      targetSection: 'market',
      urgencyScore: 100 - energy,
    });
  } else if (materials < 25) {
    items.push({
      id: 'decision-corp-material-deficit',
      category: 'business',
      title: 'Production materials running low',
      whyItMatters: 'Manufacturing lines cannot fulfill output quotas without raw components and materials.',
      deadline: 'In 1 Game Day',
      expectedImpact: 'Keep industrial assembly lines running at 100% capacity.',
      riskLevel: 'high',
      primaryActionLabel: 'Buy Materials',
      targetSection: 'market',
      urgencyScore: 75,
    });
  } else if (profit < 0) {
    items.push({
      id: 'decision-corp-negative-cashflow',
      category: 'business',
      title: 'Corporation is operating at a net loss',
      whyItMatters: 'Operating expenses exceed daily revenues, eroding working capital.',
      deadline: 'End of Fiscal Cycle',
      expectedImpact: 'Adjust production pricing and policy to restore positive operating margins.',
      riskLevel: 'high',
      primaryActionLabel: 'Review Financials',
      targetSection: 'business',
      urgencyScore: 70,
    });
  }

  // 2. Supply / Service Contracts Expiration & Delivery
  const activeContracts = (input.contracts ?? []).filter(
    (c) => c.status === 'active' || c.status === 'pending' || c.status === 'open'
  );
  if (activeContracts.length > 0) {
    const nextContract = activeContracts[0];
    items.push({
      id: `decision-contract-expiry-${nextContract.id}`,
      category: 'contracts',
      title: 'A contract expires in 2 days',
      whyItMatters: 'Unfulfilled supply obligations risk forfeiture of escrow collateral and damage commercial reliability standing.',
      deadline: 'In 2 Game Days',
      expectedImpact: 'Fulfill shipment to unlock full credit payout and improve corporate credit score.',
      riskLevel: 'high',
      primaryActionLabel: 'Review Contract',
      targetSection: 'contracts',
      urgencyScore: 85,
    });
  }

  // 3. Unresolved Governance & Civic Referendums
  const openProposals = (input.proposals ?? []).filter((p) => p.status === 'open');
  if (openProposals.length > 0) {
    const proposal = openProposals[0];
    items.push({
      id: `decision-governance-vote-${proposal.id}`,
      category: 'governance',
      title: 'You have an unresolved governance vote',
      whyItMatters: 'A municipal referendum regarding city tax charters and public services closes this cycle.',
      deadline: 'Voting Closes Today',
      expectedImpact: 'Shape tax regulations and direct municipal infrastructure investments.',
      riskLevel: 'medium',
      primaryActionLabel: 'Cast Ballot',
      targetSection: 'civic',
      urgencyScore: 65,
    });
  }

  // 4. Machinery & Asset Maintenance
  const degradedMachines = (input.machines ?? []).filter((m) => num(m.condition) < 60);
  if (degradedMachines.length > 0) {
    const worstMachine = degradedMachines.sort((a, b) => num(a.condition) - num(b.condition))[0];
    const cond = Math.round(num(worstMachine.condition));
    items.push({
      id: `decision-machine-maintenance-${worstMachine.id}`,
      category: 'machines',
      title: 'Your machine needs maintenance',
      whyItMatters: `${worstMachine.name || 'Primary Machinery'} is at ${cond}% condition. Degraded machinery suffers severe breakdown risk and reduced output rate.`,
      deadline: 'Before Next Production Cycle',
      expectedImpact: 'Restore 100% productive capacity and prevent permanent machinery destruction.',
      riskLevel: cond < 30 ? 'critical' : 'high',
      primaryActionLabel: 'Service Machine',
      targetSection: 'business',
      urgencyScore: cond < 30 ? 95 : 80,
    });
  }

  // 5. Research & Technology Funding
  const techProgress = num(input.technology?.progress ?? 45);
  if (techProgress < 100) {
    items.push({
      id: 'decision-tech-funding-available',
      category: 'technology',
      title: 'Research funding is available',
      whyItMatters: 'Collective R&D in clean energy & automation requires capital contributions to unlock universal patents and production multipliers.',
      deadline: 'Current Research Cycle',
      expectedImpact: 'Advance global tech level and secure perpetual licensing dividend rights.',
      riskLevel: 'low',
      primaryActionLabel: 'Fund Research',
      targetSection: 'technology',
      urgencyScore: 40,
    });
  }

  // 6. Dynasty & Succession Decisions
  if (!input.dynasty?.successor_id) {
    items.push({
      id: 'decision-dynasty-successor-pending',
      category: 'dynasty',
      title: 'A dynasty decision is pending',
      whyItMatters: 'No legal successor is registered for your lineage. In the event of mortal transition, your accumulated estate faces heavy OUC liquidation penalties.',
      deadline: 'Prior to Transition',
      expectedImpact: 'Guarantee 100% generational wealth preservation and unlock family dynasty perks.',
      riskLevel: 'high',
      primaryActionLabel: 'Manage Dynasty',
      targetSection: 'dynasty',
      urgencyScore: 78,
    });
  }
  if (input.dynasty?.perks_available) {
    items.push({
      id: 'decision-dynasty-perk-available',
      category: 'dynasty',
      title: 'Legacy points can unlock a family trait',
      whyItMatters: 'A dynasty perk creates a lasting advantage for every future generation.',
      deadline: 'When legacy points are available',
      expectedImpact: 'Improve production, research, finance, or civic influence across the lineage.',
      riskLevel: 'low',
      primaryActionLabel: 'Open Dynasty',
      targetSection: 'dynasty',
      urgencyScore: 48,
    });
  }

  // 7. Finance & Outstanding Tax Settlement
  const unpaidTax = num(input.finance?.unpaid_tax ?? 0);
  if (unpaidTax > 0 || input.finance?.status === 'delinquent') {
    items.push({
      id: 'decision-finance-tax-settlement',
      category: 'finance',
      title: 'Municipal tax assessment pending settlement',
      whyItMatters: 'Unpaid civic assessments accrue compounding penalties and risk personal financial insolvency.',
      deadline: 'Fiscal Day End',
      expectedImpact: 'Clear municipal balance and maintain pristine corporate standing.',
      riskLevel: 'high',
      primaryActionLabel: 'Settle Tax',
      targetSection: 'finance',
      urgencyScore: 72,
    });
  }

  // 8. Market Arbitrage Signals
  const marketShortages = (input.market ?? []).filter(
    (p) => num(p.demand) > num(p.supply) * 1.5 && num(p.demand) > 10
  );
  if (marketShortages.length > 0) {
    const topShortage = marketShortages[0];
    items.push({
      id: `decision-market-shortage-${topShortage.product}`,
      category: 'market',
      title: `Critical ${topShortage.product.toUpperCase()} shortage on Central Market`,
      whyItMatters: `Demand exceeds supply by ${(num(topShortage.demand) / Math.max(1, num(topShortage.supply))).toFixed(1)}x; premium spot pricing is available.`,
      deadline: 'Next Batch Settlement',
      expectedImpact: 'Capture high-margin spot trade profits before market equilibrium restores.',
      riskLevel: 'medium',
      primaryActionLabel: 'Place Trade Order',
      targetSection: 'market',
      urgencyScore: 50,
    });
  }

  // Sort by urgency score descending
  return items.sort((a, b) => b.urgencyScore - a.urgencyScore);
}
