part of 'earth_api.dart';

extension EarthApiDailySummary on EarthApi {
  Future<Map<String, dynamic>> getDailySummary({int? day}) async {
    final res = await _request('/api/house/daily-summary${day == null ? '' : '?day=$day'}');
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'error': 'Invalid daily summary response'};
  }
}
