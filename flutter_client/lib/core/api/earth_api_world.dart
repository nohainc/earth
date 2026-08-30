part of 'earth_api.dart';

extension EarthApiWorld on EarthApi {
  // --- World & Operating Cycle ---

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);

  Future<EarthState> advanceDay() async {
    await _request('/api/day/advance', method: 'POST');
    return world();
  }

  Future<void> recalculateWorld() async {
    await _request('/api/world/recalculate', method: 'POST');
  }

  Future<List<dynamic>> events() async {
    final response =
        (await _request('/api/events?limit=20')) as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> notifications() async =>
      (await _request('/api/notifications?limit=20')) as Map<String, dynamic>;

  Future<void> markNotificationRead(String id) async {
    await _request('/api/notifications/$id/read', method: 'POST');
  }

  Future<void> markAllNotificationsRead() async {
    await _request('/api/notifications/read-all', method: 'POST');
  }

  Future<List<dynamic>> publicActivity() async {
    final response = await _request('/api/world/activity');
    if (response is Map<String, dynamic>) {
      return (response['activity'] as List<dynamic>?) ?? const [];
    }
    return response is List<dynamic> ? response : const [];
  }

  Future<List<dynamic>> ownershipEvents() async {
    final response = (await _request('/api/ownership/events?limit=20'))
        as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> membershipEvents() async {
    final response = (await _request('/api/membership/events?limit=20'))
        as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> authorityEvents() async {
    final response =
        (await _request('/api/governance/authority/events?limit=20'))
            as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> pantheon() async =>
      (await _request('/api/pantheon')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> cemetery(
      {String? search, String? house, String? dynasty, int limit = 50}) async {
    final houseFilter = house?.trim() ?? dynasty?.trim();
    final params = <String, String>{
      'limit': limit.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (houseFilter != null && houseFilter.isNotEmpty) 'house': houseFilter,
    };
    final uri = Uri(path: '/api/cemetery', queryParameters: params);
    return (await _request(uri.toString())) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rankings({
    String? category,
    String? metric,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      if (metric != null && metric.trim().isNotEmpty)
        'metric': metric.trim(),
      if (search != null && search.trim().isNotEmpty)
        'search': search.trim(),
    };
    final uri = Uri(path: '/api/rankings', queryParameters: params);
    return (await _request(uri.toString())) as Map<String, dynamic>;
  }

  Future<List<dynamic>> worldHistory({int limit = 30}) async {
    final response =
        (await _request('/api/history?limit=$limit')) as Map<String, dynamic>;
    return (response['history'] as List<dynamic>?) ?? const [];
  }
}
