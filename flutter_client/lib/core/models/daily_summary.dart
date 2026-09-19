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

String _parseUnitsString(dynamic v) {
  if (v == null) return '0';
  if (v is String) return v.trim();
  if (v is int || v is BigInt) return v.toString();
  if (v is num) return v.toString();
  return v.toString().trim();
}

class FinancialSummary {
  final String incomeUnits;
  final String expensesUnits;
  final String netCashflowUnits;
  final String taxesUnits;
  final String marketSalesUnits;
  final String marketPurchasesUnits;

  const FinancialSummary({
    required this.incomeUnits,
    required this.expensesUnits,
    required this.netCashflowUnits,
    required this.taxesUnits,
    required this.marketSalesUnits,
    this.marketPurchasesUnits = '0',
  });

  factory FinancialSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FinancialSummary(
        incomeUnits: '0',
        expensesUnits: '0',
        netCashflowUnits: '0',
        taxesUnits: '0',
        marketSalesUnits: '0',
        marketPurchasesUnits: '0',
      );
    }
    return FinancialSummary(
      incomeUnits: _parseUnitsString(json['incomeUnits']),
      expensesUnits: _parseUnitsString(json['expensesUnits']),
      netCashflowUnits: _parseUnitsString(json['netCashflowUnits']),
      taxesUnits: _parseUnitsString(json['taxesUnits']),
      marketSalesUnits: _parseUnitsString(json['marketSalesUnits']),
      marketPurchasesUnits: _parseUnitsString(json['marketPurchasesUnits']),
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
  final int operatedBuildingCount;
  final List<DailySummaryEvent> completed;
  final List<DailySummaryEvent> upgraded;
  final List<DailySummaryEvent> inactive;

  const BuildingSummary({
    required this.operatedBuildingCount,
    this.completed = const [],
    this.upgraded = const [],
    this.inactive = const [],
  });

  factory BuildingSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BuildingSummary(
        operatedBuildingCount: 0,
      );
    }
    return BuildingSummary(
      operatedBuildingCount: _parseInt(json['operatedBuildingCount']),
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
  final int eventCount;
  final List<DailySummaryEvent> events;

  const GovernanceSummary({
    required this.eventCount,
    required this.events,
  });

  factory GovernanceSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GovernanceSummary(
        eventCount: 0,
        events: [],
      );
    }
    final events = _eventList(json['events']);
    return GovernanceSummary(
      eventCount: _parseInt(json['eventCount']),
      events: events,
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
  final int resourceShortfallCount;
  final List<DailySummaryEvent> researchEvents;
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
    this.resourceShortfallCount = 0,
    this.researchEvents = const [],
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
          incomeUnits: '0',
          expensesUnits: '0',
          netCashflowUnits: '0',
          taxesUnits: '0',
          marketSalesUnits: '0',
          marketPurchasesUnits: '0'),
      marketMovements: const [],
      buildings: const BuildingSummary(operatedBuildingCount: 0),
      governance: const GovernanceSummary(eventCount: 0, events: []),
      alerts: const AlertSummary(
          unreadNotifications: 0, unreadComms: 0, criticalAlertsCount: 0),
      highlights: const [],
      resources: const [],
      resourceShortfallCount: 0,
      researchEvents: const [],
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
    final rawGovernance = json['governance'] is Map
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
      governance: GovernanceSummary.fromJson(rawGovernance),
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
      resourceShortfallCount: _parseInt(json['resourceShortfallCount']),
      researchEvents: _eventList((json['research'] as Map?)?['completed']) +
          _eventList((json['research'] as Map?)?['progress']),
      houseEvents: _eventList((json['house'] as Map?)?['events']),
      alertItems: _eventList(json['alerts']),
    );
  }
}
