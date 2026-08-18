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

  Future<Map<String, dynamic>> commMetrics() async {
    return (await _request('/api/comm/metrics')) as Map<String, dynamic>;
  }
}
