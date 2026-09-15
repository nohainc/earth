export type DecisionCategory =
  | 'organization'
  | 'governance'
  | 'civic'
  | 'technology'
  | 'house'
  | 'dynasty'
  | 'market'
  | 'finance';

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
  proposals?: Array<{ id: string; title?: string; status?: string; closes_game_day?: unknown; closes_game_minute?: unknown }>;
  technology?: { progress?: unknown; active_patents?: unknown; is_funding_open?: boolean };
  house?: { successor_id?: string | null; heirloom_unlocked?: boolean; perks_available?: boolean };
  dynasty?: { successor_id?: string | null; heirloom_unlocked?: boolean; perks_available?: boolean };
  organization?: { id?: string; name?: string; profit?: unknown; net_income?: unknown; condition?: unknown };
  finance?: { unpaid_tax?: unknown; status?: string; debt?: unknown };
  territory?: { id?: string; residents?: unknown; housing_capacity?: unknown; energy_capacity?: unknown; connectivity_capacity?: unknown; health_capacity?: unknown };
  market?: Array<{ product: string; supply?: unknown; demand?: unknown; price?: unknown }>;
  buildings?: Array<{ id: string; utilization_bps?: unknown; status?: string }>;
  needs?: Array<{ need_code: string; demand_units?: unknown; allocated_units?: unknown; shortfall_units?: unknown; risk_level?: string }>;
  gameDay?: number;
}

const num = (v: unknown): number => Number(v ?? 0);

/**
 * Generates a unified, prioritized decision queue aggregating critical
 * alerts across operational, financial, civic, and dynasty domains.
 */
export function generateDecisionQueue(input: DecisionQueueInput): DecisionQueueItem[] {
  const items: DecisionQueueItem[] = [];
  const gameDay = input.gameDay ?? 0;

  const territory = input.territory;
  if (territory?.id) {
    const residents = Math.max(1, num(territory.residents));
    const energyRatio = num(territory.energy_capacity) / residents;
    const healthRatio = num(territory.health_capacity) / 100;
    if (energyRatio < 1) items.push({
      id: `decision-territory-energy-${territory.id}`, category: 'civic',
      title: 'Your Territory needs an energy recovery plan',
      whyItMatters: `The local grid provides ${Math.round(num(territory.energy_capacity))} capacity for ${Math.round(residents)} residents.`,
      deadline: 'Before the next settlement',
      expectedImpact: 'Restore reliable local services and protect productive assets from brownouts.',
      riskLevel: energyRatio < 0.75 ? 'critical' : 'high',
      primaryActionLabel: 'Review Territory Capacity', targetSection: 'territory',
      urgencyScore: Math.round(85 + Math.max(0, 1 - energyRatio) * 15),
    });
    if (healthRatio < 0.5) items.push({
      id: `decision-territory-health-${territory.id}`, category: 'civic',
      title: 'Your Territory needs a health recovery plan',
      whyItMatters: `Health capacity is at ${Math.round(healthRatio * 100)}%; a prolonged deficit can reduce quality of life and trigger mobility pressure.`,
      deadline: 'Before the next settlement',
      expectedImpact: 'Raise health capacity and keep your household and workforce in place.',
      riskLevel: 'critical', primaryActionLabel: 'Review Territory Capacity', targetSection: 'territory', urgencyScore: 92,
    });
  }

  for (const need of input.needs ?? []) {
    const shortfall = num(need.shortfall_units);
    const level = String(need.risk_level ?? '').toLowerCase();
    if (shortfall <= 0 && level === 'normal') continue;
    const code = need.need_code.toUpperCase();
    const demand = Math.max(1, num(need.demand_units));
    const allocated = num(need.allocated_units);
    const coverage = allocated / demand;
    items.push({
      id: `decision-house-service-${code.toLowerCase()}`, category: 'house',
      title: `House ${code} access needs attention`,
      whyItMatters: `Your House received ${Math.round(allocated)} of ${Math.round(demand)} ${code} service units in the latest settlement.`,
      deadline: 'Before the next settlement',
      expectedImpact: `Improve ${code.toLowerCase()} coverage and reduce pressure on House continuity.`,
      riskLevel: level === 'critical' || coverage === 0 ? 'critical' : 'high',
      primaryActionLabel: 'Review Life & Services', targetSection: 'services',
      urgencyScore: Math.round(90 - Math.min(40, coverage * 40)),
    });
  }

  // Organization resource deficit / energy drain.
  const energy = num(input.resources?.energy);
  const materials = num(input.resources?.material ?? input.resources?.materials);
  const profit = num(input.organization?.profit ?? input.organization?.net_income ?? 0);

  if (energy <= 50) {
    items.push({
      id: 'decision-organization-energy-deficit',
      category: 'organization',
      title: 'An Organization is losing energy',
      whyItMatters: 'Energy reserves are dangerously depleted; productive operations will halt if energy drops to zero.',
      deadline: energy <= 20 ? 'Immediate' : 'Next game day',
      expectedImpact: 'Prevent an operating blackout and avoid idle capacity penalties.',
      riskLevel: energy <= 20 ? 'critical' : 'high',
      primaryActionLabel: 'Procure Energy',
      targetSection: 'market',
      urgencyScore: 100 - energy,
    });
  } else if (materials < 25) {
    items.push({
      id: 'decision-organization-material-deficit',
      category: 'organization',
      title: 'Organization materials are running low',
      whyItMatters: 'Productive operations cannot fulfill planned output without material inputs.',
      deadline: 'In 1 Game Day',
      expectedImpact: 'Keep industrial assembly lines running at 100% capacity.',
      riskLevel: 'high',
      primaryActionLabel: 'Buy Materials',
      targetSection: 'market',
      urgencyScore: 75,
    });
  } else if (profit < 0) {
    items.push({
      id: 'decision-organization-negative-cashflow',
      category: 'organization',
      title: 'Organization is operating at a net loss',
      whyItMatters: 'Operating expenses exceed daily revenues, eroding working capital.',
      deadline: 'End of Fiscal Cycle',
      expectedImpact: 'Adjust production pricing and policy to restore positive operating margins.',
      riskLevel: 'high',
      primaryActionLabel: 'Review Financials',
      targetSection: 'business',
      urgencyScore: 70,
    });
  }

  for (const building of input.buildings ?? []) {
    const utilization = num(building.utilization_bps) / 100;
    if (String(building.status ?? '').toUpperCase() === 'ACTIVE' && utilization < 75) {
      items.push({
        id: `decision-building-utilization-${building.id}`,
        category: 'organization',
        title: 'A building is operating below capacity',
        whyItMatters: `Latest settlement utilization is ${Math.round(utilization)}%; shortages or operating policy may be limiting output.`,
        deadline: 'Before the next settlement',
        expectedImpact: 'Restore productive utilization and improve operating margin.',
        riskLevel: utilization === 0 ? 'critical' : 'high',
        primaryActionLabel: 'Review Buildings',
        targetSection: 'business',
        urgencyScore: Math.round(80 - Math.min(30, utilization / 3)),
      });
    }
  }

  // 2. Unresolved Governance & Civic Referendums
  const openProposals = (input.proposals ?? []).filter((p) => String(p.status ?? '').toLowerCase() === 'open');
  if (openProposals.length > 0) {
    const proposal = openProposals[0];
    items.push({
      id: `decision-governance-vote-${proposal.id}`,
      category: 'governance',
      title: 'You have an unresolved governance vote',
      whyItMatters: 'A governance proposal closes this cycle and may change shared rules or spending priorities.',
      deadline: 'Voting Closes Today',
      expectedImpact: 'Shape the rules and shared investments that affect your House and Territory.',
      riskLevel: 'medium',
      primaryActionLabel: 'Cast Ballot',
      targetSection: 'civic',
      urgencyScore: 65,
    });
  }

  // 4. Research & Technology Funding
  const techProgress = num(input.technology?.progress);
  if (techProgress < 100) {
    items.push({
      id: 'decision-tech-funding-available',
      category: 'technology',
      title: 'Research funding is available',
      whyItMatters: 'Contributions to the current research program can unlock shared technology improvements.',
      deadline: 'Current Research Cycle',
      expectedImpact: 'Advance the technology generation and improve future productive capacity.',
      riskLevel: 'low',
      primaryActionLabel: 'Fund Research',
      targetSection: 'technology',
      urgencyScore: 40,
    });
  }

  // 6. House & Succession Decisions
  const houseData = input.house || input.dynasty;
  if (!houseData?.successor_id) {
    items.push({
      id: 'decision-house-successor-pending',
      category: 'house',
      title: 'A house decision is pending',
      whyItMatters: 'No legal successor is registered for your lineage. After mortality, you can designate an existing adult or begin a new adult through Civic Rebirth, but an unplanned estate risks liquidation and lost productive assets.',
      deadline: 'Prior to Transition',
      expectedImpact: 'Choose your continuity path early, preserve more productive assets, and keep the house eligible for family perks.',
      riskLevel: 'high',
      primaryActionLabel: 'Manage House',
      targetSection: 'house',
      urgencyScore: 78,
    });
  }
  if (houseData?.perks_available) {
    items.push({
      id: 'decision-house-perk-available',
      category: 'house',
      title: 'Legacy points can unlock a family trait',
      whyItMatters: 'A house perk creates a lasting advantage for every future generation.',
      deadline: 'When House continuity capacity is available',
      expectedImpact: 'Improve production, research, finance, or civic influence across the lineage.',
      riskLevel: 'low',
      primaryActionLabel: 'Open House',
      targetSection: 'house',
      urgencyScore: 48,
    });
  }

  // 7. Finance & Outstanding Tax Settlement
  const unpaidTax = num(input.finance?.unpaid_tax ?? 0);
  if (unpaidTax > 0 || input.finance?.status === 'delinquent') {
    items.push({
      id: 'decision-finance-tax-settlement',
      category: 'finance',
      title: 'A financial obligation needs settlement',
      whyItMatters: 'Unpaid obligations can accrue penalties and restrict your House from acting freely.',
      deadline: 'Fiscal Day End',
      expectedImpact: 'Protect House liquidity and keep your financial standing healthy.',
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
