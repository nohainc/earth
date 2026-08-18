part of 'earth_api.dart';

extension EarthApiNetWorth on EarthApi {
  Future<Map<String, dynamic>> getNetWorthHistory() async {
    final response = await _request('/api/finance/net-worth-history');
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return {'ok': false, 'error': 'Unexpected response format'};
  }
}
