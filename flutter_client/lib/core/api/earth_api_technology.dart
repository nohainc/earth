part of 'earth_api.dart';

extension EarthApiTechnology on EarthApi {
  // --- Technology & AI ---

  Future<EarthState> startResearch(String name) async {
    await _request('/api/technology/projects', method: 'POST', body: {
      'name': name,
      'correlationId': newClientCorrelationId('research-project'),
    });
    return world();
  }

  Future<Map<String, dynamic>> quoteResearch(String name) async {
    final response = await _request('/api/technology/projects/quote',
        method: 'POST', body: {'name': name});
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Research quote unavailable'};
  }

  Future<EarthState> startCorporationBuildingResearch(
      String buildingType) async {
    await _request('/api/research/buildings', method: 'POST', body: {
      'buildingType': buildingType,
      'correlationId': newClientCorrelationId('corporation-building-research'),
    });
    return world();
  }

  Future<Map<String, dynamic>> quoteCorporationBuildingResearch(
      String buildingType) async {
    try {
      final response = await _request('/api/research/buildings/quote',
          method: 'POST', body: {'buildingType': buildingType});
      return response is Map<String, dynamic>
          ? response
          : <String, dynamic>{
              'ok': false,
              'error': 'Building research quote unavailable',
            };
    } catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': 'Building research quote unavailable: $e',
      };
    }
  }

  Future<Map<String, dynamic>> proposeCorporationBuildingResearch({
    required String corporationId,
    required String buildingType,
    required int targetTier,
    required int effectiveFromGameDay,
    required String title,
    required String body,
  }) async {
    final response = await _request('/api/governance/v5/proposals',
        method: 'POST',
        body: {
          'subjectType': 'CORPORATION',
          'subjectId': corporationId,
          'actionType': 'CORPORATION_BUILDING_RESEARCH',
          'payload': {
            'corporationId': corporationId,
            'buildingType': buildingType,
            'targetTier': targetTier,
            'effectiveFromGameDay': effectiveFromGameDay,
          },
          'title': title,
          'body': body,
          'correlationId': newClientCorrelationId('corporation-building-research-proposal'),
        });
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Building research proposal failed'};
  }
}
