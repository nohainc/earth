import '../../shared/widgets/format_helpers.dart';
import 'human_profile.dart';
import 'human_daily_needs.dart';
import 'human_authority_summary.dart';
import 'building_models.dart';
import 'technology_models.dart';

class EarthState {
  final Map<String, dynamic> json;
  const EarthState(this.json);

  static Map<String, dynamic> _toMap(dynamic val) {
    if (val is Map<String, dynamic>) return val;
    if (val is Map) return Map<String, dynamic>.from(val);
    return const {};
  }

  static List<dynamic> _toList(dynamic val) {
    if (val is List) return val;
    return const [];
  }

  Map<String, dynamic> get clock => _toMap(json['clock']);
  Map<String, dynamic> get human => _toMap(json['human']);
  HumanProfile? get humanProfile {
    final value = json['humanProfile'];
    return value is Map ? HumanProfile.fromJson(_toMap(value)) : null;
  }

  HumanDailyNeeds? get humanDailyNeeds {
    final value = json['humanDailyNeeds'];
    return value is Map ? HumanDailyNeeds.fromJson(_toMap(value)) : null;
  }

  List<dynamic> get roles => _toList(json['roles']);
  List<HumanAuthoritySummary> get humanAuthoritySummary => _toList(
        json['humanAuthoritySummary'],
      )
          .whereType<Map>()
          .map((row) => HumanAuthoritySummary.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList(growable: false);
  List<dynamic> get recentLifeEvents => _toList(json['recentLifeEvents']);
  Map<String, dynamic> get house => _toMap(json['house']);
  Map<String, dynamic> get residency => _toMap(json['residency']);
  Map<String, dynamic> get world => _toMap(json['world']);
  Map<String, dynamic> get resources => _toMap(json['resources']);
  Map<String, dynamic> get technology => _toMap(json['technology'] is Map
      ? (json['technology'] as Map)['research']
      : null);
  Map<String, dynamic> get technologyRegistry => _toMap(json['technology']);
  TechnologyWorkspace get technologyWorkspace =>
      TechnologyWorkspace.fromJson(technologyRegistry);
  Map<String, dynamic> get governance => _toMap(json['governance']);
  Map<String, dynamic> get institutions => _toMap(json['institutions']);
  Map<String, dynamic> get life => _toMap(json['life']);
  Map<String, dynamic> get market => _toMap(
      json['market'] is Map ? (json['market'] as Map)['products'] : null);
  List<dynamic> get marketBook =>
      _toList(json['market'] is Map ? (json['market'] as Map)['book'] : null);
  List<dynamic> get marketTrades =>
      _toList(json['market'] is Map ? (json['market'] as Map)['trades'] : null);
  List<dynamic> get marketOrders =>
      _toList(json['market'] is Map ? (json['market'] as Map)['orders'] : null);
  double get marketFeeRate =>
      asDouble(
          json['market'] is Map ? (json['market'] as Map)['feeRate'] : null) ??
      0;
  double get marketReservedCredits =>
      asDouble(json['market'] is Map
          ? (json['market'] as Map)['reservedCredits']
          : null) ??
      0;
  List<dynamic> get communities => _toList(json['communities']);
  List<dynamic> get territories => _toList(json['territories']);
  List<dynamic> get organizations => _toList(json['organizations']);
  Map<String, dynamic> get audit => _toMap(json['audit']);
  Map<String, dynamic> get finance => _toMap(json['finance']);
  List<dynamic> get ledgerEntries => _toList(json['ledgerEntries']);
  List<dynamic> get publicActivity => _toList(json['publicActivity']);
  List<dynamic> get opportunities => _toList(json['opportunities']);
  List<dynamic> get decisionQueue => _toList(json['decisionQueue']);
  List<dynamic> get objectives => _toList(json['objectives']);
  Map<String, dynamic> get rankings => _toMap(json['rankings']);
  Map<String, dynamic> get history => _toMap(json['history']);
  List<dynamic> get financeStatus => _toList(json['financeStatus']);
  Map<String, dynamic> get personalFinance => _toMap(json['personalFinance']);
  List<dynamic> get buildings => _toList(json['buildings']);
  BuildingPortfolio? get buildingPortfolio {
    final value = json['buildingPortfolio'];
    return value is Map ? BuildingPortfolio.fromJson(_toMap(value)) : null;
  }

  List<BuildingAsset> get houseBuildingAssets =>
      buildingPortfolio?.houseAssets ?? const [];
  List<BuildingAsset> get corporationPublicBuildingAssets =>
      buildingPortfolio?.corporationPublicAssets ?? const [];
  Map<String, dynamic> get districtZoning => _toMap(json['districtZoning']);
  List<dynamic> get investmentShares => _toList(json['investmentShares']);
  List<dynamic> get corporateResearch => _toList(json['corporateResearch']);
  Map<String, dynamic> get corporationBuildingResearch =>
      _toMap(json['corporationBuildingResearch']);
  List<dynamic> get buildingPatentLicenses =>
      _toList(json['buildingPatentLicenses']);
  List<dynamic> get buildingCatalog => _toList(json['buildingCatalog']);
  Map<String, dynamic>? get membership => json['membership'] is Map
      ? Map<String, dynamic>.from(json['membership'] as Map)
      : null;
  List<Map<String, dynamic>> get myCommunities {
    final list = <Map<String, dynamic>>[];
    for (final c in communities) {
      if (c is Map) {
        final row = Map<String, dynamic>.from(c);
        final viewer = row['viewer'] is Map
            ? Map<String, dynamic>.from(row['viewer'] as Map)
            : const <String, dynamic>{};
        if (viewer['membershipStatus'] == 'ACTIVE') list.add(row);
      }
    }
    return list;
  }

  Map<String, dynamic> get corporation => _toMap(json['corporation']);
  Map<String, dynamic> get corporationProfile =>
      _toMap(json['corporationProfile']);
  Map<String, dynamic> get settlement => _toMap(json['settlement']);
  Map<String, dynamic> get settlementProfile =>
      _toMap(json['settlementProfile']);
  List<dynamic> get scaleCapabilities => _toList(json['scaleCapabilities']);
  Map<String, dynamic> get corporationResources =>
      _toMap(corporation['resources']);
  double get corporationTreasury => asDouble(corporation['treasury']) ?? 0.0;
  Map<String, dynamic> get corporationSettlementProfile =>
      _toMap(corporation['settlementProfile']);
  List<dynamic> get corporationScaleCapabilities =>
      _toList(corporation['scaleCapabilities']);

  Map<String, dynamic>? get myCommunity {
    final list = myCommunities;
    return list.isNotEmpty ? list.first : null;
  }
}
