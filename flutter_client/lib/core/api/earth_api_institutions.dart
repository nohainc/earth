part of 'earth_api.dart';

extension EarthApiInstitutions on EarthApi {
  Future<List<Map<String, dynamic>>> listCities() async {
    final response = (await _request('/api/cities')) as Map<String, dynamic>;
    return (response['cities'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listCorporations({String? search}) async {
    final query = search == null || search.trim().isEmpty
        ? ''
        : '?search=${Uri.encodeQueryComponent(search.trim())}';
    final response =
        (await _request('/api/corporations$query')) as Map<String, dynamic>;
    return (response['corporations'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

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

  Future<EarthState> setCorporationAdmissionPolicy({
    required String corporationId,
    required String policy,
  }) async {
    await _request('/api/corporations/$corporationId/admission-policy',
        method: 'POST', body: {'policy': policy});
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

  Future<EarthState> createCorporationWithCapital({
    required String corporationName,
    required String cityName,
  }) async {
    await _request('/api/corporations/with-capital', method: 'POST', body: {
      'corporationName': corporationName,
      'cityName': cityName,
    });
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

  Future<EarthState> createCommunity({
    required String name,
    String? description,
    String admissionPolicy = 'open',
  }) async {
    await _request('/api/communities', method: 'POST', body: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'admissionPolicy': admissionPolicy,
      'correlationId':
          'community-formation-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> updateCommunity({
    required String communityId,
    String? description,
    String? admissionPolicy,
  }) async {
    await _request('/api/communities/$communityId', method: 'PATCH', body: {
      if (description != null) 'description': description,
      if (admissionPolicy != null) 'admissionPolicy': admissionPolicy,
    });
    return world();
  }

  Future<EarthState> disbandCommunity(String communityId) async {
    await _request('/api/communities/$communityId', method: 'DELETE');
    return world();
  }

  Future<Map<String, dynamic>> listCommunityMembers(String communityId) async {
    final res = await _request('/api/communities/$communityId/members', method: 'GET');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listCommunityRequests(String communityId) async {
    final res = await _request('/api/communities/$communityId/requests', method: 'GET');
    return res as Map<String, dynamic>;
  }

  Future<EarthState> decideCommunityRequest({
    required String communityId,
    required String requestId,
    required String action,
  }) async {
    await _request('/api/communities/$communityId/requests/$requestId', method: 'POST', body: {
      'action': action,
    });
    return world();
  }

  Future<EarthState> setCommunityMemberRole({
    required String communityId,
    required String targetHumanId,
    required String role,
  }) async {
    await _request('/api/communities/$communityId/members/$targetHumanId/role', method: 'POST', body: {
      'role': role,
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

  Future<EarthState> setCityTaxCharter({
    String cityId = 'CITY-0084',
    int incomeTaxBps = 0,
    int salesTaxBps = 0,
    int corporateTaxBps = 0,
    int propertyTaxBps = 0,
  }) async {
    await _request('/api/cities/$cityId/tax-charter', method: 'POST', body: {
      'incomeTaxBps': incomeTaxBps,
      'salesTaxBps': salesTaxBps,
      'corporateTaxBps': corporateTaxBps,
      'propertyTaxBps': propertyTaxBps,
      'correlationId':
          'tax-charter-$cityId-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> setCorporationTaxCharter({
    required String corporationId,
    int incomeTaxBps = 0,
    int salesTaxBps = 0,
    int corporateTaxBps = 0,
    int propertyTaxBps = 0,
  }) async {
    await _request('/api/corporations/$corporationId/tax-charter',
        method: 'POST',
        body: {
          'incomeTaxBps': incomeTaxBps,
          'salesTaxBps': salesTaxBps,
          'corporateTaxBps': corporateTaxBps,
          'propertyTaxBps': propertyTaxBps,
          'correlationId':
              'corp-tax-charter-$corporationId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> adoptCityForCorporation({
    required String corporationId,
    required String cityId,
  }) async {
    await _request('/api/corporations/$corporationId/cities/$cityId',
        method: 'POST');
    return world();
  }
}
