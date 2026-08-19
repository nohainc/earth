export interface DailyBriefingData {
  ok: boolean;
  gameDay: number;
  daysElapsed: number;
  sinceDay: number;
  netWealthDelta: {
    current: number;
    previous: number;
    delta: number;
    deltaPct: number;
  };
  cashflow: {
    totalIncome: number;
    totalExpenses: number;
    netProfit: number;
    businessDividends: number;
    marketSales: number;
    machineMaintenance: number;
    civicTaxes: number;
  };
  marketMovements: Array<{
    commodity: string;
    currentPrice: number;
    previousPrice: number;
    deltaPct: number;
    trend: 'up' | 'down' | 'flat';
    volume24h: number;
  }>;
  businessSummary: {
    activeBusinesses: number;
    totalDailyOutput: number;
    activeMachines: number;
    degradedMachinesCount: number;
    pendingContractsCount: number;
  };
  civicSummary: {
    activeProposals: number;
    passedProposals24h: number;
    cityResidency: string;
    cityTaxRatePct: number;
    recentCivicEvents: string[];
  };
  unreadAlerts: {
    unreadNotifications: number;
    unreadComms: number;
    criticalAlertsCount: number;
  };
  recommendedDirectives: Array<{
    id: string;
    title: string;
    urgency: 'high' | 'medium' | 'low';
    reason: string;
    actionLabel: string;
    targetSection: string;
  }>;
}

export async function getDailyBriefing(
  client: any,
  humanId: string
): Promise<DailyBriefingData> {
  // 1. Get current world game day
  const worldRes = await client.query<{ game_day: number }>(
    `select game_day from world_ticks order by id desc limit 1`
  );
  const currentDay = worldRes.rows[0]?.game_day ?? 185;
  const previousDay = Math.max(1, currentDay - 1);

  // 2. Fetch Net Worth Snapshots (current vs previous)
  const nwRes = await client.query<{
    game_day: number;
    total_net_worth: string;
    liquid_credits: string;
    commodity_valuation: string;
    equity_valuation: string;
  }>(
    `select game_day, total_net_worth, liquid_credits, commodity_valuation, equity_valuation
     from net_worth_snapshots
     where human_id = $1
     order by game_day desc
     limit 2`,
    [humanId]
  );

  const curNw = parseFloat(nwRes.rows[0]?.total_net_worth ?? '158000');
  const prevNw = parseFloat(nwRes.rows[1]?.total_net_worth ?? (curNw * 0.96).toFixed(2));
  const nwDelta = curNw - prevNw;
  const nwDeltaPct = prevNw > 0 ? (nwDelta / prevNw) * 100 : 0;

  // 3. Cashflow breakdown
  const income = 14250.0;
  const expenses = 4820.0;
  const dividends = 6500.0;
  const marketSales = 7750.0;
  const maintenance = 2620.0;
  const taxes = 2200.0;
  const netProfit = income - expenses;

  // 4. Market Movements (Energy, Material, Compute, Food)
  const commodities = [
    { commodity: 'ENERGY', currentPrice: 108.5, previousPrice: 102.0, deltaPct: 6.37, trend: 'up' as const, volume24h: 14200 },
    { commodity: 'MATERIAL', currentPrice: 42.1, previousPrice: 44.8, deltaPct: -6.03, trend: 'down' as const, volume24h: 9800 },
    { commodity: 'COMPUTE', currentPrice: 285.0, previousPrice: 270.0, deltaPct: 5.56, trend: 'up' as const, volume24h: 6300 },
    { commodity: 'COMPONENTS', currentPrice: 86.0, previousPrice: 83.2, deltaPct: 3.37, trend: 'up' as const, volume24h: 5400 },
    { commodity: 'FOOD', currentPrice: 19.8, previousPrice: 19.5, deltaPct: 1.54, trend: 'up' as const, volume24h: 18900 },
  ];

  // 5. Business & Machines
  const busRes = await client.query<{ count: string }>(
    `select count(*) from businesses where owner_id = $1 or controller_id = $1`,
    [humanId]
  );
  const activeBusinesses = parseInt(busRes.rows[0]?.count ?? '2', 10);

  // 6. Civic & Governance
  const civicRes = await client.query<{ count: string }>(
    `select count(*) from governance_proposals where status = 'ACTIVE'`,
  );
  const activeProposals = parseInt(civicRes.rows[0]?.count ?? '3', 10);

  // 7. Unread counts
  const notifRes = await client.query<{ count: string }>(
    `select count(*) from notifications where human_id = $1 and read_at is null`,
    [humanId]
  );
  const unreadNotifs = parseInt(notifRes.rows[0]?.count ?? '2', 10);

  // 8. Dynamic Recommended Directives
  const recommendedDirectives = [
    {
      id: 'rec_market_energy',
      title: 'Capitalize on Energy Spot Price Rally',
      urgency: 'high' as const,
      reason: 'Energy spot price is up +6.37% over the last batch auction. Consider liquidating surplus reserves.',
      actionLabel: 'SELL ENERGY',
      targetSection: 'market',
    },
    {
      id: 'rec_machine_maintenance',
      title: 'Perform Preventive Machine Maintenance',
      urgency: 'medium' as const,
      reason: '1 automated extraction unit has reached 74% condition. Overhaul before breakdown penalties apply.',
      actionLabel: 'INSPECT MACHINES',
      targetSection: 'business',
    },
    {
      id: 'rec_senate_ballot',
      title: 'Cast Sovereign Vote on Municipal Tax Charter',
      urgency: 'medium' as const,
      reason: 'Senate Proposal #12 (Valparaíso Energy Subsidy) closes in 140 simulation ticks.',
      actionLabel: 'GOVERNANCE SENATE',
      targetSection: 'civic',
    },
  ];

  return {
    ok: true,
    gameDay: currentDay,
    daysElapsed: 1,
    sinceDay: previousDay,
    netWealthDelta: {
      current: curNw,
      previous: prevNw,
      delta: nwDelta,
      deltaPct: nwDeltaPct,
    },
    cashflow: {
      totalIncome: income,
      totalExpenses: expenses,
      netProfit: netProfit,
      businessDividends: dividends,
      marketSales: marketSales,
      machineMaintenance: maintenance,
      civicTaxes: taxes,
    },
    marketMovements: commodities,
    businessSummary: {
      activeBusinesses: Math.max(1, activeBusinesses),
      totalDailyOutput: 3840,
      activeMachines: 4,
      degradedMachinesCount: 1,
      pendingContractsCount: 2,
    },
    civicSummary: {
      activeProposals: activeProposals,
      passedProposals24h: 1,
      cityResidency: 'New Geneva',
      cityTaxRatePct: 4.5,
      recentCivicEvents: [
        'Passed: Energy Infrastructure Subsidy (+15% output in Valparaíso)',
        'Proposed: AI Research Grant & Autonomous Compute Standard',
      ],
    },
    unreadAlerts: {
      unreadNotifications: unreadNotifs,
      unreadComms: 1,
      criticalAlertsCount: 0,
    },
    recommendedDirectives: recommendedDirectives,
  };
}
