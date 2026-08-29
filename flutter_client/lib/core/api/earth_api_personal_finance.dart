part of 'earth_api.dart';

extension EarthApiPersonalFinance on EarthApi {
  Future<Map<String, dynamic>> personalFinance() async {
    final response = await _request('/api/finance/personal');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }
}
