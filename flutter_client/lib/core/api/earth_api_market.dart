part of 'earth_api.dart';

extension EarthApiMarket on EarthApi {
  // --- Market ---

  Future<List<MarketInstrumentSummary>> marketInstruments() async {
    final response = await _request('/api/market/instruments');
    final map = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    final rows = map['instruments'];
    return rows is List
        ? rows.whereType<Map>().map((row) => MarketInstrumentSummary.fromJson(Map<String, dynamic>.from(row))).toList()
        : const [];
  }

  Future<MarketBook> marketBook(String instrument) async {
    final response = await _request('/api/market/${Uri.encodeComponent(instrument)}/book');
    final map = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    return MarketBook.fromJson(map);
  }

  Future<List<MarketCandle>> marketCandles(String instrument,
      {MarketCandleInterval interval = MarketCandleInterval.hourly}) async {
    final response = await _request(
        '/api/market/${Uri.encodeComponent(instrument)}/candles?interval=${interval.wireName}');
    final map = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    final rows = map['candles'];
    return rows is List
        ? rows.whereType<Map>().map((row) => MarketCandle.fromJson(Map<String, dynamic>.from(row))).toList()
        : const [];
  }

  Future<List<MarketCandle>> marketHourlyCandles(String instrument) =>
      marketCandles(instrument, interval: MarketCandleInterval.hourly);

  Future<List<MarketCandle>> marketDailyCandles(String instrument) =>
      marketCandles(instrument, interval: MarketCandleInterval.daily);

  Future<EarthState> submitOrder(String product, String limitPrice,
      {String side = 'buy', String quantity = '1'}) async {
    await _request('/api/market/orders', method: 'POST', body: {
      'product': product,
      'quantity': quantity,
      'limitPrice': limitPrice,
      'side': side,
      'correlationId':
        newClientCorrelationId('market-order-$product'),
    });
    return world();
  }

  Future<MarketOrderPage> marketOrders({String? cursor, int limit = 100}) async {
    final params = <String>['limit=${limit.clamp(1, 200)}'];
    if (cursor != null && cursor.isNotEmpty) {
      params.add('cursor=${Uri.encodeQueryComponent(cursor)}');
    }
    final response = await _request('/api/market/orders/my?${params.join('&')}');
    final map = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    final rows = map['orders'];
    return MarketOrderPage(
      orders: rows is List
          ? rows.whereType<Map>().map((row) => MarketOrder.fromJson(Map<String, dynamic>.from(row))).toList()
          : const [],
      nextCursor: map['nextCursor']?.toString(),
    );
  }

  Future<MarketQuote> quoteOrder({
    required String product,
    required String quantity,
    required String limitPrice,
    String side = 'buy',
  }) async {
    final response = await _request('/api/market/order-quote', method: 'POST', body: {
      'product': product,
      'quantity': quantity,
      'limitPrice': limitPrice,
      'side': side,
    });
    if (response is Map<String, dynamic>) return MarketQuote.fromJson(response);
    if (response is Map) return MarketQuote.fromJson(Map<String, dynamic>.from(response));
    return MarketQuote.failure('Market quote unavailable');
  }

  Future<EarthState> cancelOrder(String orderId) async {
    await _request('/api/market/orders/$orderId', method: 'DELETE');
    return world();
  }

  Future<List<HouseCommodityPosition>> marketHousePositions() async {
    final response = await _request('/api/market/positions');
    final map = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    final rows = map['positions'];
    return rows is List
        ? rows.whereType<Map>().map((row) => HouseCommodityPosition.fromJson(Map<String, dynamic>.from(row))).toList()
        : const [];
  }
}
