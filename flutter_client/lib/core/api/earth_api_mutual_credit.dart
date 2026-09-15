part of 'earth_api.dart';

/// Client access to the optional mutual-credit experiment. These units are
/// intentionally kept separate from the global CREDIT balance in the UI.
extension EarthApiMutualCredit on EarthApi {
  Future<Map<String, dynamic>> mutualCreditNetworks() async {
    final response = await _request('/api/mutual-credit/networks');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> mutualCreditNetwork(String networkId) async {
    final response = await _request('/api/mutual-credit/networks/$networkId');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> joinMutualCreditNetwork(String networkId,
      {String? creditLimitUnits}) async {
    final response = await _request('/api/mutual-credit/networks/$networkId/join',
        method: 'POST',
        body: {
          if (creditLimitUnits != null) 'creditLimitUnits': creditLimitUnits,
          'correlationId': newClientCorrelationId('mutual-credit-join'),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> transferMutualCredit(String networkId,
      {required String toHouseId, required String amountUnits}) async {
    final response = await _request(
        '/api/mutual-credit/networks/$networkId/transfers',
        method: 'POST',
        body: {
          'toHouseId': toHouseId,
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('mutual-credit-transfer'),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> guaranteeMutualCredit(String networkId,
      {required String memberHouseId, required String guaranteedUnits}) async {
    final response = await _request(
        '/api/mutual-credit/networks/$networkId/guarantees',
        method: 'POST',
        body: {
          'memberHouseId': memberHouseId,
          'guaranteedUnits': guaranteedUnits,
          'correlationId': newClientCorrelationId('mutual-credit-guarantee'),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }
}
