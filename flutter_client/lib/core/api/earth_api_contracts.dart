part of 'earth_api.dart';

extension EarthApiContracts on EarthApi {

  Future<EarthState> createContract(
      String kind, String counterpartyId, String title, double amount) async {
    await _request('/api/contracts', method: 'POST', body: {
      'kind': kind,
      'counterpartyId': counterpartyId.trim(),
      'title': title.trim(),
      'amount': amount,
      'durationDays': 30,
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
