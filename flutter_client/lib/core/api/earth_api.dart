import 'earth_api_transport.dart';
import '../auth_storage.dart';
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
part 'earth_api_contracts.dart';
part 'earth_api_personal_finance.dart';
part 'earth_api_comm.dart';

class EarthApi {
  final String baseUrl;
  final EarthApiTransport? _customTransport;
  const EarthApi({String? baseUrl, EarthApiTransport? transport})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL', defaultValue: ''),
        _customTransport = transport;

  EarthApiTransport get _transport =>
      _customTransport ?? EarthApiTransport(baseUrl: baseUrl);

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    return _transport.request(path, method: method, body: body);
  }
}
