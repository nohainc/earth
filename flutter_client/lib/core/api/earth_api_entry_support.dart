part of 'earth_api.dart';

extension EarthApiEntrySupport on EarthApi {
  Future<Map<String, dynamic>> houseEntryOpportunities() async {
    final response = await _request('/api/house/entry-opportunities');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> claimHouseEntrySupport() async {
    final response =
        await _request('/api/house/entry-support/claim', method: 'POST', body: {
      'correlationId': newClientCorrelationId('ENTRY-SUPPORT'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> houseCatchUpTargets() async {
    final response = await _request('/api/house/catch-up-targets');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }
}
