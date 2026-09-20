import 'decision_queue_item.dart';

class OverviewMarketProduct {
  final String product;
  final String supplyUnits;
  final String demandUnits;
  final String priceUnits;
  final String? openSellUnits;
  final String? openBuyUnits;
  final int? latestSettledGameDay;
  final String? closingBalance;
  final String? production;
  final String? consumption;
  final String? netFlow;
  final String? shortage;

  const OverviewMarketProduct({
    required this.product,
    required this.supplyUnits,
    required this.demandUnits,
    required this.priceUnits,
    this.openSellUnits,
    this.openBuyUnits,
    this.latestSettledGameDay,
    this.closingBalance,
    this.production,
    this.consumption,
    this.netFlow,
    this.shortage,
  });

  factory OverviewMarketProduct.fromJson(Map<String, dynamic> json) =>
      OverviewMarketProduct(
        product: json['product']?.toString() ?? '',
        supplyUnits: json['supplyUnits']?.toString() ??
            json['supply']?.toString() ??
            '0',
        demandUnits: json['demandUnits']?.toString() ??
            json['demand']?.toString() ??
            '0',
        priceUnits:
            json['priceUnits']?.toString() ?? json['price']?.toString() ?? '0',
        openSellUnits: json['openSellUnits']?.toString(),
        openBuyUnits: json['openBuyUnits']?.toString(),
        latestSettledGameDay:
            int.tryParse(json['latestSettledGameDay']?.toString() ?? ''),
        closingBalance: json['closingBalance']?.toString(),
        production: json['production']?.toString(),
        consumption: json['consumption']?.toString(),
        netFlow: json['netFlow']?.toString(),
        shortage: json['shortage']?.toString(),
      );
}

class OverviewFinanceSummary {
  final String availableWalletUnits;
  final Map<String, dynamic>? latestStatement;

  const OverviewFinanceSummary({
    required this.availableWalletUnits,
    this.latestStatement,
  });

  factory OverviewFinanceSummary.fromJson(Map<String, dynamic> json) =>
      OverviewFinanceSummary(
        availableWalletUnits: json['availableWalletUnits']?.toString() ??
            json['balance']?.toString() ??
            '0',
        latestStatement: json['latestStatement'] as Map<String, dynamic>?,
      );
}

class OverviewBuildingsSummary {
  final int totalCount;
  final int activeCount;
  final int suspendedCount;
  final int otherCount;

  const OverviewBuildingsSummary({
    required this.totalCount,
    required this.activeCount,
    this.suspendedCount = 0,
    this.otherCount = 0,
  });

  factory OverviewBuildingsSummary.fromJson(Map<String, dynamic> json) =>
      OverviewBuildingsSummary(
        totalCount: int.tryParse(json['totalCount']?.toString() ?? '') ??
            int.tryParse(json['total']?.toString() ?? '') ??
            0,
        activeCount: int.tryParse(json['activeCount']?.toString() ?? '') ??
            int.tryParse(json['active']?.toString() ?? '') ??
            0,
        suspendedCount:
            int.tryParse(json['suspendedCount']?.toString() ?? '') ??
                int.tryParse(json['suspended']?.toString() ?? '') ??
                0,
        otherCount: int.tryParse(json['otherCount']?.toString() ?? '') ?? 0,
      );
}

class OverviewMarketSummary {
  final String energyPriceUnits;
  final String materialsPriceUnits;
  final String componentsPriceUnits;
  final List<OverviewMarketProduct> products;

  const OverviewMarketSummary({
    required this.energyPriceUnits,
    required this.materialsPriceUnits,
    required this.componentsPriceUnits,
    this.products = const [],
  });

  factory OverviewMarketSummary.fromJson(Map<String, dynamic> json) {
    final list = json['products'] as List<dynamic>? ?? const [];
    return OverviewMarketSummary(
      energyPriceUnits: json['energyPriceUnits']?.toString() ?? '0',
      materialsPriceUnits: json['materialsPriceUnits']?.toString() ?? '0',
      componentsPriceUnits: json['componentsPriceUnits']?.toString() ?? '0',
      products: list
          .whereType<Map>()
          .map((e) =>
              OverviewMarketProduct.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class OverviewDecisionsSummary {
  final int totalCount;
  final int criticalCount;
  final int highCount;
  final List<DecisionQueueItem> items;

  const OverviewDecisionsSummary({
    required this.totalCount,
    required this.criticalCount,
    required this.highCount,
    this.items = const [],
  });

  factory OverviewDecisionsSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => DecisionQueueItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return OverviewDecisionsSummary(
      totalCount:
          int.tryParse(json['totalCount']?.toString() ?? '') ?? items.length,
      criticalCount: int.tryParse(json['criticalCount']?.toString() ?? '') ??
          items.where((d) => d.riskLevel == 'critical').length,
      highCount: int.tryParse(json['highCount']?.toString() ?? '') ??
          items.where((d) => d.riskLevel == 'high').length,
      items: items,
    );
  }
}

class OverviewCapacitySummary {
  final String residentialUnits;
  final String buildingUnits;
  final String totalUnits;
  final String delinquencyStatus;

  const OverviewCapacitySummary({
    required this.residentialUnits,
    required this.buildingUnits,
    required this.totalUnits,
    required this.delinquencyStatus,
  });

  factory OverviewCapacitySummary.fromJson(Map<String, dynamic> json) {
    final del = json['delinquency'] as Map<String, dynamic>? ?? const {};
    return OverviewCapacitySummary(
      residentialUnits: json['residentialUnits']?.toString() ??
          json['residential_units']?.toString() ??
          '0',
      buildingUnits: json['buildingUnits']?.toString() ??
          json['building_units']?.toString() ??
          '0',
      totalUnits: json['totalUnits']?.toString() ??
          json['total_units']?.toString() ??
          '0',
      delinquencyStatus:
          del['status']?.toString() ?? json['status']?.toString() ?? 'CURRENT',
    );
  }
}

class CommandOverview {
  final bool ok;
  final String version;
  final int gameDay;
  final int nextSettlementGameDay;
  final String houseId;
  final String houseName;
  final int generation;
  final String houseStatus;
  final String? corporationId;
  final OverviewFinanceSummary finance;
  final OverviewBuildingsSummary buildings;
  final OverviewMarketSummary market;
  final OverviewDecisionsSummary decisions;
  final OverviewCapacitySummary? capacity;
  final List<Map<String, dynamic>> attention;

  const CommandOverview({
    this.ok = true,
    this.version = 'V5-OVERVIEW-1',
    required this.gameDay,
    required this.nextSettlementGameDay,
    required this.houseId,
    required this.houseName,
    required this.generation,
    required this.houseStatus,
    this.corporationId,
    required this.finance,
    required this.buildings,
    required this.market,
    required this.decisions,
    this.capacity,
    this.attention = const [],
  });

  factory CommandOverview.fromJson(Map<String, dynamic> json) {
    final house = json['house'] as Map<String, dynamic>? ?? const {};
    final financeMap = json['finance'] as Map<String, dynamic>? ?? const {};
    final buildingsMap = json['buildings'] as Map<String, dynamic>? ?? const {};
    final marketMap = json['market'] as Map<String, dynamic>? ?? const {};
    final decisionsMap = json['decisions'] as Map<String, dynamic>? ?? const {};
    final capacityMap = json['capacity'] as Map<String, dynamic>?;
    final attentionList = (json['attention'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];

    return CommandOverview(
      ok: json['ok'] == true || json['ok'] == 'true',
      version: json['version']?.toString() ?? 'V5-OVERVIEW-1',
      gameDay: int.tryParse(json['gameDay']?.toString() ?? '') ?? 0,
      nextSettlementGameDay:
          int.tryParse(json['nextSettlementGameDay']?.toString() ?? '') ?? 0,
      houseId: house['id']?.toString() ?? '',
      houseName: house['name']?.toString() ?? '',
      generation: int.tryParse(house['generation']?.toString() ?? '') ?? 1,
      houseStatus: house['status']?.toString() ?? 'ACTIVE',
      corporationId: house['corporationId']?.toString(),
      finance: OverviewFinanceSummary.fromJson(financeMap),
      buildings: OverviewBuildingsSummary.fromJson(buildingsMap),
      market: OverviewMarketSummary.fromJson(marketMap),
      decisions: OverviewDecisionsSummary.fromJson(decisionsMap),
      capacity: capacityMap != null
          ? OverviewCapacitySummary.fromJson(capacityMap)
          : null,
      attention: attentionList,
    );
  }
}
