import 'earth_api_transport.dart';
import '../models/earth_state.dart';

class EarthApi {
  final String baseUrl;
  const EarthApi({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL', defaultValue: '');

  EarthApiTransport get _transport => EarthApiTransport(baseUrl: baseUrl);

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    return _transport.request(path, method: method, body: body);
  }

  // --- Auth & Session ---

  Future<Map<String, dynamic>> session() async =>
      (await _request('/api/auth/me')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> login(String email, String password,
          {String? otp}) async =>
      (await _request('/api/auth/login', method: 'POST', body: {
        'email': email,
        'password': password,
        if (otp != null && otp.isNotEmpty) 'otp': otp,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> enrollMfa() async =>
      (await _request('/api/auth/mfa/enroll', method: 'POST'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> confirmMfa(String code) async =>
      (await _request('/api/auth/mfa/confirm',
          method: 'POST', body: {'code': code})) as Map<String, dynamic>;

  Future<void> disableMfa(String code) async {
    await _request('/api/auth/mfa/disable',
        method: 'POST', body: {'code': code});
  }

  Future<List<dynamic>> sessions() async {
    final response =
        (await _request('/api/auth/sessions')) as Map<String, dynamic>;
    return (response['sessions'] as List<dynamic>?) ?? const [];
  }

  Future<void> revokeSession(String sessionId) async {
    await _request('/api/auth/sessions/$sessionId', method: 'DELETE');
  }

  Future<void> revokeAllSessions() async {
    await _request('/api/auth/sessions', method: 'DELETE');
  }

  Future<Map<String, dynamic>> register(
          String email, String password, String displayName,
          {String passwordConfirmation = ''}) async =>
      (await _request('/api/auth/register', method: 'POST', body: {
        'email': email,
        'password': password,
        'passwordConfirmation': passwordConfirmation,
        'displayName': displayName,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> resendVerification(String email) async =>
      (await _request('/api/auth/verify-email/resend',
          method: 'POST', body: {'email': email})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> verifyEmail(String token) async =>
      (await _request(
              '/api/auth/verify-email?token=${Uri.encodeQueryComponent(token)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      (await _request('/api/auth/password-reset/request',
          method: 'POST',
          body: {
            'email': email,
          })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> completePasswordReset(
          String token, String password) async =>
      (await _request('/api/auth/password-reset/complete',
          method: 'POST',
          body: {
            'token': token,
            'password': password,
          })) as Map<String, dynamic>;

  Future<void> logout() async {
    await _request('/api/auth/logout', method: 'POST');
  }

  // --- World & Simulation ---

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);

  Future<EarthState> advanceDay() async {
    await _request('/api/day/advance', method: 'POST');
    return world();
  }

  Future<List<dynamic>> events() async {
    final response =
        (await _request('/api/events?limit=20')) as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> notifications() async =>
      (await _request('/api/notifications?limit=20')) as Map<String, dynamic>;

  Future<void> markNotificationRead(String id) async {
    await _request('/api/notifications/$id/read', method: 'POST');
  }

  Future<List<dynamic>> ownershipEvents() async {
    final response = (await _request('/api/ownership/events?limit=20'))
        as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> membershipEvents() async {
    final response = (await _request('/api/membership/events?limit=20'))
        as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> authorityEvents() async {
    final response =
        (await _request('/api/governance/authority/events?limit=20'))
            as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> productionCatalog() async {
    final response =
        (await _request('/api/production/catalog')) as Map<String, dynamic>;
    return (response['sectors'] as List<dynamic>?) ?? const [];
  }

  // --- Business & Finance ---

  Future<Map<String, dynamic>> businessOwnership(String businessId) async =>
      (await _request('/api/businesses/$businessId/ownership'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> businessFinancials(String businessId) async =>
      (await _request('/api/businesses/$businessId/financials'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> businessProfile(String businessId) async =>
      (await _request('/api/businesses/$businessId')) as Map<String, dynamic>;

  Future<EarthState> setPolicy(String policy) async {
    await _request('/api/businesses/me/policy',
        method: 'POST', body: {'policy': policy});
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
      {String? otp}) async {
    await _request('/api/businesses/me/shares/transfer', method: 'POST', body: {
      'recipientId': recipientId.trim(),
      'shares': shares,
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

  // --- Technology & AI ---

  Future<EarthState> fundResearch() async {
    await _request('/api/technology/me/fund', method: 'POST', body: {
      'amount': 240,
      'correlationId':
          'research-funding-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> startResearch(String name, double budget,
      {String focus = 'efficiency'}) async {
    await _request('/api/technology/projects', method: 'POST', body: {
      'name': name,
      'budget': budget,
      'focus': focus,
      'correlationId':
          'research-project-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> grantPatent() async {
    await _request('/api/technology/me/patent', method: 'POST');
    return world();
  }

  Future<EarthState> licenseTechnology() async {
    await _request('/api/technology/me/license', method: 'POST', body: {
      'royaltyRate': 0.05,
    });
    return world();
  }

  Future<EarthState> licenseTechnologyTo(
      String licenseeId, double fee, String otp) async {
    await _request('/api/technology/me/license', method: 'POST', body: {
      'licenseeId': licenseeId.trim(),
      'licenseFee': fee,
      'royaltyRate': 0.05,
      'otp': otp,
    });
    return world();
  }

  Future<EarthState> setAiPolicy(String assistantId, String policy,
      {bool enabled = true}) async {
    await _request('/api/ai/policy', method: 'POST', body: {
      'assistantId': assistantId,
      'policy': policy,
      'enabled': enabled,
    });
    return world();
  }

  Future<EarthState> upgradeAi(String assistantId, {String otp = ''}) async {
    await _request('/api/ai/upgrade', method: 'POST', body: {
      'assistantId': assistantId,
      if (otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  // --- Machines ---

  Future<EarthState> acquireMachine(String machineType) async {
    await _request('/api/machines/acquire', method: 'POST', body: {
      'machineType': machineType,
      'correlationId':
          'machine-acquisition-$machineType-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> maintainMachine(String machineId) async {
    await _request('/api/machines/$machineId/maintenance',
        method: 'POST',
        body: {
          'amount': 10,
          'correlationId':
              'machine-maintenance-$machineId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> decommissionMachine(String machineId,
      {String otp = ''}) async {
    await _request('/api/machines/$machineId/decommission',
        method: 'POST',
        body: {
          if (otp.isNotEmpty) 'otp': otp,
          'correlationId':
              'machine-recycle-$machineId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> setMachineUtilization(
      String machineId, int utilization) async {
    await _request('/api/machines/$machineId/utilization',
        method: 'POST', body: {'utilization': utilization});
    return world();
  }

  Future<EarthState> upgradeMachine(String machineId, {String otp = ''}) async {
    await _request('/api/machines/$machineId/upgrade', method: 'POST', body: {
      if (otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  Future<EarthState> sellMachine(String machineId, String buyerId, double price,
      {String otp = ''}) async {
    await _request('/api/machines/$machineId/sell', method: 'POST', body: {
      'buyerId': buyerId.trim(),
      'price': price,
      if (otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  // --- Market ---

  Future<EarthState> submitOrder(String product, double limitPrice,
      {String side = 'buy', int quantity = 1}) async {
    await _request('/api/market/orders', method: 'POST', body: {
      'product': product,
      'quantity': quantity,
      'limitPrice': limitPrice,
      'side': side,
      'correlationId':
          'market-order-$product-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> settleMarket(String product) async {
    await _request('/api/market/settle',
        method: 'POST', body: {'product': product});
    return world();
  }

  Future<EarthState> cancelOrder(String orderId) async {
    await _request('/api/market/orders/$orderId', method: 'DELETE');
    return world();
  }

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

  // --- Governance ---

  Future<EarthState> vote(String proposalId, String choice) async {
    await _request('/api/governance/proposals/$proposalId/vote',
        method: 'POST', body: {'vote': choice});
    return world();
  }

  Future<EarthState> createProposal(String title, String body,
      {String? targetCategory, double? targetRate}) async {
    await _request('/api/governance/proposals', method: 'POST', body: {
      'institutionId': 'OUC-001',
      'title': title,
      'body': body,
      'durationHours': 72,
      if (targetCategory != null && targetCategory.isNotEmpty)
        'target': {
          'category': targetCategory,
          if (targetRate != null) 'value': {'rate': targetRate},
        },
      'correlationId':
          'governance-proposal-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> claimRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/claim', method: 'POST');
    return world();
  }

  Future<EarthState> resignRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/resign', method: 'POST');
    return world();
  }

  Future<EarthState> delegateRole(String roleId, String delegateHumanId) async {
    await _request('/api/governance/roles/$roleId/delegate',
        method: 'POST', body: {'delegateHumanId': delegateHumanId.trim()});
    return world();
  }

  Future<EarthState> recallRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/recall', method: 'POST');
    return world();
  }

  // --- Institutions ---

  Future<EarthState> setCityBudget(String category,
      {String cityId = 'CITY-0084'}) async {
    await _request('/api/cities/$cityId/budget', method: 'POST', body: {
      'category': category,
      'amount': 100,
    });
    return world();
  }

  Future<EarthState> joinCorporation(
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/membership',
        method: 'POST');
    return world();
  }

  Future<EarthState> leaveCorporation(
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/membership',
        method: 'DELETE');
    return world();
  }

  Future<EarthState> joinCity({String cityId = 'CITY-0084'}) async {
    await _request('/api/cities/$cityId/residency', method: 'POST');
    return world();
  }

  Future<EarthState> leaveCity({String cityId = 'CITY-0084'}) async {
    await _request('/api/cities/$cityId/residency', method: 'DELETE');
    return world();
  }

  Future<EarthState> createCity(String name, String communityId) async {
    await _request('/api/cities',
        method: 'POST', body: {'name': name, 'communityId': communityId});
    return world();
  }

  Future<EarthState> createCorporation(String name, String cityId) async {
    await _request('/api/corporations',
        method: 'POST', body: {'name': name, 'cityId': cityId});
    return world();
  }

  Future<EarthState> spendCorporationTreasury(double amount,
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/treasury/spend',
        method: 'POST',
        body: {
          'category': 'public-services',
          'amount': amount,
          'cityId': 'CITY-0084',
          'correlationId':
              'corporation-spending-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> contributeCorporation(double amount,
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/contributions',
        method: 'POST',
        body: {
          'amount': amount,
          'correlationId':
              'corporation-contribution-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> createCommunity() async {
    await _request('/api/communities', method: 'POST', body: {
      'name': 'Carthage Makers',
      'correlationId':
          'community-formation-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> contributeToCommunity(
      String communityId, double amount) async {
    await _request('/api/communities/$communityId/contributions',
        method: 'POST',
        body: {
          'amount': amount,
          'correlationId': 'flutter-${DateTime.now().millisecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> joinCommunity(String communityId) async {
    await _request('/api/communities/$communityId/members', method: 'POST');
    return world();
  }

  Future<EarthState> leaveCommunity(String communityId) async {
    await _request('/api/communities/$communityId/members', method: 'DELETE');
    return world();
  }

  // --- Contracts & Arbitration ---

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
