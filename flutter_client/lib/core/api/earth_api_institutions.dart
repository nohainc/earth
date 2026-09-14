part of 'earth_api.dart';

extension EarthApiInstitutions on EarthApi {
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

  Future<Map<String, dynamic>> listCorporationTerritories(String corporationId) async {
    final response = await _request('/api/corporations/$corporationId/territories');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getCorporationFiscalState(String corporationId) async {
    final response = await _request('/api/finance/corporations/$corporationId');
    return Map<String, dynamic>.from(response as Map);
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

  Future<EarthState> createCorporation(String name, {String? territoryName}) async {
    await _request('/api/corporations',
        method: 'POST', body: {'name': name, if (territoryName != null) 'territoryName': territoryName});
    return world();
  }

  Future<EarthState> spendCorporationTreasury(double amount,
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/treasury/spend',
        method: 'POST',
        body: {
          'category': 'public-services',
          'amount': amount,
          'correlationId': newClientCorrelationId('corporation-spending'),
        });
    return world();
  }

  Future<EarthState> contributeCorporation(double amount,
      {String corporationId = 'CORP-001'}) async {
    await _request('/api/corporations/$corporationId/contributions',
        method: 'POST',
        body: {
          'amount': amount,
          'correlationId': newClientCorrelationId('corporation-contribution'),
        });
    return world();
  }

  Future<EarthState> createCommunity({
    required String name,
    String? description,
    String joinPolicy = 'OPEN',
    String? correlationId,
  }) async {
    await _request('/api/communities', method: 'POST', body: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'joinPolicy': joinPolicy,
      'correlationId':
          correlationId ?? newClientCorrelationId('community-formation'),
    });
    return world();
  }

  Future<EarthState> updateCommunity({
    required String communityId,
    String? description,
    String? visibility,
    String? joinPolicy,
  }) async {
    await _request('/api/communities/$communityId', method: 'PATCH', body: {
      if (description != null) 'description': description,
      if (visibility != null) 'visibility': visibility,
      if (joinPolicy != null) 'joinPolicy': joinPolicy,
    });
    return world();
  }

  Future<EarthState> disbandCommunity(String communityId) async {
    await _request('/api/communities/$communityId', method: 'DELETE', body: {});
    return world();
  }

  Future<Map<String, dynamic>> listCommunityMembers(String communityId) async {
    final res =
        await _request('/api/communities/$communityId/members', method: 'GET');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listCommunityRequests(String communityId) async {
    final res =
        await _request('/api/communities/$communityId/requests', method: 'GET');
    return res as Map<String, dynamic>;
  }

  Future<EarthState> decideCommunityRequest({
    required String communityId,
    required String requestId,
    required String action,
    String? rejectionReason,
  }) async {
    if (action != 'approve' && action != 'reject') {
      throw ArgumentError.value(action, 'action', 'must be approve or reject');
    }
    if (action == 'approve') {
      await _request(
          '/api/communities/$communityId/requests/$requestId/approve',
          method: 'POST',
          body: {});
    } else {
      await _request('/api/communities/$communityId/requests/$requestId/reject',
          method: 'POST',
          body: {
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              'rejectionReason': rejectionReason,
          });
    }
    return world();
  }

  Future<EarthState> setCommunityMemberRole({
    required String communityId,
    required String targetHouseId,
    required String role,
  }) async {
    await _request('/api/communities/$communityId/members/$targetHouseId',
        method: 'PATCH',
        body: {
          'role': role,
        });
    return world();
  }

  Future<EarthState> joinCommunity(String communityId,
      {String? applicationMessage}) async {
    await _request('/api/communities/$communityId/join', method: 'POST', body: {
      if (applicationMessage != null && applicationMessage.isNotEmpty)
        'applicationMessage': applicationMessage,
    });
    return world();
  }

  Future<EarthState> leaveCommunity(String communityId) async {
    await _request('/api/communities/$communityId/leave',
        method: 'POST', body: {});
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
              newClientCorrelationId('corp-tax-charter-$corporationId'),
        });
    return world();
  }

}
