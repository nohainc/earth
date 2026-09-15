part of 'earth_api.dart';

extension EarthApiOnboarding on EarthApi {
  Future<Map<String, dynamic>> getHouseOnboarding() async {
    final result = await _request('/api/house/onboarding');
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'ok': false, 'error': 'Invalid onboarding response'};
  }

  Future<Map<String, dynamic>> advanceHouseOnboarding({
    String? milestone,
    bool expertSkip = false,
  }) async {
    final result = await _request(
      '/api/house/onboarding/advance',
      method: 'POST',
      body: {
        if (milestone != null) 'milestone': milestone,
        'expertSkip': expertSkip,
        'correlationId': newClientCorrelationId('onboarding'),
      },
    );
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'ok': false, 'error': 'Invalid onboarding update response'};
  }
}
