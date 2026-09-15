part of 'earth_api.dart';

extension EarthApiOrganizations on EarthApi {
  Future<Map<String, dynamic>> listCharterTemplates() async {
    final response = await _request('/api/organizations/charters/templates');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listOrganizations({String? archetype}) async {
    final suffix = archetype == null ? '' : '?archetype=${Uri.encodeQueryComponent(archetype)}';
    final response = await _request('/api/organizations$suffix');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createOrganization({
    required String name,
    required String archetype,
    String joinPolicy = 'OPEN',
    List<String>? capabilities,
  }) async {
    final response = await _request('/api/organizations', method: 'POST', body: {
      'name': name,
      'archetype': archetype,
      'joinPolicy': joinPolicy,
      if (capabilities != null) 'capabilities': capabilities,
      'correlationId': newClientCorrelationId('CREATE-ORG'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> joinOrganization({required String organizationId}) async {
    final response = await _request('/api/organizations/$organizationId/membership', method: 'POST', body: {
      'correlationId': newClientCorrelationId('JOIN-ORG'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationFinance({required String organizationId}) async {
    final response = await _request('/api/organizations/$organizationId/finance');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationCharter({required String organizationId, bool history = false}) async {
    final path = history
        ? '/api/organizations/$organizationId/charter/history'
        : '/api/organizations/$organizationId/charter';
    final response = await _request(path);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> validateOrganizationCharter({required String organizationId, required Map<String, dynamic> charter}) async {
    final response = await _request('/api/organizations/$organizationId/charter/validate', method: 'POST', body: {'charter': charter});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> amendOrganizationCharter({required String organizationId, required Map<String, dynamic> charter}) async {
    final response = await _request('/api/organizations/$organizationId/charter/amend', method: 'POST', body: {
      'charter': charter,
      'correlationId': newClientCorrelationId('AMEND-CHARTER'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationVotingMethod({required String organizationId}) async {
    final response = await _request('/api/governance/v4/organizations/$organizationId/method');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> setOrganizationVotingMethod({required String organizationId, required String votingMethod, int voiceCycleDays = 7, int voicePerCycle = 100}) async {
    final response = await _request('/api/governance/v4/organizations/$organizationId/method', method: 'POST', body: {
      'votingMethod': votingMethod,
      'voiceCycleDays': voiceCycleDays,
      'voicePerCycle': voicePerCycle,
      'correlationId': newClientCorrelationId('SET-VOTING-METHOD'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listEarthPrograms() async {
    final response = await _request('/api/earth/programs');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listEarthTechnologyGenerations() async {
    final response = await _request('/api/earth/technology/generations');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationAuthority({required String organizationId}) async {
    final response = await _request('/api/organizations/$organizationId/authority');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> appointOrganizationOffice({required String organizationId, required String officeCode, required String targetHumanId}) async {
    final response = await _request('/api/organizations/$organizationId/offices/$officeCode/appoint', method: 'POST', body: {
      'targetHumanId': targetHumanId,
      'correlationId': newClientCorrelationId('APPOINT-OFFICE'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> resignOrganizationOffice({required String organizationId, required String officeCode}) async {
    final response = await _request('/api/organizations/$organizationId/offices/$officeCode/resign', method: 'POST', body: {
      'correlationId': newClientCorrelationId('RESIGN-OFFICE'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getAssetOwnership({required String organizationId, required String assetId}) async {
    final response = await _request('/api/organizations/$organizationId/assets/$assetId/ownership');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> subscribeToAssetOwnership({required String organizationId, required String assetId, required String units, required String priceUnits, required String sourceAccountId}) async {
    final response = await _request('/api/organizations/$organizationId/assets/$assetId/ownership', method: 'POST', body: {
      'units': units,
      'priceUnits': priceUnits,
      'sourceAccountId': sourceAccountId,
      'investorType': 'HOUSE',
      'correlationId': newClientCorrelationId('SUBSCRIBE-OWNERSHIP'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> distributeOwnership({required String organizationId, required String assetId, required String amountUnits}) async {
    final response = await _request('/api/organizations/$organizationId/assets/$assetId/distributions', method: 'POST', body: {
      'amountUnits': amountUnits,
      'correlationId': newClientCorrelationId('DISTRIBUTE-OWNERSHIP'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listOrganizationContracts({required String organizationId}) async {
    final response = await _request('/api/organizations/$organizationId/contracts');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createOrganizationContract({required String organizationId, required String counterpartyOrganizationId, required String templateId, required Map<String, dynamic> terms, required int startGameDay, required int endGameDay, required String amountPerPeriod, required int periodDays}) async {
    final response = await _request('/api/organizations/$organizationId/contracts', method: 'POST', body: {
      'counterpartyOrganizationId': counterpartyOrganizationId,
      'templateId': templateId,
      'terms': terms,
      'startGameDay': startGameDay,
      'endGameDay': endGameDay,
      'amountPerPeriod': amountPerPeriod,
      'periodDays': periodDays,
      'correlationId': newClientCorrelationId('CREATE-CONTRACT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> signOrganizationContract({required String organizationId, required String contractId}) async {
    final response = await _request('/api/organizations/$organizationId/contracts/$contractId/sign', method: 'POST', body: {'correlationId': newClientCorrelationId('SIGN-CONTRACT')});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listPublicProjects() async {
    final response = await _request('/api/public-projects');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> contributeToPublicProject({required String projectId, required String sourceAccountId, required String amountUnits}) async {
    final response = await _request('/api/public-projects/$projectId/contributions', method: 'POST', body: {
      'sourceAccountId': sourceAccountId,
      'amountUnits': amountUnits,
      'correlationId': newClientCorrelationId('CONTRIBUTE-PUBLIC-PROJECT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> organizationFinancialRisk(String organizationId) async {
    final response = await _request('/api/finance/organizations/$organizationId/risk');
    return Map<String, dynamic>.from(response as Map);
  }
}
