part of 'earth_api.dart';

extension EarthApiDerivatives on EarthApi {
  Future<Map<String, dynamic>> derivativesOverview({String commodity = 'energy'}) async {
    final response = await _request('/api/market/derivatives?commodity=${Uri.encodeComponent(commodity)}');
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> createFuturesListing({
    required String commodity,
    required double size,
    required double strikePrice,
    required int durationGameMinutes,
  }) async {
    final response = await _request(
      '/api/market/futures/create',
      method: 'POST',
      body: {
        'commodity': commodity,
        'size': size,
        'strikePrice': strikePrice,
        'durationGameMinutes': durationGameMinutes,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> buyFuturesContract(String contractId) async {
    final response = await _request(
      '/api/market/futures/$contractId/buy',
      method: 'POST',
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> cancelFuturesContract(String contractId) async {
    final response = await _request(
      '/api/market/futures/$contractId/cancel',
      method: 'POST',
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }
}
