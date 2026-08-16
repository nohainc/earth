part of 'earth_api.dart';

extension EarthApiContracts on EarthApi {

  Future<List<dynamic>> contracts() async {
    final response = await _request('/api/contracts');
    if (response is Map<String, dynamic>) {
      return (response['contracts'] as List<dynamic>?) ?? const [];
    }
    return response is List<dynamic> ? response : const [];
  }

  Future<Map<String, dynamic>> contract(String contractId) async {
    final response = await _request('/api/contracts/$contractId');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<EarthState> createContract(
      String kind, String counterpartyId, String title, double amount,
      {Map<String, dynamic>? terms, int durationDays = 30}) async {
    await _request('/api/contracts', method: 'POST', body: {
      'kind': kind,
      'counterpartyId': counterpartyId.trim(),
      'title': title.trim(),
      'amount': amount,
      'durationDays': durationDays,
      if (terms != null) 'terms': terms,
    });
    return world();
  }

  Future<EarthState> acceptContract(String contractId) async {
    await _request('/api/contracts/$contractId/accept', method: 'POST');
    return world();
  }

  Future<EarthState> cancelContract(String contractId) async {
    await _request('/api/contracts/$contractId/cancel', method: 'POST');
    return world();
  }

  Future<EarthState> disputeContract(String contractId, String reason) async {
    await _request('/api/contracts/$contractId/dispute',
        method: 'POST', body: {'reason': reason.trim()});
    return world();
  }

  Future<EarthState> resolveContract(
      String contractId, String outcome, String resolution) async {
    await _request('/api/contracts/$contractId/resolve', method: 'POST', body: {
      'outcome': outcome,
      'resolution': resolution.trim(),
    });
    return world();
  }
}
