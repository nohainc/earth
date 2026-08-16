import 'earth_api_transport.dart';
import '../models/earth_state.dart';

part 'earth_api_auth.dart';
part 'earth_api_world.dart';
part 'earth_api_business.dart';
part 'earth_api_technology.dart';
part 'earth_api_machines.dart';

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
