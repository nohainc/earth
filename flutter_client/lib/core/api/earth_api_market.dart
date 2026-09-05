part of 'earth_api.dart';

extension EarthApiMarket on EarthApi {
  // --- Market ---

  Future<EarthState> submitOrder(String product, double limitPrice,
      {String side = 'buy', int quantity = 1}) async {
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

  Future<EarthState> settleMarket(String product) async {
    await _request('/api/market/settle',
        method: 'POST', body: {'product': product});
    return world();
  }

  Future<EarthState> cancelOrder(String orderId) async {
    await _request('/api/market/orders/$orderId', method: 'DELETE');
    return world();
  }

  Future<Map<String, dynamic>> marketPriceHistory(String product,
      {int days = 30}) async {
    final encodedProduct = Uri.encodeQueryComponent(product.trim());
    return (await _request(
            '/api/market/history?product=$encodedProduct&days=$days'))
        as Map<String, dynamic>;
  }
}
