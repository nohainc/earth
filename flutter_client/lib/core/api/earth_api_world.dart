part of 'earth_api.dart';

extension EarthApiWorld on EarthApi {
  // --- World & Operating Cycle ---

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);

  Future<List<dynamic>> events() async {
    final response =
        (await _request('/api/events?limit=20')) as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> news({
    int limit = 25,
    String? before,
    String? scope,
    String? topic,
    String? importance,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (before != null && before.isNotEmpty) 'before': before,
      if (scope != null && scope.isNotEmpty) 'scope': scope,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
      if (importance != null && importance.isNotEmpty) 'importance': importance,
    };
    final response = await _request(
        Uri(path: '/api/news', queryParameters: params).toString());
    return response as Map<String, dynamic>;
  }

  Future<void> markNewsSeen(String publicationKey) async {
    await _request('/api/news/seen', method: 'POST', body: {
      'publicationKey': publicationKey,
    });
  }

  Future<Map<String, dynamic>> notifications() async =>
      (await _request('/api/notifications?limit=20')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> commandCenter({int limit = 20}) async =>
      (await _request('/api/command-center?limit=$limit'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> v5Overview() async {
    final response = await _request('/api/v5/command/overview');
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Invalid V5 overview response'};
  }

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

  @Deprecated('Use memorial() for the canonical V5 Memorial archive.')
  Future<Map<String, dynamic>> pantheon({
    String? search,
    String? citizenCursor,
    String? houseCursor,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (citizenCursor != null && citizenCursor.isNotEmpty)
        'citizenCursor': citizenCursor,
      if (houseCursor != null && houseCursor.isNotEmpty)
        'houseCursor': houseCursor,
    };
    final response = await _request(
        Uri(path: '/api/pantheon', queryParameters: params).toString());
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<MemorialArchivePage> memorial({
    String? search,
    String? houseStatus,
    String? citizenCursor,
    String? houseCursor,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (houseStatus != null && houseStatus.trim().isNotEmpty && houseStatus != 'ALL') 'houseStatus': houseStatus,
      if (citizenCursor != null && citizenCursor.isNotEmpty)
        'citizenCursor': citizenCursor,
      if (houseCursor != null && houseCursor.isNotEmpty)
        'houseCursor': houseCursor,
    };
    final response = await _request(
        Uri(path: '/api/memorial', queryParameters: params).toString());
    return MemorialArchivePage.fromJson(
        response is Map<String, dynamic> ? response : const {});
  }

  Future<HouseLineage> memorialHouseLineage(String houseId) async {
    final response = await _request('/api/memorial/houses/${Uri.encodeComponent(houseId)}/lineage');
    return HouseLineage.fromJson(
        response is Map<String, dynamic> ? response : const {});
  }

  Future<MemorialCitizenDetail> memorialCitizenBiography(String humanId) async {
    final response = await _request('/api/memorial/citizens/${Uri.encodeComponent(humanId)}');
    final raw = response is Map<String, dynamic> ? response : const <String, dynamic>{};
    final citizen = raw['citizen'] is Map
        ? Map<String, dynamic>.from(raw['citizen'] as Map)
        : <String, dynamic>{};
    final payload = <String, dynamic>{...raw, ...citizen};
    return MemorialCitizenDetail.fromJson(
        payload);
  }

  Future<Map<String, dynamic>> worldConditions({int? day}) async {
    final suffix = day == null ? '' : '?day=$day';
    final response = await _request('/api/world/conditions$suffix');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  @Deprecated('Use memorial() for the canonical V5 Memorial archive.')
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
      if (metric != null && metric.trim().isNotEmpty) 'metric': metric.trim(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
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
