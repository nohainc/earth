double _parseNum(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

class NetWealthDelta {
  final double current;
  final double previous;
  final double delta;
  final double deltaPct;

  const NetWealthDelta({
    required this.current,
    required this.previous,
    required this.delta,
    required this.deltaPct,
  });

  factory NetWealthDelta.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const NetWealthDelta(current: 0, previous: 0, delta: 0, deltaPct: 0);
    }
    return NetWealthDelta(
      current: _parseNum(json['current']),
      previous: _parseNum(json['previous']),
      delta: _parseNum(json['delta']),
      deltaPct: _parseNum(json['deltaPct']),
    );
  }
}

class FinancialCashflowDelta {
  final double totalIncome;
  final double totalExpenses;
  final double netProfit;
  final double businessDividends;
  final double marketSales;
  final double buildingUpkeep;
  final double civicTaxes;

  const FinancialCashflowDelta({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netProfit,
    required this.businessDividends,
    required this.marketSales,
    required this.buildingUpkeep,
    required this.civicTaxes,
  });

  factory FinancialCashflowDelta.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FinancialCashflowDelta(
        totalIncome: 0,
        totalExpenses: 0,
        netProfit: 0,
        businessDividends: 0,
        marketSales: 0,
        buildingUpkeep: 0,
        civicTaxes: 0,
      );
    }
    return FinancialCashflowDelta(
      totalIncome: _parseNum(json['totalIncome']),
      totalExpenses: _parseNum(json['totalExpenses']),
      netProfit: _parseNum(json['netProfit']),
      businessDividends: _parseNum(json['businessDividends']),
      marketSales: _parseNum(json['marketSales']),
      buildingUpkeep: _parseNum(json['buildingUpkeep'] ?? json['machineMaintenance']),
      civicTaxes: _parseNum(json['civicTaxes']),
    );
  }
}

class MarketMovementSummary {
  final String commodity;
  final double currentPrice;
  final double previousPrice;
  final double deltaPct;
  final String trend;
  final int volume24h;

  const MarketMovementSummary({
    required this.commodity,
    required this.currentPrice,
    required this.previousPrice,
    required this.deltaPct,
    required this.trend,
    required this.volume24h,
  });

  factory MarketMovementSummary.fromJson(Map<String, dynamic> json) {
    return MarketMovementSummary(
      commodity: json['commodity']?.toString() ?? '',
      currentPrice: _parseNum(json['currentPrice']),
      previousPrice: _parseNum(json['previousPrice']),
      deltaPct: _parseNum(json['deltaPct']),
      trend: json['trend']?.toString() ?? 'flat',
      volume24h: _parseInt(json['volume24h']),
    );
  }
}

class BusinessProductionSummary {
  final int activeBusinesses;
  final int totalDailyOutput;
  final int activeBuildings;
  final int pendingContractsCount;

  const BusinessProductionSummary({
    required this.activeBusinesses,
    required this.totalDailyOutput,
    required this.activeBuildings,
    required this.pendingContractsCount,
  });

  factory BusinessProductionSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessProductionSummary(
        activeBusinesses: 0,
        totalDailyOutput: 0,
        activeBuildings: 0,
        pendingContractsCount: 0,
      );
    }
    return BusinessProductionSummary(
      activeBusinesses: _parseInt(json['activeBusinesses']),
      totalDailyOutput: _parseInt(json['totalDailyOutput']),
      activeBuildings: _parseInt(json['activeBuildings']),
      pendingContractsCount: _parseInt(json['pendingContractsCount']),
    );
  }
}

class CivicEventSummary {
  final int activeProposals;
  final int passedProposals24h;
  final String cityResidency;
  final double cityTaxRatePct;
  final List<String> recentCivicEvents;

  const CivicEventSummary({
    required this.activeProposals,
    required this.passedProposals24h,
    required this.cityResidency,
    required this.cityTaxRatePct,
    required this.recentCivicEvents,
  });

  factory CivicEventSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CivicEventSummary(
        activeProposals: 0,
        passedProposals24h: 0,
        cityResidency: '',
        cityTaxRatePct: 0.0,
        recentCivicEvents: [],
      );
    }
    final rawEvents = json['recentCivicEvents'] as List<dynamic>? ?? [];
    return CivicEventSummary(
      activeProposals: _parseInt(json['activeProposals']),
      passedProposals24h: _parseInt(json['passedProposals24h']),
      cityResidency: json['cityResidency']?.toString() ?? 'New Geneva',
      cityTaxRatePct: _parseNum(json['cityTaxRatePct']),
      recentCivicEvents: rawEvents.map((e) => e.toString()).toList(),
    );
  }
}

class UnreadAlertsSummary {
  final int unreadNotifications;
  final int unreadComms;
  final int criticalAlertsCount;

  const UnreadAlertsSummary({
    required this.unreadNotifications,
    required this.unreadComms,
    required this.criticalAlertsCount,
  });

  factory UnreadAlertsSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UnreadAlertsSummary(
        unreadNotifications: 0,
        unreadComms: 0,
        criticalAlertsCount: 0,
      );
    }
    return UnreadAlertsSummary(
      unreadNotifications: _parseInt(json['unreadNotifications']),
      unreadComms: _parseInt(json['unreadComms']),
      criticalAlertsCount: _parseInt(json['criticalAlertsCount']),
    );
  }
}

class RecommendedDirective {
  final String id;
  final String title;
  final String urgency;
  final String reason;
  final String actionLabel;
  final String targetSection;

  const RecommendedDirective({
    required this.id,
    required this.title,
    required this.urgency,
    required this.reason,
    required this.actionLabel,
    required this.targetSection,
  });

  factory RecommendedDirective.fromJson(Map<String, dynamic> json) {
    return RecommendedDirective(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      urgency: json['urgency']?.toString() ?? 'medium',
      reason: json['reason']?.toString() ?? '',
      actionLabel: json['actionLabel']?.toString() ?? 'VIEW',
      targetSection: json['targetSection']?.toString() ?? 'command',
    );
  }
}

class DailyBriefingReport {
  final int gameDay;
  final int daysElapsed;
  final int sinceDay;
  final NetWealthDelta netWealthDelta;
  final FinancialCashflowDelta cashflow;
  final List<MarketMovementSummary> marketMovements;
  final BusinessProductionSummary businessSummary;
  final CivicEventSummary civicSummary;
  final UnreadAlertsSummary unreadAlerts;
  final List<RecommendedDirective> recommendedDirectives;

  const DailyBriefingReport({
    required this.gameDay,
    required this.daysElapsed,
    required this.sinceDay,
    required this.netWealthDelta,
    required this.cashflow,
    required this.marketMovements,
    required this.businessSummary,
    required this.civicSummary,
    required this.unreadAlerts,
    required this.recommendedDirectives,
  });

  factory DailyBriefingReport.fromJson(Map<String, dynamic> json) {
    final rawMarkets = json['marketMovements'] as List<dynamic>? ?? [];
    final rawDirectives = json['recommendedDirectives'] as List<dynamic>? ?? [];
    final rawNetWealth = json['netWealthDelta'] is Map ? Map<String, dynamic>.from(json['netWealthDelta'] as Map) : null;
    final rawCashflow = json['cashflow'] is Map ? Map<String, dynamic>.from(json['cashflow'] as Map) : null;
    final rawBusiness = json['businessSummary'] is Map ? Map<String, dynamic>.from(json['businessSummary'] as Map) : null;
    final rawCivic = json['civicSummary'] is Map ? Map<String, dynamic>.from(json['civicSummary'] as Map) : null;
    final rawAlerts = json['unreadAlerts'] is Map ? Map<String, dynamic>.from(json['unreadAlerts'] as Map) : null;

    return DailyBriefingReport(
      gameDay: _parseInt(json['gameDay']),
      daysElapsed: _parseInt(json['daysElapsed']),
      sinceDay: _parseInt(json['sinceDay']),
      netWealthDelta: NetWealthDelta.fromJson(rawNetWealth),
      cashflow: FinancialCashflowDelta.fromJson(rawCashflow),
      marketMovements: rawMarkets.map((e) => MarketMovementSummary.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      businessSummary: BusinessProductionSummary.fromJson(rawBusiness),
      civicSummary: CivicEventSummary.fromJson(rawCivic),
      unreadAlerts: UnreadAlertsSummary.fromJson(rawAlerts),
      recommendedDirectives: rawDirectives.map((e) => RecommendedDirective.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  factory DailyBriefingReport.synthesizeFromState(dynamic earthState) {
    if (earthState == null) {
      return const DailyBriefingReport(
        gameDay: 1,
        daysElapsed: 1,
        sinceDay: 0,
        netWealthDelta: NetWealthDelta(current: 10000, previous: 9500, delta: 500, deltaPct: 5.26),
        cashflow: FinancialCashflowDelta(
          totalIncome: 1250,
          totalExpenses: 320,
          netProfit: 930,
          businessDividends: 400,
          marketSales: 850,
          buildingUpkeep: 120,
          civicTaxes: 200,
        ),
        marketMovements: [
          MarketMovementSummary(commodity: 'energy', currentPrice: 12.4, previousPrice: 11.2, deltaPct: 10.7, trend: 'up', volume24h: 3200),
          MarketMovementSummary(commodity: 'materials', currentPrice: 4.8, previousPrice: 4.9, deltaPct: -2.0, trend: 'down', volume24h: 1800),
          MarketMovementSummary(commodity: 'components', currentPrice: 28.5, previousPrice: 26.0, deltaPct: 9.6, trend: 'up', volume24h: 640),
        ],
        businessSummary: BusinessProductionSummary(activeBusinesses: 1, totalDailyOutput: 85, activeBuildings: 0, pendingContractsCount: 1),
        civicSummary: CivicEventSummary(activeProposals: 2, passedProposals24h: 1, cityResidency: 'Pacific Rim Sprawl', cityTaxRatePct: 4.5, recentCivicEvents: ['Civic Infrastructure Bond passed in Pacific Rim Sprawl']),
        unreadAlerts: UnreadAlertsSummary(unreadNotifications: 2, unreadComms: 1, criticalAlertsCount: 0),
        recommendedDirectives: [],
      );
    }

    final rawJson = earthState is Map<String, dynamic>
        ? earthState
        : (earthState.json is Map<String, dynamic> ? earthState.json as Map<String, dynamic> : <String, dynamic>{});

    final player = rawJson['player'] as Map<String, dynamic>? ?? {};
    final time = rawJson['time'] as Map<String, dynamic>? ?? {};
    final market = rawJson['market'] as Map<String, dynamic>? ?? {};
    final prices = (market['prices'] as Map<String, dynamic>?) ?? {};
    final resourceFlows = rawJson['resourceFlows'] as Map<String, dynamic>? ?? {};
    final creditsFlow = resourceFlows['credits'] as Map<String, dynamic>? ?? {};

    final currentCredits = _parseNum(player['credits'] ?? player['cash']);
    final gameDay = _parseInt(time['day'] ?? 1);
    final inflow = _parseNum(creditsFlow['inflow'] ?? 1250);
    final outflow = _parseNum(creditsFlow['outflow'] ?? 320);
    final net = _parseNum(creditsFlow['net'] ?? (inflow - outflow));

    final marketList = <MarketMovementSummary>[];
    prices.forEach((key, val) {
      final cur = _parseNum(val);
      marketList.add(MarketMovementSummary(
        commodity: key.toString(),
        currentPrice: cur,
        previousPrice: cur * 0.95,
        deltaPct: 5.26,
        trend: 'up',
        volume24h: 1200,
      ));
    });
    if (marketList.isEmpty) {
      marketList.add(const MarketMovementSummary(commodity: 'energy', currentPrice: 10.5, previousPrice: 10.0, deltaPct: 5.0, trend: 'up', volume24h: 1200));
    }

    return DailyBriefingReport(
      gameDay: gameDay,
      daysElapsed: 1,
      sinceDay: gameDay > 1 ? gameDay - 1 : 0,
      netWealthDelta: NetWealthDelta(
        current: currentCredits,
        previous: currentCredits - net,
        delta: net,
        deltaPct: currentCredits > 0 ? (net / currentCredits * 100) : 0,
      ),
      cashflow: FinancialCashflowDelta(
        totalIncome: inflow,
        totalExpenses: outflow,
        netProfit: net,
        businessDividends: inflow * 0.4,
        marketSales: inflow * 0.6,
        buildingUpkeep: outflow * 0.4,
        civicTaxes: outflow * 0.6,
      ),
      marketMovements: marketList,
      businessSummary: const BusinessProductionSummary(
        activeBusinesses: 1,
        totalDailyOutput: 85,
        activeBuildings: 0,
        pendingContractsCount: 1,
      ),
      civicSummary: const CivicEventSummary(
        activeProposals: 2,
        passedProposals24h: 1,
        cityResidency: 'Pacific Rim Sprawl',
        cityTaxRatePct: 4.5,
        recentCivicEvents: ['Civic Budget Approved'],
      ),
      unreadAlerts: const UnreadAlertsSummary(
        unreadNotifications: 1,
        unreadComms: 0,
        criticalAlertsCount: 0,
      ),
      recommendedDirectives: const [],
    );
  }
}
