part of 'earth_api.dart';

extension EarthApiResidency on EarthApi {
  Future<Map<String, dynamic>> getHouseResidency() async {
    final response = await _request('/api/house/residency');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> quoteHouseMove({required String territoryId}) async {
    final response = await _request('/api/house/residency/quote?territoryId=${Uri.encodeQueryComponent(territoryId)}');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> moveHouseResidence({required String territoryId}) async {
    final response = await _request('/api/house/residency/move', method: 'POST', body: {
      'territoryId': territoryId,
      'correlationId': newClientCorrelationId('MOVE-RESIDENCE'),
    });
    return Map<String, dynamic>.from(response as Map);
  }
}
