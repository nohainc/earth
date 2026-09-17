part of 'earth_api.dart';

extension EarthApiRealEstate on EarthApi {
  Future<Map<String, dynamic>> territoryRights({required String territoryId}) async {
    final response = await _request('/api/territories/${Uri.encodeComponent(territoryId)}/rights');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> commonsStatement({required String territoryId}) async {
    final response = await _request('/api/territories/${Uri.encodeComponent(territoryId)}/commons');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> acquireTerritoryRight({required String territoryId, String slotQuantity = '1', int termDays = 30}) async {
    final response = await _request('/api/real-estate/rights', method: 'POST', body: {
      'territoryId': territoryId,
      'slotClass': 'PRIVATE',
      'slotQuantity': slotQuantity,
      'termDays': termDays,
      'correlationId': newClientCorrelationId('ACQUIRE-RIGHT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> releaseTerritoryRight({required String rightId}) async {
    final response = await _request('/api/real-estate/rights/${Uri.encodeComponent(rightId)}/release', method: 'POST', body: {
      'correlationId': newClientCorrelationId('RELEASE-RIGHT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getBuildingCapitalOptions({required String buildingId}) async {
    final response = await _request('/api/real-estate/buildings/$buildingId/capital-options');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> startBuildingCapitalProject({required String buildingId, required String projectKind, String? targetGenerationId}) async {
    final response = await _request('/api/real-estate/buildings/$buildingId/capital-projects', method: 'POST', body: {
      'projectKind': projectKind,
      if (targetGenerationId != null) 'targetGenerationId': targetGenerationId,
      'correlationId': newClientCorrelationId('CAPITAL-PROJECT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }
  Future<EarthState> purchaseBuilding({
    required String buildingType,
    required String name,
    required String territoryId,
  }) async {
    final res = await _request(
      '/api/real-estate/purchase',
      method: 'POST',
      body: {
        'buildingType': buildingType,
        'name': name,
        'territoryId': territoryId,
        'correlationId': newClientCorrelationId('PURCHASE-BLD'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  /// Starts a V5 pooled-capacity construction project.
  ///
  /// V5 resolves the active Corporation affiliation and all capacity, rent,
  /// tax, and material requirements on the server. No Territory placement is
  /// accepted because buildings consume pooled institutional capacity.
  Future<EarthState> purchaseV5Building({
    required String buildingType,
    required String name,
  }) async {
    final res = await _request(
      '/api/v5/buildings',
      method: 'POST',
      body: {
        'buildingType': buildingType,
        'name': name,
        'correlationId': newClientCorrelationId('V5-BUILDING'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> quoteV5Building(String buildingType) async {
    final response = await _request('/api/v5/buildings/quote',
        method: 'POST', body: {'buildingType': buildingType});
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{
            'ok': false,
            'error': 'V5 construction quote unavailable',
          };
  }

  Future<EarthState> upgradeBuilding({
    required String buildingId,
  }) async {
    final res = await _request(
      '/api/v5/buildings/$buildingId/upgrade',
      method: 'POST',
      body: {
        'buildingId': buildingId,
        'correlationId': newClientCorrelationId('UPGRADE-BLD'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> quoteBuildingUpgrade({required String buildingId}) async {
    final response = await _request('/api/v5/buildings/$buildingId/upgrade-quote');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<EarthState> setBuildingOperatingPolicy({
    required String buildingId,
    required String policy,
  }) async {
    final res = await _request(
      '/api/real-estate/policy',
      method: 'POST',
      body: {
        'buildingId': buildingId,
        'policy': policy,
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> quoteBuildingOperatingPolicy({required String buildingId}) async {
    final response = await _request('/api/real-estate/buildings/$buildingId/policy-quote');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<EarthState> demolishBuilding({
    required String buildingId,
  }) async {
    final res = await _request(
      '/api/real-estate/demolish',
      method: 'POST',
      body: {'buildingId': buildingId},
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> quoteBuildingDemolition({required String buildingId}) async {
    final response = await _request('/api/real-estate/buildings/$buildingId/demolition-quote');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<EarthState> contributeCorporateResearch({
    required String poolId,
    required double credits,
    required double compute,
  }) async {
    final res = await _request(
      '/api/research/contribute',
      method: 'POST',
      body: {
        'poolId': poolId,
        'credits': credits,
        'compute': compute,
        'correlationId': newClientCorrelationId('CORP-RD'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

}
