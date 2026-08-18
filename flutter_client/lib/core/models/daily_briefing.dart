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
  final double machineMaintenance;
  final double civicTaxes;

  const FinancialCashflowDelta({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netProfit,
    required this.businessDividends,
    required this.marketSales,
    required this.machineMaintenance,
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
        machineMaintenance: 0,
        civicTaxes: 0,
      );
    }
    return FinancialCashflowDelta(
      totalIncome: _parseNum(json['totalIncome']),
      totalExpenses: _parseNum(json['totalExpenses']),
      netProfit: _parseNum(json['netProfit']),
      businessDividends: _parseNum(json['businessDividends']),
      marketSales: _parseNum(json['marketSales']),
      machineMaintenance: _parseNum(json['machineMaintenance']),
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
  final int activeMachines;
  final int degradedMachinesCount;
  final int pendingContractsCount;

  const BusinessProductionSummary({
    required this.activeBusinesses,
    required this.totalDailyOutput,
    required this.activeMachines,
    required this.degradedMachinesCount,
    required this.pendingContractsCount,
  });

  factory BusinessProductionSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessProductionSummary(
        activeBusinesses: 0,
        totalDailyOutput: 0,
        activeMachines: 0,
        degradedMachinesCount: 0,
        pendingContractsCount: 0,
      );
    }
    return BusinessProductionSummary(
      activeBusinesses: _parseInt(json['activeBusinesses']),
      totalDailyOutput: _parseInt(json['totalDailyOutput']),
      activeMachines: _parseInt(json['activeMachines']),
      degradedMachinesCount: _parseInt(json['degradedMachinesCount']),
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
}
