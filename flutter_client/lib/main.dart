import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'earth_http_client.dart';

const _violet = Color(0xff8b7cf6);
const _ink = Color(0xfff1f0ff);
const _canvas = Color(0xff111327);
const _surface = Color(0xff1b1e38);
const _muted = Color(0xff9698b5);
const _apiVersion = '2026-08';
final http.Client _earthHttpClient = createEarthHttpClient();

void main() => runApp(const EarthApp());

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EARTH — United Corporations',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _canvas,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _violet, brightness: Brightness.dark),
          fontFamily: 'Manrope',
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: _ink,
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: _surface.withValues(alpha: .72),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
                bodyColor: _ink,
                displayColor: _ink,
              ),
        ),
        home: const AuthGate(),
      );
}

class EarthState {
  final Map<String, dynamic> json;
  const EarthState(this.json);
  Map<String, dynamic> get clock => json['clock'] as Map<String, dynamic>;
  Map<String, dynamic> get human => json['human'] as Map<String, dynamic>;
  Map<String, dynamic> get world => json['world'] as Map<String, dynamic>;
  Map<String, dynamic> get resources =>
      json['resources'] as Map<String, dynamic>;
  Map<String, dynamic> get business => json['business'] as Map<String, dynamic>;
  Map<String, dynamic> get technology =>
      (json['technology'] as Map<String, dynamic>)['research']
          as Map<String, dynamic>;
  Map<String, dynamic> get technologyRegistry =>
      (json['technology'] as Map<String, dynamic>);
  Map<String, dynamic> get governance =>
      json['governance'] as Map<String, dynamic>;
  Map<String, dynamic> get institutions =>
      json['institutions'] as Map<String, dynamic>;
  Map<String, dynamic> get life => json['life'] as Map<String, dynamic>;
  List<dynamic> get machines =>
      (json['machines'] as List<dynamic>?) ?? const [];
  List<dynamic> get productionEvents =>
      (json['productionEvents'] as List<dynamic>?) ?? const [];
  List<dynamic> get aiAssistants =>
      (json['aiAssistants'] as List<dynamic>?) ?? const [];
  List<dynamic> get aiRecommendations =>
      (json['aiRecommendations'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get market =>
      (json['market'] as Map<String, dynamic>)['products']
          as Map<String, dynamic>;
  List<dynamic> get marketBook =>
      ((json['market'] as Map<String, dynamic>)['book'] as List<dynamic>?) ??
      const [];
  List<dynamic> get marketTrades =>
      ((json['market'] as Map<String, dynamic>)['trades'] as List<dynamic>?) ??
      const [];
  List<dynamic> get marketOrders =>
      ((json['market'] as Map<String, dynamic>)['orders'] as List<dynamic>?) ??
      const [];
  double get marketFeeRate =>
      ((json['market'] as Map<String, dynamic>)['feeRate'] as num?)
          ?.toDouble() ??
      0;
  List<dynamic> get communities =>
      (json['communities'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get audit =>
      (json['audit'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get finance =>
      (json['finance'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get ledgerEntries =>
      (json['ledgerEntries'] as List<dynamic>?) ?? const [];
  List<dynamic> get publicActivity =>
      (json['publicActivity'] as List<dynamic>?) ?? const [];
  List<dynamic> get opportunities =>
      (json['opportunities'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get rankings =>
      (json['rankings'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get history =>
      (json['history'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get financeStatus =>
      (json['financeStatus'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get personalFinance =>
      (json['personalFinance'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get contracts =>
      (json['contracts'] as List<dynamic>?) ?? const [];
  List<dynamic> get roles => (json['roles'] as List<dynamic>?) ?? const [];
  Map<String, dynamic>? get membership =>
      json['membership'] as Map<String, dynamic>?;
}

class EarthApi {
  final String baseUrl;
  const EarthApi({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL', defaultValue: '');

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = method == 'POST'
        ? await _earthHttpClient.post(uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body ?? {}))
        : method == 'DELETE'
            ? await _earthHttpClient.delete(uri)
            : await _earthHttpClient.get(uri);
    final apiVersion = response.headers['x-earth-api-version'];
    if (apiVersion != null && apiVersion != _apiVersion) {
      throw Exception(
          'Incompatible EARTH API version $apiVersion (expected $_apiVersion)');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw EarthApiException(
          'The server returned an unexpected response (HTTP ${response.statusCode})',
          statusCode: response.statusCode);
    }
    if (response.statusCode >= 400) {
      final requestId = response.headers['x-request-id'];
      final payload = decoded is Map ? decoded : const <String, dynamic>{};
      throw EarthApiException(
        '${payload['error'] ?? 'Request failed'}',
        code: '${payload['code'] ?? 'REQUEST_FAILED'}',
        correlationId: '${payload['correlationId'] ?? requestId ?? ''}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

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

  Future<
      Map<String, dynamic>> verifyEmail(String token) async => (await _request(
          '/api/auth/verify-email?token=${Uri.encodeQueryComponent(token)}'))
      as Map<String, dynamic>;

  Future<Map<String, dynamic>> completePasswordReset(
          String token, String password) async =>
      (await _request('/api/auth/password-reset/complete',
          method: 'POST',
          body: {
            'token': token,
            'password': password,
          })) as Map<String, dynamic>;

  Future<List<dynamic>> events() async {
    final response =
        (await _request('/api/events?limit=20')) as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> notifications() async =>
      (await _request('/api/notifications?limit=20')) as Map<String, dynamic>;

  Future<List<dynamic>> ownershipEvents() async {
    final response = (await _request('/api/ownership/events?limit=20'))
        as Map<String, dynamic>;
    return (response['events'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> businessOwnership(String businessId) async =>
      (await _request('/api/businesses/$businessId/ownership'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> businessFinancials(String businessId) async =>
      (await _request('/api/businesses/$businessId/financials'))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> businessProfile(String businessId) async =>
      (await _request('/api/businesses/$businessId')) as Map<String, dynamic>;

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

  Future<void> markNotificationRead(String id) async {
    await _request('/api/notifications/$id/read', method: 'POST');
  }

  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      (await _request('/api/auth/password-reset/request',
          method: 'POST',
          body: {
            'email': email,
          })) as Map<String, dynamic>;

  Future<void> logout() async {
    await _request('/api/auth/logout', method: 'POST');
  }

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);
  Future<EarthState> advanceDay() async {
    await _request('/api/day/advance', method: 'POST');
    return world();
  }

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

  Future<EarthState> acquireMachine(String machineType) async {
    await _request('/api/machines/acquire', method: 'POST', body: {
      'machineType': machineType,
      'correlationId':
          'machine-acquisition-$machineType-${DateTime.now().microsecondsSinceEpoch}',
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

  Future<EarthState> registerSuccessor(String name,
      {String? successorHumanId}) async {
    await _request('/api/successor', method: 'POST', body: {
      'name': name,
      if (successorHumanId != null && successorHumanId.isNotEmpty)
        'successorHumanId': successorHumanId,
    });
    return world();
  }

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

  Future<EarthState> setCityBudget(String category,
      {String cityId = 'CITY-0084'}) async {
    await _request('/api/cities/$cityId/budget', method: 'POST', body: {
      'category': category,
      'amount': 100,
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

  Future<EarthState> leaveCity({String cityId = 'CITY-0084'}) async {
    await _request('/api/cities/$cityId/residency', method: 'DELETE');
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
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final api = const EarthApi();
  Map<String, dynamic>? session;
  String? error;
  String? actionMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final parameters = Uri.base.queryParameters;
    final verifyToken = parameters['verify_token'];
    if (verifyToken != null && verifyToken.isNotEmpty) {
      try {
        final result = await api.verifyEmail(verifyToken);
        actionMessage = result['message']?.toString() ??
            'Email verified. You can now sign in.';
      } catch (exception) {
        actionMessage = exception.toString().replaceFirst('Exception: ', '');
      }
    }
    try {
      final value = await api.session();
      if (mounted) setState(() => session = value);
    } catch (_) {
      if (mounted) setState(() => session = {'authenticated': false});
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    final resetToken = Uri.base.queryParameters['reset_token'];
    if (current == null) {
      return AuthScreen(
          api: api,
          onAuthenticated: (value) => setState(() => session = value),
          initialResetToken: resetToken,
          initialMessage: actionMessage);
    }
    if (current['authenticated'] != true) {
      return AuthScreen(
          api: api,
          onAuthenticated: (value) => setState(() => session = value),
          initialResetToken: resetToken,
          initialMessage: actionMessage);
    }
    return CommandCenter(
        onLogout: () => setState(() => session = {'authenticated': false}));
  }
}

class AuthScreen extends StatefulWidget {
  final EarthApi api;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final String? initialResetToken;
  final String? initialMessage;
  const AuthScreen(
      {super.key,
      required this.api,
      required this.onAuthenticated,
      this.initialResetToken,
      this.initialMessage});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  final displayName = TextEditingController();
  final otp = TextEditingController();
  bool registerMode = false;
  bool recoveryMode = false;
  late bool resetMode;
  late String? resetToken;
  bool verificationPending = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    resetToken = widget.initialResetToken;
    resetMode = resetToken != null && resetToken!.isNotEmpty;
    error = widget.initialMessage;
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (resetMode) {
        if (password.text.length < 12) {
          throw Exception('Password must be at least 12 characters');
        }
        if (password.text != passwordConfirmation.text) {
          throw Exception('Passwords do not match');
        }
        final result =
            await widget.api.completePasswordReset(resetToken!, password.text);
        if (mounted) {
          setState(() {
            resetMode = false;
            resetToken = null;
            password.clear();
            passwordConfirmation.clear();
            error = result['message']?.toString() ??
                'Password reset. You can now sign in.';
          });
        }
        return;
      }
      if (recoveryMode) {
        await widget.api.requestPasswordReset(email.text);
        if (mounted) {
          setState(() {
            error = 'If the identity exists, recovery instructions were sent.';
            recoveryMode = false;
          });
        }
        return;
      }
      if (registerMode) {
        if (password.text != passwordConfirmation.text) {
          throw Exception('Passwords do not match');
        }
        await widget.api.register(email.text, password.text, displayName.text,
            passwordConfirmation: passwordConfirmation.text);
        if (mounted) {
          setState(() {
            registerMode = false;
            verificationPending = true;
            error =
                'Identity created. Check your email to verify it, then sign in.';
          });
        }
      } else {
        final result =
            await widget.api.login(email.text, password.text, otp: otp.text);
        if (mounted) {
          widget.onAuthenticated(
              {'authenticated': true, 'human': result['human']});
        }
      }
    } catch (exception) {
      final message = exception.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          error = message;
          verificationPending =
              message.toLowerCase().contains('verify your email');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendVerification() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.resendVerification(email.text);
      if (mounted) {
        setState(() => error = result['message']?.toString() ??
            'If the identity exists, a new verification email was sent.');
      }
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    displayName.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('EARTH',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(
                          resetMode
                              ? 'Set a new password'
                              : recoveryMode
                                  ? 'Recover your identity'
                                  : registerMode
                                      ? 'Create your Human identity'
                                      : 'Enter the shared world',
                          style: const TextStyle(color: _muted)),
                      const SizedBox(height: 24),
                      if (registerMode && !recoveryMode) ...[
                        TextField(
                            controller: displayName,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Display name')),
                        const SizedBox(height: 12),
                      ],
                      if (!resetMode)
                        TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration:
                                const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 12),
                      if (!recoveryMode)
                        TextField(
                            controller: password,
                            obscureText: true,
                            onSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                                labelText: resetMode
                                    ? 'New password (12+ characters)'
                                    : 'Password (12+ characters)')),
                      if ((registerMode || resetMode) && !recoveryMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: passwordConfirmation,
                            obscureText: true,
                            onSubmitted: (_) => submit(),
                            decoration: const InputDecoration(
                                labelText: 'Repeat password')),
                      ],
                      if (!registerMode && !recoveryMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: otp,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Authenticator code (if enabled)')),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!,
                            style: const TextStyle(color: Colors.redAccent))
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(busy
                              ? 'Connecting…'
                              : resetMode
                                  ? 'Set new password'
                                  : recoveryMode
                                      ? 'Send recovery email'
                                      : registerMode
                                          ? 'Create identity'
                                          : 'Enter EARTH')),
                      if (!resetMode &&
                          !registerMode &&
                          !recoveryMode &&
                          (verificationPending ||
                              (error
                                      ?.toLowerCase()
                                      .contains('verify your email') ??
                                  false)))
                        TextButton(
                            onPressed: busy ? null : resendVerification,
                            child: const Text('Resend verification email')),
                      if (!resetMode && !registerMode && !recoveryMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      recoveryMode = true;
                                      error = null;
                                    }),
                            child: const Text('Forgot password?')),
                      if (!resetMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      recoveryMode = false;
                                      registerMode = !registerMode;
                                      verificationPending = false;
                                      error = null;
                                    }),
                            child: Text(recoveryMode || registerMode
                                ? 'Back to sign in'
                                : 'New to EARTH? Create an identity')),
                      if (resetMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      resetMode = false;
                                      resetToken = null;
                                      error = null;
                                    }),
                            child: const Text('Back to sign in')),
                    ]),
              ),
            ),
          ),
        ),
      );
}

class CommandCenter extends StatefulWidget {
  final VoidCallback onLogout;
  const CommandCenter({super.key, required this.onLogout});
  @override
  State<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<CommandCenter> {
  final api = const EarthApi();
  EarthState? state;
  String? error;
  bool busy = false;
  List<dynamic> events = const [];
  List<dynamic> notifications = const [];
  List<dynamic> ownershipEvents = const [];
  List<dynamic> membershipEvents = const [];
  List<dynamic> authorityEvents = const [];
  Map<String, dynamic> businessOwnership = const {};
  Map<String, dynamic> businessFinancials = const {};
  Map<String, dynamic> businessProfile = const {};
  List<dynamic> productionCatalog = const [];
  int unreadNotifications = 0;
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  WebSocketChannel? liveChannel;

  @override
  void initState() {
    super.initState();
    _run(api.world);
    _loadProductionCatalog();
    _refreshEvents();
    _connectLiveChannel();
    eventTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshEvents());
  }

  Future<void> _loadProductionCatalog() async {
    try {
      final catalog = await api.productionCatalog();
      if (mounted) setState(() => productionCatalog = catalog);
    } catch (_) {
      // The dashboard remains usable if the public catalog is temporarily unavailable.
    }
  }

  void _connectLiveChannel() {
    final base = api.baseUrl;
    if (base.isEmpty) return;
    final uri =
        Uri.parse('${base.replaceFirst(RegExp(r'^http'), 'ws')}/edge/events');
    try {
      liveChannel = WebSocketChannel.connect(uri);
      liveChannel!.stream.listen((_) {
        if (mounted) _refreshEvents();
      }, onError: (_) {
        liveChannel = null;
        _scheduleLiveReconnect();
      }, onDone: () {
        liveChannel = null;
        _scheduleLiveReconnect();
      });
    } catch (_) {
      liveChannel = null;
    }
  }

  void _scheduleLiveReconnect() {
    if (!mounted || liveReconnectTimer?.isActive == true) return;
    liveReconnectTimer = Timer(const Duration(seconds: 10), () {
      liveReconnectTimer = null;
      if (mounted && liveChannel == null) _connectLiveChannel();
    });
  }

  Future<void> _refreshEvents() async {
    try {
      final latest = await api.events();
      final notificationData = await api.notifications();
      final ownership = await api.ownershipEvents();
      final memberships = await api.membershipEvents();
      final authority = await api.authorityEvents();
      if (mounted) {
        setState(() {
          events = latest;
          ownershipEvents = ownership;
          membershipEvents = memberships;
          authorityEvents = authority;
          notifications =
              (notificationData['notifications'] as List<dynamic>?) ?? const [];
          unreadNotifications =
              (notificationData['unread'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // The world snapshot remains usable if the optional live feed is temporarily unavailable.
    }
  }

  Future<void> _run(Future<EarthState> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await action();
      Map<String, dynamic> ownership = const {};
      Map<String, dynamic> financials = const {};
      Map<String, dynamic> profile = const {};
      final businessId = value.business['id'] as String?;
      if (businessId != null && businessId.isNotEmpty) {
        try {
          profile = await api.businessProfile(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
        try {
          ownership = await api.businessOwnership(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
        try {
          financials = await api.businessFinancials(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
      }
      if (mounted) {
        setState(() {
          state = value;
          businessProfile = profile;
          businessOwnership = ownership;
          businessFinancials = financials;
        });
      }
      await _refreshEvents();
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    eventTimer?.cancel();
    liveReconnectTimer?.cancel();
    liveChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = state;
    final canAdvanceDay = current?.roles.any((raw) {
          final role = raw as Map<String, dynamic>;
          return role['id'] == 'ROLE-OUC-DELEGATE' &&
              role['human_id'] == current.human['id'] &&
              role['assignment_status'] == 'active';
        }) ??
        false;
    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxWidth < 900;
      return Scaffold(
          drawer: current != null && compact
              ? Drawer(
                  backgroundColor: _canvas,
                  child: SafeArea(child: _Sidebar(state: current)),
                )
              : null,
          appBar: AppBar(
            title: const Text('EARTH  ·  COMMAND CENTER',
                style:
                    TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            actions: [
              if (busy)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              TextButton(
                  onPressed: busy || !canAdvanceDay
                      ? null
                      : () => _run(api.advanceDay),
                  child: const Text('ADVANCE DAY  →')),
              IconButton(
                  tooltip: 'Sign out',
                  onPressed: busy
                      ? null
                      : () async {
                          await api.logout();
                          if (mounted) widget.onLogout();
                        },
                  icon: const Icon(Icons.logout)),
              IconButton(
                  tooltip: 'Account security',
                  onPressed: busy ? null : () => _showSecurityDialog(context),
                  icon: const Icon(Icons.security))
            ],
          ),
          body: current == null
              ? Center(
                  child: error == null
                      ? const CircularProgressIndicator()
                      : _ErrorState(
                          message: error!, retry: () => _run(api.world)))
              : RefreshIndicator(
                  onRefresh: () async => _run(api.world),
                  child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_canvas, Color(0xff171936), _canvas],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(children: [
                        if (!compact) _Sidebar(state: current),
                        Expanded(
                            child: ListView(
                                padding: EdgeInsets.fromLTRB(compact ? 16 : 34,
                                    compact ? 16 : 26, compact ? 16 : 42, 56),
                                children: [
                              if (compact)
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Text('COMPACT COMMAND VIEW',
                                        style: TextStyle(
                                            color: _muted,
                                            fontSize: 9,
                                            letterSpacing: 1.1))),
                              _Dashboard(
                                  state: current,
                                  busy: busy,
                                  events: events,
                                  notifications: notifications,
                                  ownershipEvents: ownershipEvents,
                                  businessOwnership: businessOwnership,
                                  businessFinancials: businessFinancials,
                                  businessProfile: businessProfile,
                                  membershipEvents: membershipEvents,
                                  authorityEvents: authorityEvents,
                                  productionCatalog: productionCatalog,
                                  unreadNotifications: unreadNotifications,
                                  action: _run)
                            ]))
                      ]))));
    });
  }

  Future<void> _showMfaDialog(BuildContext context) async {
    final code = TextEditingController();
    try {
      final enrollment = await api.enrollMfa();
      if (!context.mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Enable authenticator MFA'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Add this secret to your authenticator app, then enter the six-digit code.'),
                      const SizedBox(height: 12),
                      SelectableText('${enrollment['secret']}'),
                      const SizedBox(height: 12),
                      TextField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Authenticator code')),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        await api.confirmMfa(code.text);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Enable'))
                ],
              ));
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(exception.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _showSecurityDialog(BuildContext context) async {
    List<dynamic> sessions;
    try {
      sessions = await api.sessions();
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(exception.toString().replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Account security'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active sessions',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (sessions.isEmpty)
                    const Text('No active sessions were found.',
                        style: TextStyle(color: _muted))
                  else
                    ...sessions.map((raw) {
                      final session = Map<String, dynamic>.from(raw as Map);
                      final current = session['current'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            current ? Icons.devices : Icons.device_unknown,
                            color: current ? _violet : _muted),
                        title: Text(current ? 'This device' : 'Other session'),
                        subtitle: Text(
                            'Created ${_formatSecurityDate(session['created_at'])}\nExpires ${_formatSecurityDate(session['expires_at'])}'),
                        trailing: current
                            ? const Chip(label: Text('CURRENT'))
                            : IconButton(
                                tooltip: 'Revoke session',
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  try {
                                    await api.revokeSession(
                                        session['id'].toString());
                                    sessions = await api.sessions();
                                    if (dialogContext.mounted) {
                                      setDialogState(() {});
                                    }
                                  } catch (exception) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(SnackBar(
                                              content: Text(exception
                                                  .toString()
                                                  .replaceFirst(
                                                      'Exception: ', ''))));
                                    }
                                  }
                                },
                              ),
                      );
                    }),
                  const Divider(height: 28),
                  const Text('Authenticator MFA',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                      'Enroll or disable authenticator verification from this account.',
                      style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showMfaDialog(context);
                        },
                        icon: const Icon(Icons.add_moderator),
                        label: const Text('ENROLL MFA')),
                    OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showDisableMfaDialog(context);
                        },
                        icon: const Icon(Icons.remove_moderator),
                        label: const Text('DISABLE MFA')),
                  ]),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: dialogContext,
                        builder: (confirmContext) => AlertDialog(
                          title: const Text('Revoke every session?'),
                          content: const Text(
                              'This signs out every device, including the current one.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(confirmContext, false),
                                child: const Text('CANCEL')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(confirmContext, true),
                                child: const Text('REVOKE ALL')),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        await api.revokeAllSessions();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) widget.onLogout();
                      } catch (exception) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                  content: Text(exception
                                      .toString()
                                      .replaceFirst('Exception: ', ''))));
                        }
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('REVOKE ALL OTHER ACCESS'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('DONE'))
          ],
        ),
      ),
    );
  }

  Future<void> _showDisableMfaDialog(BuildContext context) async {
    final code = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Disable authenticator MFA'),
          content: TextField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Current six-digit code')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: () async {
                try {
                  await api.disableMfa(code.text.trim());
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Authenticator MFA disabled.')));
                  }
                } catch (exception) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                        content: Text(exception
                            .toString()
                            .replaceFirst('Exception: ', ''))));
                  }
                }
              },
              child: const Text('DISABLE'),
            ),
          ],
        ),
      );
    } finally {
      code.dispose();
    }
  }
}

String _formatSecurityDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'unknown';
  return parsed
      .toLocal()
      .toIso8601String()
      .replaceFirst('T', ' ')
      .split('.')
      .first;
}

class _Dashboard extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final List<dynamic> events;
  final List<dynamic> notifications;
  final List<dynamic> ownershipEvents;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final List<dynamic> membershipEvents;
  final List<dynamic> authorityEvents;
  final List<dynamic> productionCatalog;
  final int unreadNotifications;
  final Future<void> Function(Future<EarthState> Function()) action;
  const _Dashboard(
      {required this.state,
      required this.busy,
      required this.events,
      required this.notifications,
      required this.ownershipEvents,
      required this.businessOwnership,
      required this.businessFinancials,
      required this.businessProfile,
      required this.membershipEvents,
      required this.authorityEvents,
      required this.productionCatalog,
      required this.unreadNotifications,
      required this.action});
  @override
  Widget build(BuildContext context) {
    final proposals =
        (state.governance['proposals'] as List<dynamic>?) ?? const [];
    final proposal = proposals.isEmpty
        ? <String, dynamic>{
            'id': '',
            'title': 'No open proposal is currently available.',
            'status': 'waiting',
            'outcome': 'pending',
            'votes': <String, dynamic>{'support': 0, 'oppose': 0, 'uncast': 0},
          }
        : Map<String, dynamic>.from(proposals.first as Map);
    final votes = Map<String, dynamic>.from(
        (proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final hasProposal = proposal['id'].toString().isNotEmpty;
    final cityId = state.institutions['city']['id']?.toString() ?? 'CITY-0084';
    final corporationId =
        state.institutions['corporation']['id']?.toString() ?? 'CORP-001';
    final canArbitrate = state.roles.any((raw) {
      final role = raw as Map<String, dynamic>;
      return role['id'] == 'ROLE-OUC-DELEGATE' &&
          (role['human_id'] == state.human['id'] ||
              role['delegate_id'] == state.human['id']);
    });
    final resourceText = state.resources.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('  ·  ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _HeroCard(state: state),
      const SizedBox(height: 16),
      Text('The world is moving.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: _ink, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
      const SizedBox(height: 8),
      Text(
          'DAY ${state.clock['day']}  ·  ${state.institutions['city']['name']}  ·  ${state.institutions['corporation']['name']}',
          style:
              const TextStyle(color: _muted, fontSize: 11, letterSpacing: .7)),
      const SizedBox(height: 24),
      if (state.opportunities.isNotEmpty) ...[
        _OpportunityPanel(opportunities: state.opportunities),
        const SizedBox(height: 14),
      ],
      Wrap(spacing: 14, runSpacing: 14, children: [
        _Metric(
            label: 'CREDITS',
            value: '${state.human['credits']} C',
            accent: _violet),
        _Metric(
            label: 'STANDING',
            value: '${state.human['standing']}',
            accent: Colors.teal),
        _Metric(
            label: 'LEGACY',
            value: '${state.human['legacy']}',
            accent: Colors.indigo),
        _Metric(
            label: 'WORLD HEALTH',
            value: '${state.world['health']} / 100',
            accent: Colors.orange),
      ]),
      if (state.human['politicalMaturity'] == false)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'POLITICAL MATURITY · AVAILABLE FROM GAME DAY ${state.human['politicalEligibilityGameDay']}',
                style: const TextStyle(
                    color: Colors.orange, fontSize: 10, letterSpacing: .7))),
      const SizedBox(height: 18),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RESOURCE RESERVES   $resourceText',
                        style: const TextStyle(
                            fontSize: 11, letterSpacing: .8, color: _muted)),
                    const SizedBox(height: 8),
                    Text(
                        'STARTER ECONOMY   living-cost ${state.world['livingCostIndex'] ?? '—'}  ·  productive ${state.world['economicStartIndex'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 10, letterSpacing: .6, color: _muted)),
                  ]))),
      const SizedBox(height: 14),
      _Panel(
          title: 'INSTITUTIONS / CAPACITY',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'CITY  ${state.institutions['city']['residents']} residents  ·  housing ${state.institutions['city']['housing_capacity']}  ·  energy ${state.institutions['city']['energy_capacity']}'),
            const SizedBox(height: 6),
            Text(
                'SERVICE PRESSURE  housing ${_percent(state.world['serviceRatios']?['housing'])}  ·  energy ${_percent(state.world['serviceRatios']?['energy'])}  ·  connectivity ${_percent(state.world['serviceRatios']?['connectivity'])}  ·  health ${_percent(state.world['serviceRatios']?['health'])}',
                style: const TextStyle(color: _muted, fontSize: 10)),
            const SizedBox(height: 6),
            Text(
                'CITY QUALIFICATION  ${((state.world['cityQualification'] as Map<String, dynamic>?)?.values.every((value) => value == true) ?? false) ? 'QUALIFIED' : 'IN PROGRESS'}',
                style: const TextStyle(
                    color: _muted, fontSize: 10, letterSpacing: .5)),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi()
                        .setCityBudget('maintenance', cityId: cityId)),
                child: const Text('PROPOSE MAINTENANCE BUDGET')),
            const SizedBox(height: 8),
            Text(
                'CORPORATION  ${state.institutions['corporation']['member_count']} members  ·  constitution v${state.institutions['corporation']['constitution_version']}'),
            const SizedBox(height: 6),
            Text(
                'CORPORATION QUALIFICATION  ${((state.world['corporationQualification'] as Map<String, dynamic>?)?.values.every((value) => value == true) ?? false) ? 'QUALIFIED' : 'IN PROGRESS'}',
                style: const TextStyle(
                    color: _muted, fontSize: 10, letterSpacing: .5)),
            const SizedBox(height: 10),
            Text(
                state.membership?['corporation_id'] == null
                    ? 'Independent membership · eligible to join'
                    : 'Member since game day ${state.membership?['joined_game_day']}',
                style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => state.membership?['corporation_id'] ==
                            null
                        ? const EarthApi()
                            .joinCorporation(corporationId: corporationId)
                        : const EarthApi()
                            .leaveCorporation(corporationId: corporationId)),
                child: Text(state.membership?['corporation_id'] == null
                    ? 'JOIN CORPORATION'
                    : 'LEAVE CORPORATION')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => state.membership?['city_id'] == null
                        ? const EarthApi().joinCity(cityId: cityId)
                        : const EarthApi().leaveCity(cityId: cityId)),
                child: Text(state.membership?['city_id'] == null
                    ? 'JOIN CITY'
                    : 'LEAVE CITY')),
            const SizedBox(height: 8),
            if (state.communities.isNotEmpty)
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showFormationComposer(context, action,
                          city: true,
                          communityId: (state.communities.first
                              as Map<String, dynamic>)['id'] as String),
                  child: const Text('FORM CITY FROM COMMUNITY')),
            if (state.membership?['city_id'] != null)
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showFormationComposer(context, action,
                          city: false,
                          cityId: state.membership?['city_id'] as String),
                  child: const Text('FORM CORPORATION')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi()
                        .spendCorporationTreasury(100,
                            corporationId: corporationId)),
                child: const Text('FUND CITY SERVICES · 100 C')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().contributeCorporation(
                        100,
                        corporationId: corporationId)),
                child: const Text('CONTRIBUTE TO TREASURY · 100 C')),
          ])),
      const SizedBox(height: 14),
      Wrap(spacing: 14, runSpacing: 14, children: [
        _Panel(
            title: 'BUSINESS / KLINE WORKS',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Policy: ${state.business['policy']}'),
              Text('Financial status: ${state.business['status'] ?? 'active'}',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              Text('Condition: ${state.business['condition']}%'),
              if (businessProfile['business'] is Map)
                Text(
                    'Sector: ${(businessProfile['business'] as Map<String, dynamic>)['sector']} · status ${(businessProfile['business'] as Map<String, dynamic>)['status']}',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              if (businessProfile['assets'] is List)
                Text(
                    'Assigned machines: ${(businessProfile['assets'] as List).length}',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              Text(
                  'Financials: revenue ${state.business['revenue'] ?? 0} C · costs ${state.business['operating_costs'] ?? 0} C · profit ${state.business['profit'] ?? 0} C',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              if (businessFinancials['business'] is Map)
                Text(
                    'Taxed revenue: ${(businessFinancials['business'] as Map<String, dynamic>)['taxed_revenue'] ?? 0} C · last assessed day ${(businessFinancials['business'] as Map<String, dynamic>)['last_game_day'] ?? 0}',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              const Text(
                  'Revenue is recorded when owner output clears through the canonical market; production inputs are operating costs.',
                  style: TextStyle(color: _muted, fontSize: 10)),
              Text('Ownership: ${state.business['owned_shares'] ?? 0} shares',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              Text(
                  'Registry control: ${state.business['controlling_human_id'] ?? 'undetermined'} · ${state.business['total_issued_shares'] ?? 0} issued shares',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              if (businessOwnership['holders'] is List &&
                  (businessOwnership['holders'] as List).isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('OWNERSHIP REGISTRY',
                    style: TextStyle(
                        color: _muted, fontSize: 10, letterSpacing: 1)),
                ...((businessOwnership['holders'] as List).take(5).map((raw) {
                  final holder = raw as Map<String, dynamic>;
                  return Text(
                      '${holder['display_name']} · ${holder['percentage']}% (${holder['shares']} shares)',
                      style: const TextStyle(fontSize: 11));
                })),
              ],
              Text('Manager: ${state.business['manager_id'] ?? 'owner'}',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              Text(
                  'Constitution v${state.business['constitution_version'] ?? 1} · shareholder ${((double.tryParse('${state.business['shareholder_vote_threshold'] ?? 0.5}') ?? 0.5) * 100).round()}% · dilution notice ${state.business['dilution_notice_days'] ?? 3}d',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showBusinessComposer(context, action),
                  child: const Text('REGISTER NEW BUSINESS · 250 C')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed:
                      busy ? null : () => _showShareTransfer(context, action),
                  child: const Text('TRANSFER SHARES')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showShareIssue(
                          context, action, state.business['id'] as String?),
                  child: const Text('ISSUE SHARES')),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showBusinessConstitution(
                          context, action, state.business),
                  child: const Text('UPDATE CONSTITUTION')),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showBusinessManager(
                          context, action, state.business['id'] as String?),
                  child: const Text('APPOINT MANAGER')),
              if (['distressed', 'insolvent']
                  .contains('${state.business['status'] ?? ''}')) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _showBusinessLiquidationDialog(
                            context, action, state.business['id'] as String?),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent),
                    child: const Text('LIQUIDATE BUSINESS')),
              ],
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  children: ['reliability', 'margin', 'capacity']
                      .map((policy) => OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().setPolicy(policy)),
                          child: Text(policy)))
                      .toList())
            ])),
        _Panel(
            title: 'ADAPTIVE MAINTENANCE AI',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${state.technology['progress']}% complete',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(
                  'Research focus: ${state.technology['focus'] ?? 'efficiency'}',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              Text(
                  'Patents ${state.technologyRegistry['activePatents']}  ·  Licenses ${state.technologyRegistry['activeLicenses']}',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value:
                      (state.technology['progress'] as num).toDouble() / 100),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(() => const EarthApi().fundResearch()),
                  child: const Text('FUND 240 C')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showResearchComposer(context, action),
                  child: const Text('START NEW RESEARCH · 240 C MIN')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => action(() => const EarthApi().grantPatent()),
                    child: const Text('GRANT PATENT')),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () =>
                            action(() => const EarthApi().licenseTechnology()),
                    child: const Text('LICENSE 5%')),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _showLicenseComposer(context, action),
                    child: const Text('LICENSE TO HUMAN')),
              ])
            ])),
        _Panel(
            title: 'UC PROPOSAL ${proposal['id']}',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(proposal['title']),
              Text(
                  '${proposal['status']} · ${proposal['outcome'] ?? 'pending'}',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              Text(
                  'Quorum ${(((proposal['quorum'] as num?)?.toDouble() ?? .25) * 100).round()}% · approval ${(((proposal['approval_threshold'] as num?)?.toDouble() ?? .5) * 100).round()}%',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              if (proposal['deadline'] is Map)
                Text(
                    _formatProposalDeadline(
                        proposal['deadline'] as Map<String, dynamic>),
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 11)),
              const SizedBox(height: 8),
              Text(
                  'Support ${votes['support']}  ·  Oppose ${votes['oppose']}  ·  Uncast ${votes['uncast']}'),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  children: ['support', 'oppose', 'abstain']
                      .map((choice) => OutlinedButton(
                          onPressed: busy || !hasProposal
                              ? null
                              : () => action(() => const EarthApi()
                                  .vote(proposal['id'] as String, choice)),
                          child: Text(choice)))
                      .toList()),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showProposalComposer(context, action),
                  child: const Text('CREATE PROPOSAL'))
            ])),
        _Panel(
            title: 'AUTOMATION / MACHINES',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (state.machines.isEmpty)
                const Text('No registered machines.')
              else
                ...state.machines.map((raw) {
                  final machine = raw as Map<String, dynamic>;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                          '${machine['name']}\n${machine['machine_type']}\n${machine['input_resource']} → ${machine['output_resource']}')),
                                  Text(
                                      '${machine['condition']}%\n${machine['maintenance_due']} due',
                                      textAlign: TextAlign.right),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => action(() => const EarthApi()
                                              .maintainMachine(
                                                  machine['id'] as String)),
                                      child: const Text('MAINTAIN')),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _showDecommissionDialog(
                                              context,
                                              action,
                                              machine['id'] as String),
                                      child: const Text('RECYCLE')),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _showMachineUpgradeDialog(
                                              context,
                                              action,
                                              machine['id'] as String),
                                      child: const Text('UPGRADE')),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _showMachineSaleDialog(
                                              context,
                                              action,
                                              machine['id'] as String),
                                      child: const Text('SELL'))
                                ]),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, children: [
                              const Text('UTILIZATION',
                                  style:
                                      TextStyle(color: _muted, fontSize: 11)),
                              for (final level in [0, 25, 50, 75, 100])
                                OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => action(() => const EarthApi()
                                            .setMachineUtilization(
                                                machine['id'] as String,
                                                level)),
                                    child: Text('$level%')),
                            ])
                          ]));
                }),
              const SizedBox(height: 4),
              const Text('Acquire a specialized production unit:',
                  style: TextStyle(color: _muted, fontSize: 11)),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: productionCatalog.isEmpty
                      ? [
                          const Text('Production catalog is loading…',
                              style: TextStyle(color: _muted, fontSize: 11))
                        ]
                      : productionCatalog
                          .where((raw) =>
                              (raw as Map<String, dynamic>)['acquisition'] !=
                              null)
                          .expand((raw) {
                          final sector = raw as Map<String, dynamic>;
                          final types =
                              (sector['machineTypes'] as List<dynamic>?) ??
                                  const [];
                          return types.map((type) => OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .acquireMachine(type.toString())),
                                child: Text(
                                    '${type.toString().toUpperCase()} · ${sector['name']} · ${sector['acquisition']?['credit'] ?? '—'} C / ${sector['acquisition']?['material'] ?? '—'} M'),
                              ));
                        }).toList()),
            ])),
        _Panel(
            title: 'PRODUCTION / AUTHORITATIVE OUTPUT',
            child: state.productionEvents.isEmpty
                ? const Text(
                    'Production history will appear after an active machine completes a settlement cycle.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.productionEvents.take(8).map((raw) {
                      final event = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                              'DAY ${event['game_day']}  ·  +${event['amount']} ${event['resource']}  ·  ${event['machine_name'] ?? event['machine_id']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'AI ASSISTANT / BOUNDED AUTOMATION',
            child: state.aiAssistants.isEmpty
                ? const Text('No AI assistant is registered.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.aiAssistants.map((raw) {
                      final assistant = raw as Map<String, dynamic>;
                      final enabled = assistant['enabled'] == 1 ||
                          assistant['enabled'] == true;
                      return Row(children: [
                        Expanded(
                            child: Text(
                                '${assistant['tier']} AI  ·  ${assistant['policy']}  ·  ${enabled ? 'enabled' : 'paused'}',
                                style: const TextStyle(fontSize: 11))),
                        if (assistant['tier'] != 'business')
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _showAiUpgradeDialog(context, action,
                                      assistant['id'] as String),
                              child: const Text('UPGRADE · 2,400 C')),
                        OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi()
                                    .setAiPolicy(
                                        assistant['id'] as String,
                                        assistant['policy'] == 'maintenance'
                                            ? 'recommend'
                                            : 'maintenance',
                                        enabled: true)),
                            child: Text(assistant['policy'] == 'maintenance'
                                ? 'RECOMMEND'
                                : 'MAINTAIN')),
                      ]);
                    }).toList())),
        _Panel(
            title: 'AI / EXPLAINABLE RECOMMENDATIONS',
            child: state.aiRecommendations.isEmpty
                ? const Text(
                    'No priority recommendations. The current state is within bounded operating conditions.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.aiRecommendations.take(6).map((raw) {
                      final recommendation = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                              '${recommendation['priority']}  ·  ${recommendation['message']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        const _Panel(
            title: 'EIGHT-SECTOR ECONOMY',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text('ENERGY')),
              Chip(label: Text('EXTRACTION')),
              Chip(label: Text('COMPONENTS')),
              Chip(label: Text('MACHINES')),
              Chip(label: Text('MAINTENANCE')),
              Chip(label: Text('HOUSING')),
              Chip(label: Text('COMPUTE')),
              Chip(label: Text('R&D')),
            ])),
        _Panel(
            title: 'HUMAN SERVICES / CURRENT ACCESS',
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    ((state.world['serviceStatus'] as Map<String, dynamic>?) ??
                            const {})
                        .entries
                        .map((entry) => Chip(
                              label: Text(
                                  '${entry.key.toUpperCase()}  ·  ${entry.value}'),
                              backgroundColor: entry.value == 'normal'
                                  ? Colors.teal.withValues(alpha: .18)
                                  : entry.value == 'basic'
                                      ? Colors.orange.withValues(alpha: .18)
                                      : Colors.red.withValues(alpha: .18),
                            ))
                        .toList())),
        _Panel(
            title: 'CENTRAL MARKET / LIVE SIGNALS',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Settlement fee: ${(state.marketFeeRate * 100).toStringAsFixed(2)}% · buyer total includes the disclosed fee',
                  style: const TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 10),
              Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: state.market.entries.map((entry) {
                    final product = entry.value as Map<String, dynamic>;
                    return SizedBox(
                        width: 150,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.key.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 5),
                              Text('${product['price']} C',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text(
                                  'S ${product['supply']}  ·  D ${product['demand']}',
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() => const EarthApi()
                                          .submitOrder(
                                              entry.key,
                                              (product['price'] as num)
                                                  .toDouble())),
                                  child: const Text('BUY 1')),
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() => const EarthApi()
                                          .submitOrder(
                                              entry.key,
                                              (product['price'] as num)
                                                  .toDouble(),
                                              side: 'sell')),
                                  child: const Text('SELL 1')),
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() => const EarthApi()
                                          .settleMarket(entry.key)),
                                  child: const Text('SETTLE'))
                            ]));
                  }).toList())
            ])),
        _Panel(
            title: 'CENTRAL MARKET / ORDER BOOK',
            child: state.marketBook.isEmpty
                ? const Text(
                    'No open orders. The market is waiting for a new signal.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.marketBook.map((raw) {
                      final row = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${row['product']}  ·  ${row['open_quantity']} open  ·  best ${row['best_price']} C',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'MY OPEN MARKET ORDERS',
            child: state.marketOrders.isEmpty
                ? const Text('No open orders.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.marketOrders.map((raw) {
                      final order = raw as Map<String, dynamic>;
                      final remaining = (order['quantity'] as num) -
                          (order['filled_quantity'] as num);
                      return Row(children: [
                        Expanded(
                            child: Text(
                                '${order['side']} ${order['product']} · $remaining remaining · ${order['limit_price']} C',
                                style: const TextStyle(fontSize: 11))),
                        OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi()
                                    .cancelOrder(order['id'] as String)),
                            child: const Text('CANCEL')),
                      ]);
                    }).toList())),
        _Panel(
            title: 'LIFE / SUCCESSION',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Status: ${state.life['status']}  ·  age ${state.life['ageYears']} years',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 8),
              Text(state.life['successor'] == null
                  ? 'No successor registered.'
                  : 'Successor: ${(state.life['successor'] as Map<String, dynamic>)['successor_name']}'),
              const SizedBox(height: 8),
              Text('Estate period: ${state.life['estatePeriodDays']} days',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showSuccessorComposer(context, action),
                  child: const Text('PLAN SUCCESSION'))
            ])),
        _Panel(
            title: 'CENTRAL LEDGER / RECENT ACTIVITY',
            child: state.ledgerEntries.isEmpty
                ? const Text('No ledger activity yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.ledgerEntries.take(8).map((raw) {
                      final entry = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${entry['reason_type']}  ·  ${entry['amount']} ${entry['currency']}\n${entry['debit_account']} → ${entry['credit_account']}',
                              style: const TextStyle(fontSize: 12)));
                    }).toList())),
        _Panel(
            title: 'WORLD FEED / RECENT EVENTS',
            child: events.isEmpty
                ? const Text('No public events recorded yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: events.take(8).map((raw) {
                      final event = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                              '${event['type']}  ·  ${event['actor']}  ·  ${event['occurred_at']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'NOTIFICATIONS / $unreadNotifications UNREAD',
            child: notifications.isEmpty
                ? const Text('No personal alerts yet.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: notifications.take(8).map((raw) {
                      final notification = raw as Map<String, dynamic>;
                      final unread = notification['read_at'] == null;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    '${unread ? '• ' : ''}${notification['title']}\n${notification['body']}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: unread
                                            ? FontWeight.w700
                                            : FontWeight.normal))),
                            if (unread)
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() async {
                                            await const EarthApi()
                                                .markNotificationRead(
                                                    notification['id']
                                                        as String);
                                            return state;
                                          }),
                                  child: const Text('READ')),
                          ]));
                    }).toList())),
        _Panel(
            title: 'OWNERSHIP / PROVENANCE TIMELINE',
            child: ownershipEvents.isEmpty
                ? const Text(
                    'Your asset history will appear here after your first acquisition or transfer.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: ownershipEvents.take(8).map((raw) {
                      final event = raw as Map<String, dynamic>;
                      final direction = event['from_owner_id'] == null
                          ? 'acquired'
                          : 'transferred';
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              'DAY ${event['game_day']}  ·  ${event['asset_type']} ${event['asset_id']} $direction  ·  ${event['quantity']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'CIVIC STATUS / MEMBERSHIP HISTORY',
            child: membershipEvents.isEmpty
                ? const Text(
                    'Your civic and corporate history will appear here after joining an institution.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: membershipEvents.take(8).map((raw) {
                      final event = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              'DAY ${event['game_day']}  ·  ${event['institution_type']} ${event['institution_id']}  ·  ${event['action']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'AUTHORITY / GOVERNANCE HISTORY',
            child: authorityEvents.isEmpty
                ? const Text(
                    'Role claims and resignations will appear here as your institutional authority develops.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: authorityEvents.take(8).map((raw) {
                      final event = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              'DAY ${event['game_day']}  ·  ${event['action']}  ·  ROLE ${event['role_id']}',
                              style: const TextStyle(fontSize: 11)));
                    }).toList())),
        _Panel(
            title: 'WORLD RANKINGS / POSTGRES LIVE',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RankingLine('CITIES', state.rankings['cities']),
              const SizedBox(height: 12),
              _RankingLine('CORPORATIONS', state.rankings['corporations']),
            ])),
        _Panel(
            title: 'HISTORY / ARCHIVE',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((state.history['events'] as List<dynamic>?)?.isEmpty ?? true)
                const Text(
                    'The archive is waiting for the first recorded world day.')
              else
                ...((state.history['events'] as List<dynamic>?) ?? const [])
                    .take(5)
                    .map((raw) {
                  final event = raw as Map<String, dynamic>;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                          'DAY ${event['game_day']}  ·  ${event['title']}',
                          style: const TextStyle(fontSize: 11)));
                }),
              const SizedBox(height: 6),
              const Text(
                  'Rankings and Human legacies are preserved as the world changes.',
                  style: TextStyle(color: _muted, fontSize: 10)),
            ])),
        _Panel(
            title: 'COMMUNITIES / SHARED LIFE',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (state.communities.isEmpty)
                const Text('No communities registered yet.')
              else
                ...state.communities.take(5).map((raw) {
                  final community = raw as Map<String, dynamic>;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                          '${community['name']}  ·  ${community['status']}',
                          style: const TextStyle(fontSize: 11)));
                }),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () =>
                            action(() => const EarthApi().createCommunity()),
                    child: const Text('FOUND CARTHAGE MAKERS')),
                if (state.communities.isNotEmpty)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() {
                                final id = (state.communities.first
                                    as Map<String, dynamic>)['id'] as String;
                                return const EarthApi()
                                    .contributeToCommunity(id, 50);
                              }),
                      child: const Text('CONTRIBUTE 50 C')),
                if (state.communities.isNotEmpty)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() {
                                final id = (state.communities.first
                                    as Map<String, dynamic>)['id'] as String;
                                return const EarthApi().joinCommunity(id);
                              }),
                      child: const Text('JOIN COMMUNITY')),
                if (state.communities.isNotEmpty)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() {
                                final id = (state.communities.first
                                    as Map<String, dynamic>)['id'] as String;
                                return const EarthApi().leaveCommunity(id);
                              }),
                      child: const Text('LEAVE COMMUNITY')),
              ]),
            ])),
        _Panel(
            title: 'WORLD INTEGRITY / AUDIT',
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.audit.entries
                    .map((entry) => Chip(
                          label: Text(
                              '${entry.key}: ${entry.value ? 'OK' : 'CHECK'}',
                              style: const TextStyle(fontSize: 10)),
                          avatar: Icon(
                              entry.value ? Icons.check_circle : Icons.warning,
                              size: 14,
                              color: entry.value ? _cyanAccent : Colors.orange),
                          backgroundColor: Colors.white10,
                        ))
                    .toList())),
        _Panel(
            title: 'INSTITUTION SOLVENCY / RECOVERY',
            child: state.financeStatus.isEmpty
                ? const Text(
                    'Financial states will appear after the next world-day assessment.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.financeStatus.map((raw) {
                      final item = raw as Map<String, dynamic>;
                      final crisis = item['status'] == 'distressed' ||
                          item['status'] == 'insolvent';
                      final recoverable = item['institution_kind'] == 'CITY' ||
                          item['institution_kind'] == 'CORPORATION';
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${item['institution_kind']} ${item['institution_id']}  ·  ${item['status']}  ·  since day ${item['since_game_day']}',
                                    style: const TextStyle(fontSize: 11)),
                                if (crisis && recoverable)
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _showRecoveryDialog(
                                              context,
                                              action,
                                              item['institution_id'] as String,
                                              item['institution_kind']
                                                  as String),
                                      child: const Text('RECOVER')),
                              ]));
                    }).toList())),
        _Panel(
            title: 'PERSONAL FINANCE / PROTECTED MINIMUM',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Status: ${state.personalFinance['status'] ?? 'active'}  ·  protected minimum ${state.personalFinance['protected_credits'] ?? 100} C',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 6),
              const Text(
                  'A restructuring preserves one basic service robot and the protected Credit minimum; non-protected productive assets are liquidated.',
                  style: TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 8),
              if (state.personalFinance['status'] != 'bankrupt')
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => const EarthApi().declarePersonalInsolvency()),
                    child: const Text('DECLARE INSOLVENCY RESTRUCTURING')),
            ])),
        _Panel(
            title: 'NEGOTIATED CONTRACTS / DIRECT AGREEMENTS',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (state.contracts.isEmpty)
                const Text('No direct agreements yet.',
                    style: TextStyle(color: _muted, fontSize: 11))
              else
                ...state.contracts.take(8).map((raw) {
                  final contract = raw as Map<String, dynamic>;
                  final mine = contract['proposer_id'] == state.human['id'];
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                '${contract['title']}  ·  ${contract['kind']}  ·  ${contract['status']}  ·  ${contract['amount']} C',
                                style: const TextStyle(fontSize: 11))),
                        if (contract['status'] == 'proposed' && !mine)
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .acceptContract(
                                          contract['id'] as String)),
                              child: const Text('ACCEPT')),
                        if (contract['status'] == 'proposed')
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .cancelContract(
                                          contract['id'] as String)),
                              child: const Text('CANCEL')),
                        if ((contract['status'] == 'accepted' ||
                                contract['status'] == 'completed') &&
                            contract['dispute_id'] == null)
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _showDisputeDialog(context, action,
                                      contract['id'] as String),
                              child: const Text('DISPUTE')),
                        if (contract['dispute_id'] != null)
                          const Text('DISPUTE OPEN',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 10)),
                        if (canArbitrate && contract['dispute_id'] != null)
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _showResolveDialog(context, action,
                                      contract['id'] as String),
                              child: const Text('ARBITRATE')),
                      ]));
                }),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _showContractComposer(context, action),
                  child: const Text('PROPOSE AGREEMENT')),
            ])),
        _Panel(
            title: 'MACRO LIQUIDITY / WORLD ENGINE SIGNAL',
            child: Text(
                'Supply ${state.finance['liquidity']?['moneySupply'] ?? '—'} C  ·  target ${state.finance['liquidity']?['target'] ?? '—'} C  ·  ${state.finance['liquidity']?['status'] ?? 'unknown'}',
                style: const TextStyle(fontSize: 11, color: _muted))),
        _Panel(
            title: 'AUTHORITY / ACTIVE TERMS',
            child: state.roles.isEmpty
                ? const Text('No institutional terms are active yet.',
                    style: TextStyle(color: _muted, fontSize: 11))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.roles.map((raw) {
                      final role = raw as Map<String, dynamic>;
                      final holder = role['human_id'] as String?;
                      final isMine = holder == state.human['id'];
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    '${role['name']}  ·  ${holder ?? 'OPEN'}  ·  until day ${role['ends_game_day'] ?? '—'}',
                                    style: const TextStyle(fontSize: 11))),
                            if (isMine)
                              Wrap(spacing: 6, children: [
                                OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => action(() => const EarthApi()
                                            .resignRole(role['id'] as String)),
                                    child: const Text('RESIGN')),
                                OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => _showDelegateDialog(context,
                                            action, role['id'] as String),
                                    child: const Text('DELEGATE')),
                              ])
                            else if (holder == null)
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() => const EarthApi()
                                          .claimRole(role['id'] as String)),
                                  child: const Text('CLAIM')),
                            if (!isMine && holder != null)
                              OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => action(() => const EarthApi()
                                          .recallRole(role['id'] as String)),
                                  child: const Text('RECALL')),
                          ]));
                    }).toList())),
        _Panel(
            title: 'PUBLIC FINANCE / GOVERNANCE',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...((state.finance['taxRules'] as List<dynamic>?) ?? const [])
                  .map((raw) {
                final rule = raw as Map<String, dynamic>;
                return Text(
                    '${rule['scope']} / ${rule['category']}  ·  ${(NumberFormatHelper.percent(rule['rate']))}  ·  v${rule['version']}',
                    style: const TextStyle(color: _muted, fontSize: 11));
              }),
              const SizedBox(height: 8),
              const Text(
                  'Treasury settlement and public spending require authenticated player action.',
                  style: TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() => const EarthApi().settleTax(1000)),
                  child: const Text('SETTLE BASIC LEVY ON 1,000 C')),
              if (state.roles.any((raw) {
                final role = raw as Map<String, dynamic>;
                final holder = role['human_id']?.toString();
                final roleId = role['id']?.toString();
                return holder == state.human['id'] &&
                    (roleId == 'ROLE-CITY-MAYOR' ||
                        roleId == 'ROLE-CITY-PLANNER');
              })) ...[
                const SizedBox(height: 8),
                const Text(
                    'As an active city finance role, you can route UC funds into local services.',
                    style: TextStyle(color: _muted, fontSize: 10)),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => action(() => const EarthApi()
                            .spendPublicFinance(
                                'CITY-0084', 'public-services', 100)),
                    child: const Text('FUND CITY SERVICES FROM UC · 100 C')),
              ],
            ]))
      ]),
    ]);
  }
}

class _OpportunityPanel extends StatelessWidget {
  final List<dynamic> opportunities;
  const _OpportunityPanel({required this.opportunities});

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'LIVE OPPORTUNITIES',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: opportunities.map((raw) {
            final opportunity = Map<String, dynamic>.from(raw as Map);
            final signal = opportunity['signal']?.toString() ?? 'world';
            final priority = opportunity['priority']?.toString() ?? 'medium';
            final color = priority == 'high'
                ? Colors.orangeAccent
                : priority == 'low'
                    ? Colors.tealAccent
                    : _violet;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opportunity['title']?.toString() ?? 'World signal',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(opportunity['detail']?.toString() ?? '',
                            style:
                                const TextStyle(color: _muted, fontSize: 11)),
                        const SizedBox(height: 3),
                        Text(signal.toUpperCase(),
                            style: TextStyle(
                                color: color, fontSize: 9, letterSpacing: 1.1)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
}

String _percent(dynamic value) {
  final number = value is num ? value.toDouble() : 0.0;
  return '${(number.clamp(0, 1) * 100).round()}%';
}

String _formatProposalDeadline(Map<String, dynamic> deadline) {
  final day = deadline['gameDay'] ?? deadline['game_day'] ?? '—';
  final minute = (deadline['gameMinute'] ?? deadline['game_minute']) as num?;
  final remaining = (deadline['realSecondsRemaining'] ??
      deadline['real_seconds_remaining']) as num?;
  final clock = minute == null
      ? '—'
      : '${(minute.toInt() ~/ 60).toString().padLeft(2, '0')}:${(minute.toInt() % 60).toString().padLeft(2, '0')}';
  final seconds = remaining?.toInt() ?? 0;
  final duration = seconds >= 86400
      ? '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h'
      : seconds >= 3600
          ? '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m'
          : '${seconds ~/ 60}m';
  return 'Closes game day $day at $clock · in $duration real time';
}

class _RankingLine extends StatelessWidget {
  final String label;
  final dynamic rows;
  const _RankingLine(this.label, this.rows);
  @override
  Widget build(BuildContext context) {
    final list = rows is List ? rows : const [];
    final first = list.isEmpty ? null : list.first as Map<String, dynamic>;
    final value = first == null
        ? 'No entries yet'
        : label == 'CITIES'
            ? '${first['id']}  ·  ${first['residents']} residents'
            : '${first['id']}  ·  ${first['member_count']} members';
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style:
              const TextStyle(color: _muted, fontSize: 10, letterSpacing: 1)),
      Text(value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))
    ]);
  }
}

Future<void> _showBusinessManager(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final manager = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Appoint business manager'),
            content: TextField(
                controller: manager,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Manager Human ID')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    if (manager.text.trim().isEmpty) return;
                    await action(() => const EarthApi()
                        .appointBusinessManager(businessId, manager.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('APPOINT')),
            ],
          ));
  manager.dispose();
}

Future<void> _showBusinessLiquidationDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Liquidate business?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'This permanently closes the business. Its machines will be detached and preserved for future disposition; financial and production history remains recorded.',
                  style: TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    await action(() => const EarthApi()
                        .liquidateBusiness(businessId, otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: const Text('LIQUIDATE')),
            ],
          ));
  otp.dispose();
}

Future<void> _showBusinessConstitution(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    Map<String, dynamic> business) async {
  final shareholder = TextEditingController(
      text: '${business['shareholder_vote_threshold'] ?? 0.5}');
  final board = TextEditingController(
      text: '${business['board_approval_threshold'] ?? 0.5}');
  final notice =
      TextEditingController(text: '${business['dilution_notice_days'] ?? 3}');
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Business Constitution'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Separate ownership from management with explicit approval thresholds and dilution notice.',
                  style: TextStyle(color: _muted, fontSize: 12)),
              TextField(
                  controller: shareholder,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Shareholder vote threshold (0–1)')),
              TextField(
                  controller: board,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Board approval threshold (0–1)')),
              TextField(
                  controller: notice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Dilution notice (days)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    final shareValue = double.tryParse(shareholder.text.trim());
                    final boardValue = double.tryParse(board.text.trim());
                    final noticeValue = int.tryParse(notice.text.trim());
                    final businessId = business['id'] as String?;
                    if (businessId == null ||
                        shareValue == null ||
                        boardValue == null ||
                        noticeValue == null) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .updateBusinessConstitution(
                            businessId, shareValue, boardValue, noticeValue));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('SAVE CONSTITUTION')),
            ],
          ));
  shareholder.dispose();
  board.dispose();
  notice.dispose();
}

Future<void> _showShareTransfer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final recipient = TextEditingController();
  final shares = TextEditingController(text: '1');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Transfer business shares'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: recipient,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Recipient Human ID')),
                const SizedBox(height: 12),
                TextField(
                    controller: shares,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Shares to transfer')),
                const SizedBox(height: 12),
                TextField(
                    controller: otp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Authenticator code (if enabled)')),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final amount = int.tryParse(shares.text.trim());
                    if (recipient.text.trim().isEmpty ||
                        amount == null ||
                        amount < 1) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .transferShares(recipient.text, amount, otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Transfer')),
            ],
          ));
  recipient.dispose();
  shares.dispose();
  otp.dispose();
}

Future<void> _showShareIssue(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final recipient = TextEditingController();
  final shares = TextEditingController(text: '10');
  final price = TextEditingController(text: '10');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Issue business shares'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: recipient,
                  decoration:
                      const InputDecoration(labelText: 'Buyer Human ID')),
              TextField(
                  controller: shares,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Shares')),
              TextField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Price per share')),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final count = int.tryParse(shares.text.trim());
                    final value = double.tryParse(price.text.trim());
                    if (recipient.text.trim().isEmpty ||
                        count == null ||
                        count < 1 ||
                        value == null ||
                        value <= 0) {
                      return;
                    }
                    await action(() => const EarthApi().issueShares(
                        businessId, recipient.text, count, value,
                        otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Issue')),
            ],
          ));
  recipient.dispose();
  shares.dispose();
  price.dispose();
  otp.dispose();
}

Future<void> _showSuccessorComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController(text: 'Alex Kline');
  final humanId = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Plan succession'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Successor name')),
              const SizedBox(height: 10),
              TextField(
                  controller: humanId,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Existing Human ID (optional)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (name.text.trim().length < 2) return;
                    await action(() => const EarthApi().registerSuccessor(
                        name.text,
                        successorHumanId: humanId.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Save plan')),
            ],
          ));
  name.dispose();
  humanId.dispose();
}

Future<void> _showDecommissionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Recycle machine?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'This permanently decommissions the machine and returns a condition-based fraction of its embedded resources.'),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    await action(() => const EarthApi()
                        .decommissionMachine(machineId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Recycle')),
            ],
          ));
  otp.dispose();
}

Future<void> _showAiUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String assistantId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Upgrade to Business AI'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Upgrade cost: 2,400 Credits. Business AI remains bounded to recommendations and machine maintenance; it cannot vote or hold authority.'),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    await action(() => const EarthApi()
                        .upgradeAi(assistantId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Upgrade')),
            ],
          ));
  otp.dispose();
}

Future<void> _showMachineUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Upgrade machine'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Upgrade cost: 600 Credits and 20 Components. Capacity increases by 0.2 and installation reduces condition by 5%.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    await action(() => const EarthApi()
                        .upgradeMachine(machineId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Upgrade')),
            ],
          ));
  otp.dispose();
}

Future<void> _showMachineSaleDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final buyer = TextEditingController();
  final price = TextEditingController(text: '1200');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Sell machine'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: buyer,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Buyer Human ID')),
              TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price in Credits')),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final value = double.tryParse(price.text.trim());
                    if (buyer.text.trim().isEmpty ||
                        value == null ||
                        value <= 0) {
                      return;
                    }
                    await action(() => const EarthApi().sellMachine(
                        machineId, buyer.text, value,
                        otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Sell')),
            ],
          ));
  buyer.dispose();
  price.dispose();
  otp.dispose();
}

Future<void> _showFormationComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    {required bool city, String? communityId, String? cityId}) async {
  final name = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: Text(city ? 'Form a City' : 'Form a Corporation'),
            content: TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: city ? 'City name' : 'Corporation name')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (name.text.trim().length < 3) return;
                    final selectedName = name.text.trim();
                    await action(() => city
                        ? const EarthApi()
                            .createCity(selectedName, communityId!)
                        : const EarthApi()
                            .createCorporation(selectedName, cityId!));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit')),
            ],
          ));
  name.dispose();
}

Future<void> _showBusinessComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController();
  String sector = 'maintenance';
  const sectors = [
    'energy',
    'extraction',
    'components',
    'machines',
    'maintenance',
    'housing',
    'compute',
    'r-and-d'
  ];
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Register a Business'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Business name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                      initialValue: sector,
                      items: sectors
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => sector = value);
                      },
                      decoration: const InputDecoration(labelText: 'Sector')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        if (name.text.trim().length < 3) return;
                        await action(() => const EarthApi()
                            .createBusiness(name.text.trim(), sector));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Register')),
                ],
              )));
  name.dispose();
}

Future<void> _showResearchComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController();
  final budget = TextEditingController(text: '240');
  String focus = 'efficiency';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Start Research Project'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Technology focus')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: budget,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Initial budget (minimum 240 C)')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                      initialValue: focus,
                      items: const [
                        'efficiency',
                        'durability',
                        'safety',
                        'cost'
                      ]
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => focus = value);
                      },
                      decoration: const InputDecoration(
                          labelText: 'Research parameter focus')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        final amount = double.tryParse(budget.text.trim());
                        if (name.text.trim().length < 3 ||
                            amount == null ||
                            amount < 240) {
                          return;
                        }
                        await action(() => const EarthApi().startResearch(
                            name.text.trim(), amount,
                            focus: focus));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Start')),
                ],
              )));
  name.dispose();
  budget.dispose();
}

Future<void> _showLicenseComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final licensee = TextEditingController();
  final fee = TextEditingController(text: '100');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('License technology'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: licensee,
                  decoration:
                      const InputDecoration(labelText: 'Licensee Human ID')),
              TextField(
                  controller: fee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'License fee (minimum 50 C)')),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(fee.text.trim());
                    if (licensee.text.trim().isEmpty ||
                        amount == null ||
                        amount < 50) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .licenseTechnologyTo(licensee.text, amount, otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('License')),
            ],
          ));
  licensee.dispose();
  fee.dispose();
  otp.dispose();
}

Future<void> _showDelegateDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String roleId) async {
  final delegate = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Delegate authority'),
            content: TextField(
                controller: delegate,
                decoration:
                    const InputDecoration(labelText: 'Active Human ID')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (delegate.text.trim().isEmpty) return;
                    await action(() =>
                        const EarthApi().delegateRole(roleId, delegate.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Delegate')),
            ],
          ));
  delegate.dispose();
}

Future<void> _showContractComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final counterparty = TextEditingController();
  final title = TextEditingController();
  final amount = TextEditingController(text: '100');
  var kind = 'intellectual_service';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Propose agreement'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: kind,
                      items: const [
                        DropdownMenuItem(
                            value: 'employment', child: Text('Employment')),
                        DropdownMenuItem(
                            value: 'intellectual_service',
                            child: Text('Intellectual service')),
                        DropdownMenuItem(
                            value: 'capacity', child: Text('Capacity')),
                        DropdownMenuItem(
                            value: 'strategic', child: Text('Strategic')),
                      ],
                      onChanged: (value) =>
                          setState(() => kind = value ?? kind)),
                  TextField(
                      controller: counterparty,
                      decoration: const InputDecoration(
                          labelText: 'Counterparty Human ID')),
                  TextField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'Agreement title')),
                  TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Credits')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        final value = double.tryParse(amount.text.trim());
                        if (counterparty.text.trim().isEmpty ||
                            title.text.trim().length < 3 ||
                            value == null ||
                            value < 0) {
                          return;
                        }
                        await action(() => const EarthApi().createContract(
                            kind, counterparty.text, title.text, value));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Propose')),
                ],
              )));
  counterparty.dispose();
  title.dispose();
  amount.dispose();
}

Future<void> _showDisputeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String contractId) async {
  final reason = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Open UC arbitration'),
            content: TextField(
                controller: reason,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Reason (10–1000 characters)')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (reason.text.trim().length < 10) return;
                    await action(() => const EarthApi()
                        .disputeContract(contractId, reason.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit dispute')),
            ],
          ));
  reason.dispose();
}

Future<void> _showRecoveryDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String institutionId,
  String institutionKind,
) async {
  final amount = TextEditingController(text: '100');
  final otp = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Recover $institutionKind'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
            'Contribute Credits to restore this institution to active status.',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Recovery contribution (Credits)')),
        const SizedBox(height: 8),
        TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Authenticator code (if enabled)')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: () async {
              final parsed = double.tryParse(amount.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().recoverInstitution(
                  institutionId, parsed,
                  otp: otp.text.trim()));
            },
            child: const Text('AUTHORIZE RECOVERY')),
      ],
    ),
  );
  amount.dispose();
  otp.dispose();
}

Future<void> _showResolveDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String contractId) async {
  final resolution = TextEditingController();
  var outcome = 'uphold';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Resolve UC arbitration'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: outcome,
                      items: const [
                        DropdownMenuItem(
                            value: 'uphold', child: Text('Uphold contract')),
                        DropdownMenuItem(
                            value: 'void', child: Text('Void and refund')),
                      ],
                      onChanged: (value) =>
                          setState(() => outcome = value ?? outcome)),
                  TextField(
                      controller: resolution,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Resolution (10–1000 characters)')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        if (resolution.text.trim().length < 10) return;
                        await action(() => const EarthApi().resolveContract(
                            contractId, outcome, resolution.text));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Resolve')),
                ],
              )));
  resolution.dispose();
}

Future<void> _showProposalComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final title = TextEditingController();
  final body = TextEditingController();
  final targetRate = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Create UC proposal'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    maxLength: 140,
                    decoration: const InputDecoration(
                        labelText: 'Title (8–140 characters)')),
                const SizedBox(height: 12),
                TextField(
                    controller: body,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                        labelText: 'Policy proposal (20–4000 characters)')),
                const SizedBox(height: 12),
                TextField(
                    controller: targetRate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Optional UC finance rate (0–0.25)')),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (title.text.trim().length < 8 ||
                        body.text.trim().length < 20) {
                      return;
                    }
                    final rate = targetRate.text.trim().isEmpty
                        ? null
                        : double.tryParse(targetRate.text.trim());
                    if (targetRate.text.trim().isNotEmpty &&
                        (rate == null || rate < 0 || rate > .25)) {
                      return;
                    }
                    await action(() => const EarthApi().createProposal(
                        title.text.trim(), body.text.trim(),
                        targetCategory: rate == null ? null : 'finance',
                        targetRate: rate));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit proposal')),
            ],
          ));
  title.dispose();
  body.dispose();
  targetRate.dispose();
}

class _Sidebar extends StatelessWidget {
  final EarthState state;
  const _Sidebar({required this.state});
  @override
  Widget build(BuildContext context) {
    final name = '${state.human['name'] ?? 'Human'}';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final city =
        '${(state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';
    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Colors.white12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('◌  EARTH',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 3)),
        const Padding(
            padding: EdgeInsets.only(left: 28, top: 2, bottom: 26),
            child: Text('UNITED CORPORATIONS',
                style:
                    TextStyle(fontSize: 8, color: _muted, letterSpacing: 1.2))),
        Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: _surface.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12)),
            child: Row(children: [
              CircleAvatar(
                  radius: 16,
                  backgroundColor: _violet,
                  child: Text(initials.isEmpty ? 'H' : initials,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800))),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    Text('Human · $city',
                        style: const TextStyle(fontSize: 8, color: _muted))
                  ]))
            ])),
        const SizedBox(height: 22),
        for (final item in [
          '✦  Command center',
          '⌁  Central Market',
          '◈  Kline Works',
          '⊙  Civic life',
          '⌖  New Carthage',
          '✧  Technology'
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(item,
                  style: TextStyle(
                      color: item.startsWith('✦') ? _violet : _muted,
                      fontSize: 11,
                      fontWeight: item.startsWith('✦')
                          ? FontWeight.w700
                          : FontWeight.w500))),
        const Spacer(),
        const Divider(color: Colors.white12),
        const Text('●  WORLD CLOCK',
            style:
                TextStyle(color: _cyanAccent, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 7),
        Text('DAY ${state.clock['day']} · ${state.clock['minute']}',
            style: const TextStyle(fontSize: 10, letterSpacing: 1))
      ]),
    );
  }
}

const _cyanAccent = Color(0xff55d8b2);

class NumberFormatHelper {
  static String percent(dynamic value) =>
      '${(double.tryParse('$value') ?? 0) * 100}%';
}

class _HeroCard extends StatelessWidget {
  final EarthState state;
  const _HeroCard({required this.state});
  @override
  Widget build(BuildContext context) => Container(
      height: 218,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          gradient:
              const LinearGradient(colors: [_surface, Color(0xff24234c)])),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('●  WORLD HEALTH · STABLE',
              style:
                  TextStyle(color: _cyanAccent, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 13),
          Text('${state.world['health']}',
              style: const TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -4)),
          Text(
              'LCI ${state.world['livingCostIndex']}  ·  ESI ${state.world['essentialServicesIndex']}',
              style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
        Positioned(
            right: 55,
            top: 3,
            child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _violet.withValues(alpha: .5), width: 1),
                    boxShadow: [
                      BoxShadow(
                          color: _violet.withValues(alpha: .22), blurRadius: 40)
                    ]),
                child: Center(
                    child: Container(
                        width: 82,
                        height: 82,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                                colors: [_violet, Color(0xff5145b7)])),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('EARTH',
                                  style:
                                      TextStyle(fontSize: 8, letterSpacing: 2)),
                              Text('${state.clock['day']}',
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800)),
                              const Text('DAY',
                                  style:
                                      TextStyle(fontSize: 8, letterSpacing: 1))
                            ])))))
      ]));
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final width =
        (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 360.0).toDouble();
    return SizedBox(
        width: width,
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      child
                    ]))));
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _Metric(
      {required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 210,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 10, letterSpacing: 1, color: accent)),
                    const SizedBox(height: 12),
                    Text(value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700, letterSpacing: -.5))
                  ]))));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _ErrorState({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('RECONNECT'))
      ]);
}
