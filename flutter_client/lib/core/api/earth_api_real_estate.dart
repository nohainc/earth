part of 'earth_api.dart';

extension EarthApiRealEstate on EarthApi {
  Future<EarthState> purchaseBuilding({
    required String buildingType,
    required String name,
    String? cityId,
    String? businessId,
  }) async {
    final res = await _request(
      '/api/real-estate/purchase',
      method: 'POST',
      body: {
        'buildingType': buildingType,
        'name': name,
        if (cityId != null) 'cityId': cityId,
        if (businessId != null) 'businessId': businessId,
        'correlationId': 'PURCHASE-BLD-${DateTime.now().millisecondsSinceEpoch}',
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
        'correlationId': 'UPGRADE-BLD-${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> assignBuildingStaff({
    required String buildingId,
    required String staffType,
    String? machineId,
    String? employeeId,
  }) async {
    final res = await _request(
      '/api/real-estate/assign-staff',
      method: 'POST',
      body: {
        'buildingId': buildingId,
        'staffType': staffType,
        if (machineId != null) 'machineId': machineId,
        if (employeeId != null) 'employeeId': employeeId,
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> registerMunicipalLabor({
    required String machineId,
  }) async {
    final res = await _request(
      '/api/municipal-labor/register',
      method: 'POST',
      body: {'machineId': machineId},
    );
    return EarthState(res as Map<String, dynamic>);
  }

  Future<EarthState> withdrawMunicipalLabor({
    required String machineId,
  }) async {
    final res = await _request(
      '/api/municipal-labor/withdraw',
      method: 'POST',
      body: {'machineId': machineId},
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
        'correlationId': 'CORP-RD-${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    return EarthState(res as Map<String, dynamic>);
  }
}
