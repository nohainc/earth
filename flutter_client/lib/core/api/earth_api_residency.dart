part of 'earth_api.dart';

extension EarthApiResidency on EarthApi {
  Future<Map<String, dynamic>> getHouseResidency() async {
    final response = await _request('/api/house/residency');
    return Map<String, dynamic>.from(response as Map);
  }

}
