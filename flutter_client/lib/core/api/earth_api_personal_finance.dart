part of 'earth_api.dart';

extension EarthApiPersonalFinance on EarthApi {
  Future<Map<String, dynamic>> personalFinance() async {
    final responses = await Future.wait([
      _request('/api/finance/personal'),
      _request('/api/economy/balances'),
    ]);
    final legacy = responses[0] is Map<String, dynamic>
        ? Map<String, dynamic>.from(responses[0] as Map<String, dynamic>)
        : <String, dynamic>{};
    if (responses[1] is Map<String, dynamic>) legacy['economic'] = responses[1];
    return legacy;
  }

  /// Canonical Economy V2 balances in display units. Storage precision stays
  /// entirely behind the API boundary.
  Future<Map<String, dynamic>> economicBalances() async {
    final response = await _request('/api/economy/balances');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> economicTransactions({int limit = 50, int? beforeId}) async {
    final query = StringBuffer('/api/economy/transactions?limit=${limit.clamp(1, 100)}');
    if (beforeId != null) query.write('&beforeId=$beforeId');
    final response = await _request(query.toString());
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> recoverInstitution(
      String institutionId, double amount, {String? otp}) async {
    final response = await _request('/api/finance/recover', method: 'POST', body: {
      'institutionId': institutionId,
      'amount': amount,
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> bankDeposits() async {
    final response = await _request('/api/finance/bank/deposits');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createBankDeposit({required double amount, required int termDays}) async {
    final response = await _request('/api/finance/bank/deposit', method: 'POST', body: {
      'amount': amount,
      'termDays': termDays,
      'correlationId': newClientCorrelationId('BANK-DEP'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> withdrawBankDeposit(String depositId) async {
    final response = await _request('/api/finance/bank/withdraw', method: 'POST', body: {
      'depositId': depositId,
      'correlationId': newClientCorrelationId('BANK-WITHDRAW'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }
}
