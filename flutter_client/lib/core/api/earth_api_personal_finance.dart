part of 'earth_api.dart';

extension EarthApiPersonalFinance on EarthApi {
  Future<Map<String, dynamic>> personalFinance() async {
    final response = await _request('/api/finance/personal');
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
