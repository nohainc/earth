part of 'earth_api.dart';

extension EarthApiInstitutions on EarthApi {
  Future<Map<String, dynamic>> getV5EarthCapacity() async {
    final response = await _request('/api/v5/capacity');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getV5HouseCapacity() async {
    final response = await _request('/api/v5/house/capacity');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getV5CorporationCapacity(String corporationId) async {
    final response = await _request('/api/v5/corporations/$corporationId/capacity');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> quoteV5CorporationMembership(String corporationId) async {
    final response = await _request('/api/v5/corporations/$corporationId/membership');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> applyV5CorporationMembership({required String corporationId, String? inviteToken, String? correlationId}) async {
    final response = await _request('/api/v5/corporations/$corporationId/membership', method: 'POST', body: {
      'correlationId': correlationId ?? newClientCorrelationId('v5-membership'),
      if (inviteToken != null && inviteToken.isNotEmpty) 'inviteToken': inviteToken,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<EarthState> joinV5Corporation({required String corporationId, String? inviteToken}) async {
    await applyV5CorporationMembership(corporationId: corporationId, inviteToken: inviteToken);
    return world();
  }

  Future<Map<String, dynamic>> listV5MembershipApplications(String corporationId, {String status = 'PENDING'}) async {
    final response = await _request('/api/v5/corporations/$corporationId/membership/applications?status=$status');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> quoteV5CorporationFounding(String name) async {
    final response = await _request('/api/v5/corporations/founding/quote', method: 'POST', body: {'name': name});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> foundV5Corporation({required String name, required String admissionPolicy, String? correlationId}) async {
    final response = await _request('/api/v5/corporations', method: 'POST', body: {
      'name': name,
      'admissionPolicy': admissionPolicy,
      'correlationId': correlationId ?? newClientCorrelationId('v5-founding'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> delegateV5CorporationLeadership({required String corporationId, required String targetHumanId, String? correlationId}) async {
    final response = await _request('/api/v5/corporations/$corporationId/leadership/delegate', method: 'POST', body: {
      'targetHumanId': targetHumanId,
      'correlationId': correlationId ?? newClientCorrelationId('v5-delegate-leadership'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> scheduleV5CorporationDissolution({required String corporationId, String? reason, int? transitionDays, String? correlationId}) async {
    final response = await _request('/api/v5/corporations/$corporationId/dissolution/schedule', method: 'POST', body: {
      if (reason != null) 'reason': reason,
      if (transitionDays != null) 'transitionDays': transitionDays,
      'correlationId': correlationId ?? newClientCorrelationId('v5-schedule-dissolution'),
    });
    return Map<String, dynamic>.from(response as Map);
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
    await _request('/api/v5/corporations/$corporationId/membership/leave',
        method: 'POST',
        body: {'correlationId': newClientCorrelationId('v5-leave')});
    return world();
  }

  Future<EarthState> setCorporationAdmissionPolicy({
    required String corporationId,
    required String policy,
  }) async {
    await proposeV5ConstitutionAmendment(
      subjectType: 'CORPORATION', subjectId: corporationId,
      title: 'Change Corporation admission policy',
      body: 'Propose a constitutional change to the Corporation admission policy.',
      changes: [{'ruleCode': 'CORPORATION.ADMISSION_POLICY', 'value': policy.toUpperCase()}],
    );
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
    await proposeV5ConstitutionAmendment(
      subjectType: 'CORPORATION', subjectId: corporationId,
      title: 'Change Corporation tax policy',
      body: 'Propose a constitutional change to the Corporation tax policy.',
      changes: [
        {'ruleCode': 'CORPORATION.TAX.INCOME_RATE', 'value': incomeTaxBps},
        {'ruleCode': 'CORPORATION.TAX.SALES_RATE', 'value': salesTaxBps},
        {'ruleCode': 'CORPORATION.TAX.CORPORATE_RATE', 'value': corporateTaxBps},
        {'ruleCode': 'CORPORATION.TAX.PROPERTY_RATE', 'value': propertyTaxBps},
      ],
    );
    return world();
  }

}
