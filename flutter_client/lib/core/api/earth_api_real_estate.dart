part of 'earth_api.dart';

extension EarthApiRealEstate on EarthApi {
  Future<EarthState> purchaseBuilding({
    required String buildingType,
    required String name,
    String? cityId,
  }) async {
    final res = await _request(
      '/api/real-estate/purchase',
      method: 'POST',
      body: {
        'buildingType': buildingType,
        'name': name,
        if (cityId != null) 'cityId': cityId,
        'correlationId': newClientCorrelationId('PURCHASE-BLD'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> upgradeBuilding({
    required String buildingId,
  }) async {
    final res = await _request(
      '/api/real-estate/upgrade',
      method: 'POST',
      body: {
        'buildingId': buildingId,
        'correlationId': newClientCorrelationId('UPGRADE-BLD'),
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> completeBuildingConstruction({
    required String buildingId,
  }) async {
    final res = await _request(
      '/api/real-estate/complete-construction',
      method: 'POST',
      body: {'buildingId': buildingId},
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> repairBuilding({
    required String buildingId,
  }) async {
    final res = await _request(
      '/api/real-estate/repair',
      method: 'POST',
      body: {'buildingId': buildingId},
    );
    return EarthState(res as Map<String, dynamic>);
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

  Future<EarthState> setBuildingAutoRepair({
    required String buildingId,
    required bool enabled,
  }) async {
    final res = await _request(
      '/api/real-estate/auto-repair',
      method: 'POST',
      body: {
        'buildingId': buildingId,
        'enabled': enabled,
      },
    );
    return EarthState(res as Map<String, dynamic>);
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

  Future<EarthState> contributeCorporateResearch({
    required String poolId,
    required double credits,
    required double compute,
  }) async {
    final res = await _request(
      '/api/corporate-research/contribute',
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
