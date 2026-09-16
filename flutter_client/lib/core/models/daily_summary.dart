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
      return const NetWealthDelta(
          current: 0, previous: 0, delta: 0, deltaPct: 0);
    }
    return NetWealthDelta(
      current: _parseNum(json['current']),
      previous: _parseNum(json['previous']),
      delta: _parseNum(json['delta']),
      deltaPct: _parseNum(json['deltaPct']),
    );
  }
}

class FinancialSummary {
  final double totalIncome;
  final double totalExpenses;
  final double netProfit;
  final double businessDividends;
  final double marketSales;
  final double marketPurchases;
  final double buildingUpkeep;
  final double civicTaxes;

  const FinancialSummary({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netProfit,
    required this.businessDividends,
    required this.marketSales,
    this.marketPurchases = 0,
    required this.buildingUpkeep,
    required this.civicTaxes,
  });

  factory FinancialSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FinancialSummary(
        totalIncome: 0,
        totalExpenses: 0,
        netProfit: 0,
        businessDividends: 0,
        marketSales: 0,
        buildingUpkeep: 0,
        civicTaxes: 0,
      );
    }
    return FinancialSummary(
      totalIncome: _parseNum(json['income'] ?? json['totalIncome']),
      totalExpenses: _parseNum(json['expenses'] ?? json['totalExpenses']),
      netProfit: _parseNum(json['net'] ?? json['netProfit']),
      businessDividends:
          _parseNum(json['dividends'] ?? json['businessDividends']),
      marketSales: _parseNum(json['marketSales']),
      marketPurchases: _parseNum(json['marketPurchases']),
      buildingUpkeep:
          _parseNum(json['buildingUpkeep'] ?? json['machineMaintenance']),
      civicTaxes: _parseNum(json['taxes'] ?? json['civicTaxes']),
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
  final double purchases;
  final double sales;

  const MarketMovementSummary({
    required this.commodity,
    required this.currentPrice,
    required this.previousPrice,
    required this.deltaPct,
    required this.trend,
    required this.volume24h,
    this.purchases = 0,
    this.sales = 0,
  });

  factory MarketMovementSummary.fromJson(Map<String, dynamic> json) {
    return MarketMovementSummary(
      commodity: json['commodity']?.toString() ?? '',
      currentPrice: _parseNum(json['currentPrice']),
      previousPrice: _parseNum(json['previousPrice']),
      deltaPct: _parseNum(json['deltaPct']),
      trend: json['trend']?.toString() ?? 'flat',
      volume24h: _parseInt(json['volume24h']),
      purchases: _parseNum(json['purchases']),
      sales: _parseNum(json['sales']),
    );
  }
}

class BuildingSummary {
  final int activeBusinesses;
  final int totalDailyOutput;
  final int activeBuildings;
  final List<DailySummaryEvent> completed;
  final List<DailySummaryEvent> upgraded;
  final List<DailySummaryEvent> inactive;

  const BuildingSummary({
    required this.activeBusinesses,
    required this.totalDailyOutput,
    required this.activeBuildings,
    this.completed = const [],
    this.upgraded = const [],
    this.inactive = const [],
  });

  factory BuildingSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BuildingSummary(
        activeBusinesses: 0,
        totalDailyOutput: 0,
        activeBuildings: 0,
      );
    }
    return BuildingSummary(
      activeBusinesses: _parseInt(json['activeBusinesses']),
      totalDailyOutput: _parseInt(json['totalDailyOutput']),
      activeBuildings: _parseInt(
          json['activeBuildings'] ?? (json['completed'] as List?)?.length),
      completed: _eventList(json['completed']),
      upgraded: _eventList(json['upgraded']),
      inactive: _eventList(json['inactive']),
    );
  }
}

class ResourceDelta {
  final String resource;
  final double produced;
  final double consumed;
  final double net;

  const ResourceDelta(
      {required this.resource,
      required this.produced,
      required this.consumed,
      required this.net});

  factory ResourceDelta.fromJson(Map<String, dynamic> json) => ResourceDelta(
        resource:
            json['resource']?.toString() ?? json['commodity']?.toString() ?? '',
        produced: _parseNum(json['produced']),
        consumed: _parseNum(json['consumed']),
        net: _parseNum(json['net']),
      );
}

class DailySummaryEvent {
  final String id;
  final String type;
  final String title;
  final String details;
  final int gameDay;
  final int? gameMinute;

  const DailySummaryEvent(
      {required this.id,
      required this.type,
      required this.title,
      required this.details,
      required this.gameDay,
      this.gameMinute});

  factory DailySummaryEvent.fromJson(Map<String, dynamic> json) =>
      DailySummaryEvent(
        id: json['id']?.toString() ?? '',
        type: (json['type'] ?? json['event_type'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        details: (json['details'] ?? '').toString(),
        gameDay: _parseInt(json['gameDay'] ?? json['game_day']),
        gameMinute: json['gameMinute'] == null && json['game_minute'] == null
            ? null
            : _parseInt(json['gameMinute'] ?? json['game_minute']),
      );
}

List<DailySummaryEvent> _eventList(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) =>
            DailySummaryEvent.fromJson(Map<String, dynamic>.from(item)))
        .toList()
    : const [];

class GovernanceSummary {
  final int activeProposals;
  final int passedProposals24h;
  final String territoryResidency;
  final double territoryTaxRatePct;
  final List<String> recentCivicEvents;

  const GovernanceSummary({
    required this.activeProposals,
    required this.passedProposals24h,
    required this.territoryResidency,
    required this.territoryTaxRatePct,
    required this.recentCivicEvents,
  });

  /// Compatibility accessors for older clients; presentation uses Territory
  /// terminology and the canonical fields above.
  @Deprecated('Use territoryResidency')
  String get cityResidency => territoryResidency;

  @Deprecated('Use territoryTaxRatePct')
  double get cityTaxRatePct => territoryTaxRatePct;

  factory GovernanceSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GovernanceSummary(
        activeProposals: 0,
        passedProposals24h: 0,
        territoryResidency: '',
        territoryTaxRatePct: 0.0,
        recentCivicEvents: [],
      );
    }
    final rawEvents = (json['recentCivicEvents'] as List<dynamic>?) ??
        (json['relevantEvents'] as List<dynamic>? ?? []);
    return GovernanceSummary(
      activeProposals: _parseInt(json['activeProposals']),
      passedProposals24h: _parseInt(json['passedProposals24h']),
      territoryResidency: (json['territoryResidency'] ??
              json['territory_residency'] ??
              json['cityResidency'] ??
              '')
          .toString(),
      territoryTaxRatePct: _parseNum(json['territoryTaxRatePct'] ??
          json['territory_tax_rate_pct'] ??
          json['cityTaxRatePct']),
      recentCivicEvents: rawEvents.map((e) => e.toString()).toList(),
    );
  }
}

class AlertSummary {
  final int unreadNotifications;
  final int unreadComms;
  final int criticalAlertsCount;

  const AlertSummary({
    required this.unreadNotifications,
    required this.unreadComms,
    required this.criticalAlertsCount,
  });

  factory AlertSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AlertSummary(
        unreadNotifications: 0,
        unreadComms: 0,
        criticalAlertsCount: 0,
      );
    }
    final notifications = json['notifications'] as List<dynamic>? ?? [];
    return AlertSummary(
      unreadNotifications: _parseInt(json['unreadNotifications'] ??
          notifications
              .where((item) => item is Map && item['read'] != true)
              .length),
      unreadComms: _parseInt(json['unreadComms']),
      criticalAlertsCount: _parseInt(json['criticalAlertsCount']),
    );
  }
}

class SummaryHighlight {
  final String id;
  final String title;
  final String urgency;
  final String reason;
  final String actionLabel;
  final String targetSection;

  const SummaryHighlight({
    required this.id,
    required this.title,
    required this.urgency,
    required this.reason,
    required this.actionLabel,
    required this.targetSection,
  });

  factory SummaryHighlight.fromJson(Map<String, dynamic> json) {
    return SummaryHighlight(
      id: json['id']?.toString() ?? json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? json['code']?.toString() ?? '',
      urgency: (json['urgency'] ?? json['severity'])?.toString() ?? 'medium',
      reason: json['reason']?.toString() ?? '',
      actionLabel: json['actionLabel']?.toString() ?? 'VIEW',
      targetSection: json['targetSection']?.toString() ?? 'command',
    );
  }
}

class DailySummaryReport {
  final int gameDay;
  final int currentGameDay;
  final int daysElapsed;
  final int sinceDay;
  final NetWealthDelta netWealthDelta;
  final FinancialSummary financial;
  final List<MarketMovementSummary> marketMovements;
  final BuildingSummary buildings;
  final GovernanceSummary governance;
  final AlertSummary alerts;
  final List<SummaryHighlight> highlights;
  final List<ResourceDelta> resources;
  final List<DailySummaryEvent> researchEvents;
  final List<DailySummaryEvent> governanceEvents;
  final List<DailySummaryEvent> houseEvents;
  final List<DailySummaryEvent> alertItems;

  const DailySummaryReport({
    required this.gameDay,
    this.currentGameDay = 0,
    required this.daysElapsed,
    required this.sinceDay,
    required this.netWealthDelta,
    required this.financial,
    required this.marketMovements,
    required this.buildings,
    required this.governance,
    required this.alerts,
    required this.highlights,
    this.resources = const [],
    this.researchEvents = const [],
    this.governanceEvents = const [],
    this.houseEvents = const [],
    this.alertItems = const [],
  });

  factory DailySummaryReport.empty({int gameDay = 0}) {
    return DailySummaryReport(
      gameDay: gameDay,
      currentGameDay: gameDay,
      daysElapsed: 0,
      sinceDay: gameDay,
      netWealthDelta:
          const NetWealthDelta(current: 0, previous: 0, delta: 0, deltaPct: 0),
      financial: const FinancialSummary(
          totalIncome: 0,
          totalExpenses: 0,
          netProfit: 0,
          businessDividends: 0,
          marketSales: 0,
          buildingUpkeep: 0,
          civicTaxes: 0),
      marketMovements: const [],
      buildings: const BuildingSummary(
          activeBusinesses: 0, totalDailyOutput: 0, activeBuildings: 0),
      governance: const GovernanceSummary(
          activeProposals: 0,
          passedProposals24h: 0,
          territoryResidency: '',
          territoryTaxRatePct: 0,
          recentCivicEvents: []),
      alerts: const AlertSummary(
          unreadNotifications: 0, unreadComms: 0, criticalAlertsCount: 0),
      highlights: const [],
      resources: const [],
      researchEvents: const [],
      governanceEvents: const [],
      houseEvents: const [],
      alertItems: const [],
    );
  }

  factory DailySummaryReport.fromJson(Map<String, dynamic> json) {
    final traded = json['resources'] is Map
        ? (Map<String, dynamic>.from(json['resources'] as Map)['traded']
                as List<dynamic>? ??
            [])
        : <dynamic>[];
    final rawMarkets = json['marketMovements'] as List<dynamic>? ?? traded;
    final rawDirectives = json['highlights'] as List<dynamic>? ?? [];
    final rawNetWealth = json['netWealthDelta'] is Map
        ? Map<String, dynamic>.from(json['netWealthDelta'] as Map)
        : null;
    final rawCashflow = json['financial'] is Map
        ? Map<String, dynamic>.from(json['financial'] as Map)
        : null;
    final rawBusiness = json['buildings'] is Map
        ? Map<String, dynamic>.from(json['buildings'] as Map)
        : null;
    final rawCivic = json['governance'] is Map
        ? Map<String, dynamic>.from(json['governance'] as Map)
        : null;
    final rawAlerts = json['alerts'] is Map
        ? Map<String, dynamic>.from(json['alerts'] as Map)
        : null;
    final rawResources = json['resources'] is Map
        ? Map<String, dynamic>.from(json['resources'] as Map)
        : const <String, dynamic>{};

    return DailySummaryReport(
      gameDay: _parseInt(json['summaryDay'] ?? json['gameDay']),
      currentGameDay:
          _parseInt(json['currentGameDay'] ?? json['current_game_day']),
      daysElapsed:
          _parseInt(json['summaryDay'] != null ? 1 : json['daysElapsed']),
      sinceDay: _parseInt(json['summaryDay'] ?? json['sinceDay']),
      netWealthDelta: NetWealthDelta.fromJson(rawNetWealth),
      financial: FinancialSummary.fromJson(rawCashflow),
      marketMovements: rawMarkets
          .map((e) => MarketMovementSummary.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      buildings: BuildingSummary.fromJson(rawBusiness),
      governance: GovernanceSummary.fromJson(rawCivic),
      alerts: rawAlerts == null
          ? AlertSummary.fromJson({'notifications': json['alerts'] ?? []})
          : AlertSummary.fromJson(rawAlerts),
      highlights: rawDirectives
          .map((e) =>
              SummaryHighlight.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      resources: (rawResources['deltas'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ResourceDelta.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      researchEvents: _eventList((json['research'] as Map?)?['completed']) +
          _eventList((json['research'] as Map?)?['progress']),
      governanceEvents:
          _eventList((json['governance'] as Map?)?['relevantEvents']),
      houseEvents: _eventList((json['house'] as Map?)?['events']),
      alertItems: _eventList(json['alerts']),
    );
  }
}
