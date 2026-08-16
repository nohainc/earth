class EarthState {
  final Map<String, dynamic> json;
  const EarthState(this.json);

  Map<String, dynamic> get clock => json['clock'] as Map<String, dynamic>;
  Map<String, dynamic> get human => json['human'] as Map<String, dynamic>;
  Map<String, dynamic> get world => json['world'] as Map<String, dynamic>;
  Map<String, dynamic> get resources =>
      json['resources'] as Map<String, dynamic>;
  Map<String, dynamic> get business => json['business'] as Map<String, dynamic>;
  Map<String, dynamic> get technology =>
      (json['technology'] as Map<String, dynamic>)['research']
          as Map<String, dynamic>;
  Map<String, dynamic> get technologyRegistry =>
      (json['technology'] as Map<String, dynamic>);
  Map<String, dynamic> get governance =>
      json['governance'] as Map<String, dynamic>;
  Map<String, dynamic> get institutions =>
      json['institutions'] as Map<String, dynamic>;
  Map<String, dynamic> get life => json['life'] as Map<String, dynamic>;
  List<dynamic> get machines =>
      (json['machines'] as List<dynamic>?) ?? const [];
  List<dynamic> get productionEvents =>
      (json['productionEvents'] as List<dynamic>?) ?? const [];
  List<dynamic> get aiAssistants =>
      (json['aiAssistants'] as List<dynamic>?) ?? const [];
  List<dynamic> get aiRecommendations =>
      (json['aiRecommendations'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get market =>
      (json['market'] as Map<String, dynamic>)['products']
          as Map<String, dynamic>;
  List<dynamic> get marketBook =>
      ((json['market'] as Map<String, dynamic>)['book'] as List<dynamic>?) ??
      const [];
  List<dynamic> get marketTrades =>
      ((json['market'] as Map<String, dynamic>)['trades'] as List<dynamic>?) ??
      const [];
  List<dynamic> get marketOrders =>
      ((json['market'] as Map<String, dynamic>)['orders'] as List<dynamic>?) ??
      const [];
  double get marketFeeRate =>
      ((json['market'] as Map<String, dynamic>)['feeRate'] as num?)
          ?.toDouble() ??
      0;
  List<dynamic> get communities =>
      (json['communities'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get audit =>
      (json['audit'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get finance =>
      (json['finance'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get ledgerEntries =>
      (json['ledgerEntries'] as List<dynamic>?) ?? const [];
  List<dynamic> get publicActivity =>
      (json['publicActivity'] as List<dynamic>?) ?? const [];
  List<dynamic> get opportunities =>
      (json['opportunities'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get rankings =>
      (json['rankings'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get history =>
      (json['history'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get financeStatus =>
      (json['financeStatus'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get personalFinance =>
      (json['personalFinance'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get contracts =>
      (json['contracts'] as List<dynamic>?) ?? const [];
  List<dynamic> get roles => (json['roles'] as List<dynamic>?) ?? const [];
  Map<String, dynamic>? get membership =>
      json['membership'] as Map<String, dynamic>?;
}
