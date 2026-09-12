part of 'earth_api.dart';

extension EarthApiLifecycle on EarthApi {
  // --- Lifecycle ---

  Future<Map<String, dynamic>> lifeStatus() async {
    final response = await _request('/api/life/status');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<EarthState> registerSuccessor(
    String name,
  ) async {
    await _request('/api/life/successor', method: 'POST', body: {
      'name': name.trim(),
    });
    return world();
  }
}
