part of 'earth_api.dart';

extension EarthApiTechnology on EarthApi {
  // --- Technology & AI ---

  Future<EarthState> fundResearch() async {
    await _request('/api/technology/me/fund', method: 'POST', body: {
      'amount': 240,
      'correlationId':
          newClientCorrelationId('research-funding'),
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
          newClientCorrelationId('research-project'),
    });
    return world();
  }

  Future<EarthState> startCorporationBuildingResearch(String buildingType) async {
    await _request('/api/corporation/building-research', method: 'POST', body: {
      'buildingType': buildingType,
      'correlationId':
          newClientCorrelationId('corporation-building-research'),
    });
    return world();
  }

  Future<EarthState> grantPatent() async {
    await _request('/api/technology/me/patent', method: 'POST');
    return world();
  }

  Future<EarthState> adoptTechnology(String technologyId) async {
    await _request('/api/technology/adopt', method: 'POST', body: {
      'technologyId': technologyId,
    });
    return world();
  }

  Future<EarthState> setTechnologySubscription(String technologyKey, {required bool active}) async {
    await _request('/api/technology/subscription', method: 'POST', body: {
      'technologyKey': technologyKey,
      'status': active ? 'active' : 'inactive',
      'correlationId': newClientCorrelationId('technology-subscription-$technologyKey-${active ? 'on' : 'off'}'),
    });
    return world();
  }

  Future<EarthState> licenseTechnology() async {
    await _request('/api/technology/me/license', method: 'POST', body: {
      'royaltyRate': 0.05,
    });
    return world();
  }

  Future<EarthState> licenseTechnologyTo(
      String licenseeId, double fee, String otp,
      {String? licenseeBusinessId}) async {
    await _request('/api/technology/me/license', method: 'POST', body: {
      'licenseeId': licenseeId.trim(),
      'licenseFee': fee,
      'royaltyRate': 0.05,
      'otp': otp,
      if (licenseeBusinessId != null && licenseeBusinessId.trim().isNotEmpty)
        'licenseeBusinessId': licenseeBusinessId.trim(),
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

}
