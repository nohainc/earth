part of 'earth_api.dart';

extension EarthApiWorld on EarthApi {
  // --- World & Simulation ---

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);

  Future<EarthState> advanceDay() async {
    await _request('/api/day/advance', method: 'POST');
    return world();
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

  Future<List<dynamic>> productionCatalog() async {
    final response =
        (await _request('/api/production/catalog')) as Map<String, dynamic>;
    return (response['sectors'] as List<dynamic>?) ?? const [];
  }

}

