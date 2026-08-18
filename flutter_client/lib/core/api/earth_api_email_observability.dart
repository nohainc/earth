part of 'earth_api.dart';

extension EarthApiEmailObservability on EarthApi {
  Future<Map<String, dynamic>> getEmailDeliveries({int limit = 50}) async {
    final res = await _request('/api/admin/email-deliveries?limit=$limit');
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'error': 'Invalid email deliveries response'};
  }

  Future<Map<String, dynamic>> getEmailHealth() async {
    final res = await _request('/api/health/email');
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'error': 'Invalid email health response'};
  }
}
