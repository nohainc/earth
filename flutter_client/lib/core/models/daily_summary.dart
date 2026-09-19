int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
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
  final List<CashflowBreakdownRow> cashflowBreakdown;

  const FinancialSummary({
    required this.incomeUnits,
    required this.expensesUnits,
    required this.netCashflowUnits,
    this.cashflowBreakdown = const [],
  });

  factory FinancialSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FinancialSummary(
        incomeUnits: '0',
        expensesUnits: '0',
        netCashflowUnits: '0',
        cashflowBreakdown: const [],
      );
    }
    return FinancialSummary(
      incomeUnits: _parseUnitsString(json['incomeUnits']),
      expensesUnits: _parseUnitsString(json['expensesUnits']),
      netCashflowUnits: _parseUnitsString(json['netCashflowUnits']),
      cashflowBreakdown: (json['cashflowBreakdown'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((row) => CashflowBreakdownRow.fromJson(
              Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}

class CashflowBreakdownRow {
  final String category;
  final String inflowUnits;
  final String outflowUnits;

  const CashflowBreakdownRow({
    required this.category,
    required this.inflowUnits,
    required this.outflowUnits,
  });

  factory CashflowBreakdownRow.fromJson(Map<String, dynamic> json) {
    return CashflowBreakdownRow(
      category: json['category']?.toString() ?? 'OTHER',
      inflowUnits: _parseUnitsString(json['inflowUnits']),
      outflowUnits: _parseUnitsString(json['outflowUnits']),
    );
  }
}

class MarketDailyActivity {
  final String commodity;
  final String boughtUnits;
  final String soldUnits;
  final String creditSpentUnits;
  final String creditReceivedUnits;
  final String volumeUnits;

  const MarketDailyActivity({
    required this.commodity,
    required this.boughtUnits,
    required this.soldUnits,
    required this.creditSpentUnits,
    required this.creditReceivedUnits,
    required this.volumeUnits,
  });

  factory MarketDailyActivity.fromJson(Map<String, dynamic> json) {
    return MarketDailyActivity(
      commodity: json['commodity']?.toString() ?? '',
      boughtUnits: _parseUnitsString(json['boughtUnits']),
      soldUnits: _parseUnitsString(json['soldUnits']),
      creditSpentUnits: _parseUnitsString(json['creditSpentUnits']),
      creditReceivedUnits: _parseUnitsString(json['creditReceivedUnits']),
      volumeUnits: _parseUnitsString(json['volumeUnits']),
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
  final String producedUnits;
  final String consumedUnits;
  final String netUnits;

  const ResourceDelta(
      {required this.resource,
      required this.producedUnits,
      required this.consumedUnits,
      required this.netUnits});

  factory ResourceDelta.fromJson(Map<String, dynamic> json) => ResourceDelta(
        resource:
            json['resource']?.toString() ?? json['commodity']?.toString() ?? '',
        producedUnits: _parseUnitsString(json['producedUnits']),
        consumedUnits: _parseUnitsString(json['consumedUnits']),
        netUnits: _parseUnitsString(json['netUnits']),
      );

  bool get isShortfall => (BigInt.tryParse(netUnits) ?? BigInt.zero) < BigInt.zero;
}

class DailySummaryEvent {
  final String id;
  final String type;
  final String title;
  final String details;
  final int gameDay;
  final int? gameMinute;
  final String source;
  final String category;

  const DailySummaryEvent(
      {required this.id,
      required this.type,
      required this.title,
      required this.details,
      required this.gameDay,
      this.gameMinute,
      this.source = 'GAME_EVENT',
      this.category = 'EVENT'});

  factory DailySummaryEvent.fromJson(Map<String, dynamic> json) =>
      DailySummaryEvent(
        id: json['id']?.toString() ?? '',
        type: (json['type'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        details: (json['details'] ?? '').toString(),
        gameDay: _parseInt(json['gameDay']),
        gameMinute: json['gameMinute'] == null
            ? null
            : _parseInt(json['gameMinute']),
        source: (json['source'] ?? 'GAME_EVENT').toString(),
        category: (json['category'] ?? 'EVENT').toString(),
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

class DailyStatementMetadata {
  final int gameDay;
  final bool immutable;
  final String settlementStatus;
  final String? rulesVersion;
  final DateTime? finalizedAt;
  final DateTime? statementCreatedAt;
  final DateTime? statementUpdatedAt;

  const DailyStatementMetadata({
    required this.gameDay,
    required this.immutable,
    required this.settlementStatus,
    this.rulesVersion,
    this.finalizedAt,
    this.statementCreatedAt,
    this.statementUpdatedAt,
  });

  factory DailyStatementMetadata.fromJson(Map<String, dynamic>? json,
      {int fallbackGameDay = 0}) {
    DateTime? parseDate(dynamic value) => value == null
        ? null
        : DateTime.tryParse(value.toString())?.toUtc();
    return DailyStatementMetadata(
      gameDay: _parseInt(json?['gameDay'] ?? fallbackGameDay),
      immutable: json?['immutable'] == true,
      settlementStatus: json?['settlementStatus']?.toString() ?? 'unknown',
      rulesVersion: json?['rulesVersion']?.toString(),
      finalizedAt: parseDate(json?['finalizedAt']),
      statementCreatedAt: parseDate(json?['statementCreatedAt']),
      statementUpdatedAt: parseDate(json?['statementUpdatedAt']),
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
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      urgency: json['urgency']?.toString() ?? 'medium',
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
  final DailyStatementMetadata statementMetadata;
  final List<DailySummaryEvent> timeline;
  final FinancialSummary financial;
  final List<MarketDailyActivity> marketActivity;
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
    required this.statementMetadata,
    required this.timeline,
    required this.financial,
    required this.marketActivity,
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
      statementMetadata: DailyStatementMetadata.fromJson(null, fallbackGameDay: gameDay),
      timeline: const [],
      financial: const FinancialSummary(
          incomeUnits: '0',
          expensesUnits: '0',
          netCashflowUnits: '0',
          cashflowBreakdown: const []),
      marketActivity: const [],
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
    final rawMarkets = json['marketActivity'] as List<dynamic>? ?? [];
    final rawDirectives = json['highlights'] as List<dynamic>? ?? [];
    final rawCashflow = json['financial'] is Map
        ? Map<String, dynamic>.from(json['financial'] as Map)
        : null;
    final rawBusiness = json['buildings'] is Map
        ? Map<String, dynamic>.from(json['buildings'] as Map)
        : null;
    final rawAlerts = json['alerts'] is Map
        ? Map<String, dynamic>.from(json['alerts'] as Map)
        : null;
    final rawResources = json['resources'] is Map
        ? Map<String, dynamic>.from(json['resources'] as Map)
        : const <String, dynamic>{};
    final timeline = _eventList(json['timeline']);
    final governanceEvents = timeline
        .where((event) => event.type.startsWith('PROPOSAL_') ||
            event.type.startsWith('GOVERNANCE_'))
        .toList();

    return DailySummaryReport(
      gameDay: _parseInt(json['summaryDay']),
      currentGameDay: _parseInt(json['currentGameDay']),
      daysElapsed: 1,
      sinceDay: _parseInt(json['summaryDay']),
      statementMetadata: DailyStatementMetadata.fromJson(
          json['statementMetadata'] is Map
              ? Map<String, dynamic>.from(json['statementMetadata'] as Map)
              : null,
          fallbackGameDay: _parseInt(json['summaryDay'])),
      timeline: timeline,
      financial: FinancialSummary.fromJson(rawCashflow),
      marketActivity: rawMarkets
          .map((e) => MarketDailyActivity.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      buildings: BuildingSummary.fromJson(rawBusiness),
      governance: GovernanceSummary(
          eventCount: governanceEvents.length, events: governanceEvents),
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
