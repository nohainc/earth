import '../../shared/widgets/format_helpers.dart';

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
  Map<String, dynamic> get world => _toMap(json['world']);
  Map<String, dynamic> get resources => _toMap(json['resources']);
  Map<String, dynamic> get technology => _toMap(json['technology'] is Map
      ? (json['technology'] as Map)['research']
      : null);
  Map<String, dynamic> get technologyRegistry => _toMap(json['technology']);
  Map<String, dynamic> get governance => _toMap(json['governance']);
  Map<String, dynamic> get institutions => _toMap(json['institutions']);
  Map<String, dynamic> get life => _toMap(json['life']);
  List<dynamic> get aiAssistants => _toList(json['aiAssistants']);
  List<dynamic> get aiRecommendations => _toList(json['aiRecommendations']);
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
  List<dynamic> get communities => _toList(json['communities']);
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
  Map<String, dynamic> get districtZoning => _toMap(json['districtZoning']);
  List<dynamic> get investmentShares => _toList(json['investmentShares']);
  List<dynamic> get civicDividends => _toList(json['civicDividends']);
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
      if (c is Map && c['my_role'] != null) {
        list.add(Map<String, dynamic>.from(c));
      }
    }
    return list;
  }

  Map<String, dynamic>? get myCommunity {
    final list = myCommunities;
    return list.isNotEmpty ? list.first : null;
  }
}
