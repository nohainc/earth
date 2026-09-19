part of 'earth_api.dart';

extension EarthApiCommandOverview on EarthApi {
  Future<CommandOverview?> getCommandOverview() async {
    final res = await _request('/api/v5/command/overview');
    if (res is Map<String, dynamic>) {
      return CommandOverview.fromJson(res);
    }
    if (res is Map) {
      return CommandOverview.fromJson(Map<String, dynamic>.from(res));
    }
    return null;
  }
}

