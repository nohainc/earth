part of 'earth_api.dart';

extension EarthApiLifecycle on EarthApi {
  // --- Lifecycle ---

  Future<Map<String, dynamic>> lifeStatus() async {
    final response = await _request('/api/life/status');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<EarthState> registerSuccessor(
    String name, {
    String? successorHumanId,
    int? estatePeriodDays,
  }) async {
    await _request('/api/life/successor', method: 'POST', body: {
      'name': name.trim(),
      if (successorHumanId != null && successorHumanId.trim().isNotEmpty)
        'successorHumanId': successorHumanId.trim(),
      if (estatePeriodDays != null && estatePeriodDays > 0)
        'estatePeriodDays': estatePeriodDays,
    });
    return world();
  }

  Future<EarthState> settleInheritance({
    required String predecessorId,
    required String successorId,
    required String successorName,
  }) async {
    await _request('/api/life/successor', method: 'POST', body: {
      'name': successorName.trim(),
      'successorHumanId': successorId.trim(),
    });
    return world();
  }
}
