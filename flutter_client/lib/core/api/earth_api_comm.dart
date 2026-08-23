part of 'earth_api.dart';

extension EarthApiComm on EarthApi {
  // --- Communications & Diplomatic Mail ---

  Future<List<dynamic>> commChannels() async {
    final response =
        (await _request('/api/comm/channels')) as Map<String, dynamic>;
    return (response['channels'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> commMessages({
    String channelId = 'channel-global-relay',
    int limit = 50,
  }) async {
    final uri = Uri(
      path: '/api/comm/messages',
      queryParameters: {
        'channelId': channelId,
        'limit': limit.toString(),
      },
    );
    final response = (await _request(uri.toString())) as Map<String, dynamic>;
    return (response['messages'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> sendCommMessage({
    required String channelId,
    required String body,
    List<dynamic> attachments = const [],
    int? gameDay,
    int? gameMinute,
  }) async {
    final payload = {
      'channelId': channelId,
      'body': body,
      'attachments': attachments,
      if (gameDay != null) 'gameDay': gameDay,
      if (gameMinute != null) 'gameMinute': gameMinute,
    };
    return (await _request('/api/comm/messages',
        method: 'POST', body: payload)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commDispatches({
    String folder = 'inbox',
    int limit = 30,
    int offset = 0,
  }) async {
    final uri = Uri(
      path: '/api/comm/dispatches',
      queryParameters: {
        'folder': folder,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    return (await _request(uri.toString())) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendCommDispatch({
    required String recipientId,
    required String subject,
    required String body,
    String dispatchType = 'diplomatic',
    Map<String, dynamic> actionPayload = const {},
    int? gameDay,
    int? gameMinute,
  }) async {
    final payload = {
      'recipientId': recipientId,
      'subject': subject,
      'body': body,
      'dispatchType': dispatchType,
      'actionPayload': actionPayload,
      if (gameDay != null) 'gameDay': gameDay,
      if (gameMinute != null) 'gameMinute': gameMinute,
    };
    return (await _request('/api/comm/dispatches',
        method: 'POST', body: payload)) as Map<String, dynamic>;
  }

  Future<void> markCommDispatchRead(String dispatchId) async {
    await _request(
      '/api/comm/dispatches/read',
      method: 'POST',
      body: {'dispatchId': dispatchId},
    );
  }

  Future<void> archiveCommDispatch(String dispatchId, {bool archived = true}) async {
    await _request(
      '/api/comm/dispatches/archive',
      method: 'POST',
      body: {'dispatchId': dispatchId, 'archived': archived},
    );
  }

  Future<Map<String, dynamic>> commMetrics() async {
    return (await _request('/api/comm/metrics')) as Map<String, dynamic>;
  }

  Future<List<dynamic>> socialInitiatives() async {
    final response = (await _request('/api/social/initiatives')) as Map<String, dynamic>;
    return (response['initiatives'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> socialDirectory({String query = ''}) async {
    final uri = Uri(path: '/api/social/directory', queryParameters: {'q': query});
    return (await _request(uri.toString())) as Map<String, dynamic>;
  }

  Future<List<dynamic>> socialRelationships() async => ((await _request('/api/social/relationships')) as Map<String, dynamic>)['relationships'] as List<dynamic>? ?? const [];
  Future<List<dynamic>> socialTimeline({int limit = 50}) async => ((await _request('/api/social/timeline?limit=$limit')) as Map<String, dynamic>)['timeline'] as List<dynamic>? ?? const [];

  Future<Map<String, dynamic>> createSocialInitiative({required String kind, required String title, required String body, String? targetId, Map<String, dynamic> terms = const {}}) async =>
      (await _request('/api/social/initiatives', method: 'POST', body: {'kind': kind, 'title': title, 'body': body, if (targetId != null) 'targetId': targetId, 'terms': terms})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> respondToSocialInitiative(String id, {required bool accept}) async =>
      (await _request('/api/social/initiatives/$id/${accept ? 'accept' : 'decline'}', method: 'POST')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> contributeToSocialInitiative(String id, int contribution) async =>
      (await _request('/api/social/initiatives/$id/contribute', method: 'POST', body: {'contribution': contribution})) as Map<String, dynamic>;
}
