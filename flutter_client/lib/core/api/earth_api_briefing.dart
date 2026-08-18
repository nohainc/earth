part of 'earth_api.dart';

extension EarthApiBriefing on EarthApi {
  Future<Map<String, dynamic>> getDailyBriefing() async {
    final res = await _request('/api/player/daily-briefing');
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'error': 'Invalid daily briefing response'};
  }
}
