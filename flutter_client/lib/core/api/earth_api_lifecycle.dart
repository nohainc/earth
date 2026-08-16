part of 'earth_api.dart';

extension EarthApiLifecycle on EarthApi {
  // --- Lifecycle ---

  Future<EarthState> registerSuccessor(String name,
      {String? successorHumanId}) async {
    await _request('/api/successor', method: 'POST', body: {
      'name': name,
      if (successorHumanId != null && successorHumanId.isNotEmpty)
        'successorHumanId': successorHumanId,
    });
    return world();
  }

}
