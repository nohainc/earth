part of 'earth_api.dart';

extension EarthApiMap on EarthApi {
  Future<Map<String, dynamic>> planetaryRegions() async {
    final response = await _request('/api/map/regions');
    if (response is Map<String, dynamic>) {
      return response;
    }
    return {'ok': false, 'regions': <dynamic>[], 'plots': <dynamic>[]};
  }

  Future<Map<String, dynamic>> claimPlotLease({
    required String plotId,
    int durationDays = 30,
    String? correlationId,
  }) async {
    final response = await _request(
      '/api/map/plots/$plotId/lease',
      method: 'POST',
      body: {
        'durationDays': durationDays,
        if (correlationId != null) 'correlationId': correlationId,
      },
    );
    return response is Map<String, dynamic> ? response : {'ok': true};
  }

  Future<Map<String, dynamic>> upgradePlotInfrastructure({
    required String plotId,
    String? correlationId,
  }) async {
    final response = await _request(
      '/api/map/plots/$plotId/upgrade',
      method: 'POST',
      body: {
        if (correlationId != null) 'correlationId': correlationId,
      },
    );
    return response is Map<String, dynamic> ? response : {'ok': true};
  }

  Future<Map<String, dynamic>> harvestPlotYield({
    required String plotId,
    String? correlationId,
  }) async {
    final response = await _request(
      '/api/map/plots/$plotId/harvest',
      method: 'POST',
      body: {
        if (correlationId != null) 'correlationId': correlationId,
      },
    );
    return response is Map<String, dynamic> ? response : {'ok': true};
  }
}
