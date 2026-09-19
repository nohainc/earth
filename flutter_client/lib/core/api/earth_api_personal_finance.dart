part of 'earth_api.dart';

extension EarthApiPersonalFinance on EarthApi {
  Future<Map<String, dynamic>> taxStatement() async {
    final response = await _request('/api/finance/tax-statement');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> houseFinanceOverview() async {
    final response = await _request('/api/finance/overview');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> openCapacityResolution({String? reason}) async {
    final response = await _request('/api/v5/house/capacity-resolution',
        method: 'POST',
        body: {
          'correlationId': newClientCorrelationId('V5-CAPACITY-RESOLUTION'),
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  @Deprecated('Use houseFinanceOverview')
  Future<Map<String, dynamic>> personalFinance() => houseFinanceOverview();

  /// Canonical Economy V2 balances in display units. Storage precision stays
  /// entirely behind the API boundary.
  Future<Map<String, dynamic>> economicBalances() async {
    final response = await _request('/api/economy/balances');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> economicTransactions(
      {int limit = 50, int? beforeId}) async {
    final query =
        StringBuffer('/api/economy/transactions?limit=${limit.clamp(1, 100)}');
    if (beforeId != null) query.write('&beforeId=$beforeId');
    final response = await _request(query.toString());
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> recoverInstitution(
      String institutionId, double amount,
      {String? otp}) async {
    final response =
        await _request('/api/finance/recover', method: 'POST', body: {
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

  Future<Map<String, dynamic>> bankLoans() async {
    final response = await _request('/api/finance/bank/loans');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createBankDeposit(
      {required String amount, required int termDays}) async {
    final response =
        await _request('/api/finance/bank/deposit', method: 'POST', body: {
      'amount': amount,
      'termDays': termDays,
      'correlationId': newClientCorrelationId('BANK-DEP'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> bankDepositQuote(
      {required String amount, int termDays = 30}) async {
    final response = await _request(
        '/api/finance/bank/deposit-quote?amount=${Uri.encodeQueryComponent(amount)}&termDays=$termDays');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> withdrawBankDeposit(String depositId) async {
    final response =
        await _request('/api/finance/bank/withdraw', method: 'POST', body: {
      'depositId': depositId,
      'correlationId': newClientCorrelationId('BANK-WITHDRAW'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> bankLoanQuote(
      {required String amount, int termDays = 30}) async {
    final response = await _request(
        '/api/finance/bank/loan-quote?amount=${Uri.encodeQueryComponent(amount)}&termDays=$termDays');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> originateBankLoan(
      {required String amount, int termDays = 30}) async {
    final response =
        await _request('/api/finance/bank/loan', method: 'POST', body: {
      'amount': amount,
      'termDays': termDays,
      'correlationId': newClientCorrelationId('BANK-LOAN'),
    });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> repayBankLoan(String loanId,
      {String? amount}) async {
    final response = await _request('/api/finance/bank/loan/$loanId/repay',
        method: 'POST',
        body: {
          if (amount != null) 'amount': amount,
          'correlationId': newClientCorrelationId('BANK-REPAY'),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> guaranteeBankLoan(
      {required String loanId, required String guaranteedUnits}) async {
    final response = await _request('/api/finance/bank/loan/$loanId/guarantee',
        method: 'POST',
        body: {
          'guaranteedUnits': guaranteedUnits,
          'correlationId': newClientCorrelationId('BANK-GUARANTEE'),
        });
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> bankRiskProjection() async {
    final response = await _request('/api/finance/bank/risk');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }
}
