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
part 'earth_api_institutions.dart';

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
