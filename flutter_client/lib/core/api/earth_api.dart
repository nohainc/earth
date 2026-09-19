import 'dart:math';
import 'earth_api_transport.dart';
import '../auth_storage.dart';
import '../models/earth_state.dart';
import '../models/corporation_directory_entry.dart';
import '../models/corporation_profile.dart';
import '../models/governance_proposal.dart';
import '../models/house_profile.dart';
import '../models/building_models.dart';
import '../models/command_overview.dart';

part 'earth_api_auth.dart';
part 'earth_api_world.dart';
part 'earth_api_technology.dart';
part 'earth_api_market.dart';
part 'earth_api_lifecycle.dart';
part 'earth_api_governance.dart';
part 'earth_api_institutions.dart';
part 'earth_api_personal_finance.dart';
part 'earth_api_comm.dart';
part 'earth_api_house.dart';
part 'earth_api_net_worth.dart';
part 'earth_api_daily_summary.dart';
part 'earth_api_onboarding.dart';
part 'earth_api_entry_support.dart';
part 'earth_api_real_estate.dart';
part 'earth_api_organizations.dart';
part 'earth_api_residency.dart';
part 'earth_api_mutual_credit.dart';
part 'earth_api_command_overview.dart';


String newClientCorrelationId(String prefix) =>
    '$prefix-${Random.secure().nextInt(0x7fffffff)}';

class EarthApi {
  final String baseUrl;
  final EarthApiTransport? _customTransport;
  const EarthApi({String? baseUrl, EarthApiTransport? transport})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL', defaultValue: ''),
        _customTransport = transport;

  EarthApiTransport get _transport =>
      _customTransport ??
      EarthApiTransport(baseUrl: baseUrl.isNotEmpty ? baseUrl : null);

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    return _transport.request(path, method: method, body: body);
  }
}
