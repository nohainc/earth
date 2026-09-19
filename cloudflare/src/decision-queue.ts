export type DecisionCategory =
  | 'house'
  | 'buildings'
  | 'finance'
  | 'governance'
  | 'technology'
  | 'market';

export type DecisionRiskLevel = 'critical' | 'high' | 'medium' | 'low';
export type DecisionRoute =
  | 'market'
  | 'buildings'
  | 'finance'
  | 'technology'
  | 'civic'
  | 'governance'
  | 'house'
  | 'life'
  | 'citizen'
  | 'corporation';

export interface DecisionQueueItem {
  id: string;
  category: DecisionCategory;
  title: string;
  whyItMatters: string;
  deadline: string;
  expectedImpact: string;
  riskLevel: DecisionRiskLevel;
  primaryActionLabel: string;
  targetRoute: DecisionRoute;
  targetEntityId?: string;
  viewerCanAct: boolean;
  urgencyScore: number;
}

type DecisionQueueDraft = Omit<DecisionQueueItem, 'targetRoute' | 'targetEntityId' | 'viewerCanAct'> & {
  targetSection: string;
  targetEntityId?: string;
  viewerCanAct?: boolean;
};

export interface DecisionQueueInput {
  gameDay?: number;
  house?: { has_successor?: boolean };
  needs?: Array<{
    need_code: string;
    demand_units?: unknown;
    allocated_units?: unknown;
    shortfall_units?: unknown;
    risk_level?: string;
  }>;
  buildings?: Array<{
    id: string;
    catalog_code?: string;
    building_type?: string;
    status?: string;
    v5_productive_status?: string;
    utilization_bps?: unknown;
    latest_settlement_status?: string;
  }>;
  finance?: {
    unpaid_tax?: unknown;
    unpaid_obligations?: unknown;
    capacity_arrears_units?: unknown;
    delinquency_status?: string;
    status?: string;
    debt?: unknown;
  };
  proposals?: Array<{
    id: string;
    title?: string;
    action_type?: string;
    status?: string;
    viewer?: { canVote?: boolean };
  }>;
  technology?: {
    progress?: unknown;
    has_active_research?: boolean;
    available_projects_count?: number;
  };
  market?: Array<{
    product: string;
    supply?: unknown;
    demand?: unknown;
    price?: unknown;
  }>;
  orders?: {
    open_count?: unknown;
    expiring_count?: unknown;
  };
}

const num = (v: unknown): number => Number(v ?? 0);

/**
 * Generates a unified, prioritized decision queue aggregating critical
 * alerts across V5 House needs, buildings, finance/capacity, governance,
 * succession, research, and market conditions.
 */
export function generateDecisionQueue(input: DecisionQueueInput): DecisionQueueItem[] {
  const items: DecisionQueueDraft[] = [];

  // 1. House needs & basic life services
  for (const need of input.needs ?? []) {
    const shortfall = num(need.shortfall_units);
    const level = String(need.risk_level ?? '').toLowerCase();
    if (shortfall <= 0 && level === 'normal') continue;
    const code = need.need_code.toUpperCase();
    const demand = Math.max(1, num(need.demand_units));
    const allocated = num(need.allocated_units);
    const coverage = allocated / demand;
    items.push({
      id: `decision-house-service-${code.toLowerCase()}`,
      category: 'house',
      title: `House ${code} access needs attention`,
      whyItMatters: `Your House received ${Math.round(allocated)} of ${Math.round(demand)} ${code} service units in the latest settlement.`,
      deadline: 'Before the next settlement',
      expectedImpact: `Improve ${code.toLowerCase()} coverage and protect household vitality.`,
      riskLevel: level === 'critical' || coverage === 0 ? 'critical' : 'high',
      primaryActionLabel: 'Review Life & Services',
      targetSection: 'citizen',
      urgencyScore: Math.round(95 - Math.min(40, coverage * 40)),
    });
  }

  // 2. Building settlement shortfalls & degraded utilization
  for (const building of input.buildings ?? []) {
    const status = String(building.status ?? '').toUpperCase();
    const productiveStatus = String(building.v5_productive_status ?? '').toUpperCase();
    const settlementStatus = String(building.latest_settlement_status ?? '').toUpperCase();
    const utilization = num(building.utilization_bps) / 100;

    if (productiveStatus === 'SUSPENDED' || status === 'SUSPENDED') {
      items.push({
      id: `decision-building-suspended-${building.id}`,
        targetEntityId: building.id,
        category: 'buildings',
        title: 'A building is suspended from operation',
        whyItMatters: 'Productive operations are halted due to capacity delinquency or manual suspension.',
        deadline: 'Before the next settlement',
        expectedImpact: 'Restore capacity standing and reactivate building production.',
        riskLevel: 'critical',
        primaryActionLabel: 'Review Buildings',
        targetSection: 'buildings',
        urgencyScore: 94,
      });
    } else if (settlementStatus === 'SHORTFALL' || settlementStatus === 'HALTED' || (status === 'ACTIVE' && utilization < 75)) {
      items.push({
        id: `decision-building-utilization-${building.id}`,
        targetEntityId: building.id,
        category: 'buildings',
        title: 'A building is operating below capacity',
        whyItMatters: `Latest settlement utilization is ${Math.round(utilization)}%; resource shortfalls or operating conditions may be limiting output.`,
        deadline: 'Before the next settlement',
        expectedImpact: 'Supply necessary inputs and restore full productive margin.',
        riskLevel: utilization === 0 || settlementStatus === 'HALTED' ? 'critical' : 'high',
        primaryActionLabel: 'Review Buildings',
        targetSection: 'buildings',
        urgencyScore: Math.round(85 - Math.min(30, utilization / 3)),
      });
    }
  }

  // 3. Financial obligations, capacity rent arrears, and delinquency
  const finance = input.finance ?? {};
  const unpaidTax = num(finance.unpaid_tax ?? finance.unpaid_obligations ?? finance.debt ?? 0);
  const capacityArrears = num(finance.capacity_arrears_units ?? 0);
  const delinquencyStatus = String(finance.delinquency_status ?? finance.status ?? '').toUpperCase();

  if (delinquencyStatus === 'PRODUCTIVE_CAPACITY_SUSPENDED' || delinquencyStatus === 'DELINQUENT' || capacityArrears > 0) {
    items.push({
      id: 'decision-finance-capacity-arrears',
      category: 'finance',
      title: 'House capacity rent requires urgent settlement',
      whyItMatters: 'Unpaid capacity rent restricts expansion and eventually suspends productive building operations.',
      deadline: 'Before the next settlement',
      expectedImpact: 'Restore the House to good standing and safeguard productive buildings.',
      riskLevel: delinquencyStatus === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 'critical' : 'high',
      primaryActionLabel: 'Review Finance',
      targetSection: 'finance',
      urgencyScore: delinquencyStatus === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 98 : 88,
    });
  } else if (unpaidTax > 0) {
    items.push({
      id: 'decision-finance-tax-settlement',
      category: 'finance',
      title: 'A financial obligation needs settlement',
      whyItMatters: 'Outstanding obligations accrue interest and limit House liquidity.',
      deadline: 'Before the next settlement',
      expectedImpact: 'Protect House liquidity and keep your financial standing healthy.',
      riskLevel: 'high',
      primaryActionLabel: 'Settle Obligation',
      targetSection: 'finance',
      urgencyScore: 78,
    });
  }

  // 4. V5 Governance proposals open for voting
  const openProposals = (input.proposals ?? []).filter((p) => {
    const s = String(p.status ?? '').toLowerCase();
    return s === 'open' || s === 'voting';
  });
  if (openProposals.length > 0) {
    const proposal = openProposals[0];
    const proposalTitle = proposal.title ?? proposal.action_type ?? 'Governance proposal';
    items.push({
      id: `decision-governance-vote-${proposal.id}`,
      targetEntityId: proposal.id,
      category: 'governance',
      title: 'You have an unresolved governance vote',
      whyItMatters: `Proposal "${proposalTitle}" is actively voting and determines shared institutional rules and constitutional rates.`,
      deadline: 'Voting Closes Today',
      expectedImpact: 'Participate in governance to represent your House interests.',
      riskLevel: 'medium',
      primaryActionLabel: 'Cast Ballot',
      targetSection: 'governance',
      viewerCanAct: proposal.viewer?.canVote !== false,
      urgencyScore: 65,
    });
  }

  // 5. House succession plans
  const houseData = input.house;
  if (houseData?.has_successor !== true) {
    items.push({
      id: 'decision-house-successor-pending',
      category: 'house',
      title: 'A house decision is pending',
      whyItMatters: 'No legal successor is registered for your lineage. Designation ensures seamless estate continuity and prevents forfeiture of assets during generational transitions.',
      deadline: 'Prior to Transition',
      expectedImpact: 'Designate a successor to safeguard House legacy and productive assets.',
      riskLevel: 'high',
      primaryActionLabel: 'Manage House',
      targetSection: 'house',
      urgencyScore: 75,
    });
  }

  // 6. Technology & Corporation Research
  const techProgress = num(input.technology?.progress);
  if (techProgress < 100) {
    items.push({
      id: 'decision-tech-funding-available',
      category: 'technology',
      title: 'Research funding is available',
      whyItMatters: 'Advancing corporate research unlocks new building tiers, generational retrofits, and scale capabilities.',
      deadline: 'Current Research Cycle',
      expectedImpact: 'Accelerate tech research to unlock next-generation productive assets.',
      riskLevel: 'low',
      primaryActionLabel: 'Fund Research',
      targetSection: 'technology',
      urgencyScore: 45,
    });
  }

  // 7. Market conditions & supply/demand imbalances
  const marketShortages = (input.market ?? []).filter(
    (p) => num(p.demand) > num(p.supply) * 1.5 && num(p.demand) > 10,
  );
  for (const shortage of marketShortages) {
    items.push({
      id: `decision-market-shortage-${shortage.product}`,
      category: 'market',
      title: `Critical ${shortage.product.toUpperCase()} shortage on Central Market`,
      whyItMatters: `Demand exceeds supply by ${(num(shortage.demand) / Math.max(1, num(shortage.supply))).toFixed(1)}x; premium spot pricing is available.`,
      deadline: 'Next Batch Settlement',
      expectedImpact: 'Capture high-margin spot trade opportunities before market clears.',
      riskLevel: 'medium',
      primaryActionLabel: 'Place Trade Order',
      targetSection: 'market',
      urgencyScore: 50,
    });
  }

  const expiringOrders = num(input.orders?.expiring_count);
  if (expiringOrders > 0) {
    items.push({
      id: 'decision-market-orders-expiring',
      category: 'market',
      title: 'Open Market orders are nearing expiry',
      whyItMatters: `${Math.round(expiringOrders)} of your open orders expire by the next market boundary.`,
      deadline: 'Before the next batch settlement',
      expectedImpact: 'Review open orders and renew or cancel positions intentionally.',
      riskLevel: 'medium',
      primaryActionLabel: 'Review Market Orders',
      targetSection: 'market',
      urgencyScore: 55,
    });
  }

  // Sort by urgency score descending
  const allowed = new Set<DecisionRoute>([
    'market', 'buildings', 'finance', 'technology', 'civic',
    'governance', 'house', 'life', 'citizen', 'corporation',
  ]);
  return items
    .sort((a, b) => b.urgencyScore - a.urgencyScore)
    .map(({ targetSection, targetEntityId, viewerCanAct, ...item }) => {
      const normalized = targetSection;
      const targetRoute = allowed.has(normalized as DecisionRoute)
        ? normalized as DecisionRoute
        : 'house';
      return {
        ...item,
        targetRoute,
        ...(targetEntityId ? { targetEntityId } : {}),
        viewerCanAct: viewerCanAct !== false,
      };
    });
}
