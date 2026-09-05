part of 'earth_api.dart';

extension EarthApiComm on EarthApi {
  // --- Communications ---

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
  }) async {
    final payload = {
      'channelId': channelId,
      'body': body,
      'attachments': attachments,
    };
    return (await _request('/api/comm/messages', method: 'POST', body: payload))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> openDirectConversation(
      String targetHumanId) async {
    return (await _request('/api/comm/direct', method: 'POST', body: {
      'targetHumanId': targetHumanId,
    })) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commMetrics() async {
    return (await _request('/api/comm/metrics')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> socialDirectory({String query = ''}) async {
    final uri =
        Uri(path: '/api/social/directory', queryParameters: {'q': query});
    return (await _request(uri.toString())) as Map<String, dynamic>;
  }
}
