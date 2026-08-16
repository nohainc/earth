import 'earth_api_transport.dart';
import '../models/earth_state.dart';

part 'earth_api_auth.dart';
part 'earth_api_world.dart';
part 'earth_api_business.dart';
part 'earth_api_technology.dart';
part 'earth_api_machines.dart';
part 'earth_api_market.dart';
part 'earth_api_lifecycle.dart';
part 'earth_api_governance.dart';

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
