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
    await _request('/api/research/buildings', method: 'POST', body: {
      'buildingType': buildingType,
      'correlationId':
          newClientCorrelationId('corporation-building-research'),
    });
    return world();
  }

}
