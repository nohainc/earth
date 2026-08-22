part of 'earth_api.dart';

extension EarthApiBusiness on EarthApi {
  // --- Business & Finance ---

  Future<Map<String, dynamic>> businessOwnership(String businessId) async =>
      (await _request('/api/businesses/$businessId/ownership'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> businessFinancials(String businessId) async =>
      (await _request('/api/businesses/$businessId/financials'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> businessProfile(String businessId) async =>
      (await _request('/api/businesses/$businessId')) as Map<String, dynamic>;

  Future<EarthState> renameBusiness(String businessId, String name) async {
    await _request('/api/businesses/$businessId/name', method: 'POST', body: {'name': name.trim()});
    return world();
  }

  Future<EarthState> setPolicy(String policy, {String? businessId}) async {
    await _request('/api/businesses/me/policy',
        method: 'POST', body: {'policy': policy, if (businessId != null) 'businessId': businessId});
    return world();
  }

  Future<EarthState> updateBusinessConstitution(
      String businessId,
      double shareholderVoteThreshold,
      double boardApprovalThreshold,
      int dilutionNoticeDays) async {
    await _request('/api/businesses/$businessId/constitution',
        method: 'POST',
        body: {
          'shareholderVoteThreshold': shareholderVoteThreshold,
          'boardApprovalThreshold': boardApprovalThreshold,
          'dilutionNoticeDays': dilutionNoticeDays,
        });
    return world();
  }

  Future<EarthState> appointBusinessManager(
      String businessId, String managerId) async {
    await _request('/api/businesses/$businessId/manager',
        method: 'POST', body: {'managerId': managerId.trim()});
    return world();
  }

  Future<EarthState> hireEmployee(
      String businessId, String name, String role, double wage) async {
    await _request('/api/businesses/$businessId/employees',
        method: 'POST',
        body: {
          'name': name.trim(),
          'role': role.trim(),
          'wage': wage,
          'correlationId':
              'employee-hire-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> trainEmployee(
      String businessId, String employeeId) async {
    await _request('/api/businesses/$businessId/employees/$employeeId/train',
        method: 'POST',
        body: {
          'correlationId':
              'employee-train-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> dismissEmployee(
      String businessId, String employeeId) async {
    await _request('/api/businesses/$businessId/employees/$employeeId/dismiss',
        method: 'POST',
        body: {
          'correlationId':
              'employee-dismiss-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> reassignEmployee(
      String businessId, String employeeId, String role, double wage) async {
    await _request('/api/businesses/$businessId/employees/$employeeId/reassign',
        method: 'POST',
        body: {
          'role': role.trim(),
          'wage': wage,
          'correlationId': 'employee-reassign-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> createBusiness(String name, String sector) async {
    await _request('/api/businesses', method: 'POST', body: {
      'name': name,
      'sector': sector,
      'correlationId':
          'business-registration-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> liquidateBusiness(String businessId,
      {String otp = ''}) async {
    await _request('/api/businesses/$businessId/liquidate',
        method: 'POST',
        body: {
          if (otp.trim().isNotEmpty) 'otp': otp.trim(),
        });
    return world();
  }

  Future<EarthState> transferShares(String recipientId, int shares,
      {String? otp, String? businessId}) async {
    await _request('/api/businesses/me/shares/transfer', method: 'POST', body: {
      'recipientId': recipientId.trim(),
      'shares': shares,
      if (businessId != null && businessId.trim().isNotEmpty)
        'businessId': businessId.trim(),
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  Future<EarthState> issueShares(
      String businessId, String recipientId, int shares, double pricePerShare,
      {String? otp}) async {
    await _request('/api/businesses/$businessId/shares/issue',
        method: 'POST',
        body: {
          'recipientId': recipientId.trim(),
          'shares': shares,
          'pricePerShare': pricePerShare,
          if (otp != null && otp.isNotEmpty) 'otp': otp,
        });
    return world();
  }

  Future<EarthState> settleTax(double taxableAmount) async {
    await _request('/api/taxes/settle', method: 'POST', body: {
      'taxableAmount': taxableAmount,
    });
    return world();
  }

  Future<EarthState> spendPublicFinance(
      String cityId, String category, double amount) async {
    final correlationId =
        'public-spending-${DateTime.now().microsecondsSinceEpoch}';
    await _request('/api/finance/public-spending', method: 'POST', body: {
      'cityId': cityId,
      'category': category,
      'amount': amount,
      'correlationId': correlationId,
    });
    return world();
  }

  Future<EarthState> recoverInstitution(String institutionId, double amount,
      {String? otp}) async {
    await _request('/api/finance/recover', method: 'POST', body: {
      'institutionId': institutionId,
      'amount': amount,
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  Future<EarthState> declarePersonalInsolvency({String reason = ''}) async {
    await _request('/api/finance/personal/declare', method: 'POST', body: {
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return world();
  }

  Future<EarthState> distributeDividends(
      String businessId, double amount) async {
    await _request('/api/businesses/$businessId/dividends',
        method: 'POST',
        body: {
          'amount': amount,
          'correlationId':
              'dividends-$businessId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<Map<String, dynamic>> proposeMerger({
    required String acquirerBusinessId,
    required String targetBusinessId,
    required double pricePerShare,
  }) async {
    return (await _request(
      '/api/businesses/$acquirerBusinessId/merger/propose',
      method: 'POST',
      body: {
        'targetBusinessId': targetBusinessId.trim(),
        'pricePerShare': pricePerShare,
        'correlationId':
            'merger-$acquirerBusinessId-${DateTime.now().microsecondsSinceEpoch}',
      },
    )) as Map<String, dynamic>;
  }

  Future<EarthState> executeMerger(String mergerId) async {
    await _request('/api/businesses/merger/$mergerId/execute',
        method: 'POST',
        body: {
          'correlationId':
              'merger-execute-$mergerId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

}
