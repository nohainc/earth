part of 'earth_api.dart';

extension EarthApiOrganizations on EarthApi {
  Future<Map<String, dynamic>> listCharterTemplates() async {
    final response = await _request('/api/organizations/charters/templates');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listOrganizations({String? archetype}) async {
    final suffix = archetype == null
        ? ''
        : '?archetype=${Uri.encodeQueryComponent(archetype)}';
    final response = await _request('/api/organizations$suffix');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createOrganization({
    required String name,
    required String archetype,
    String joinPolicy = 'OPEN',
    List<String>? capabilities,
  }) async {
    final response =
        await _request('/api/organizations', method: 'POST', body: {
      'name': name,
      'archetype': archetype,
      'joinPolicy': joinPolicy,
      if (capabilities != null) 'capabilities': capabilities,
      'correlationId': newClientCorrelationId('CREATE-ORG'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> joinOrganization(
      {required String organizationId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/membership',
        method: 'POST',
        body: {
          'correlationId': newClientCorrelationId('JOIN-ORG'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationFinance(
      {required String organizationId}) async {
    final response =
        await _request('/api/organizations/$organizationId/finance');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationCharter(
      {required String organizationId, bool history = false}) async {
    final path = history
        ? '/api/organizations/$organizationId/charter/history'
        : '/api/organizations/$organizationId/charter';
    final response = await _request(path);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> validateOrganizationCharter(
      {required String organizationId,
      required Map<String, dynamic> charter}) async {
    final response = await _request(
        '/api/organizations/$organizationId/charter/validate',
        method: 'POST',
        body: {'charter': charter});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> amendOrganizationCharter(
      {required String organizationId,
      required Map<String, dynamic> charter}) async {
    throw StateError('Direct Charter amendment is retired; use a V5 Constitution amendment proposal.');
  }

  Future<Map<String, dynamic>> getOrganizationVotingMethod(
      {required String organizationId}) async {
    final response = await _request(
        '/api/governance/v4/organizations/$organizationId/method');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> setOrganizationVotingMethod(
      {required String organizationId,
      required String votingMethod,
      int voiceCycleDays = 7,
      int voicePerCycle = 100}) async {
    throw StateError('Direct voting-setting amendment is retired; use a V5 Constitution amendment proposal.');
  }

  Future<Map<String, dynamic>> listEarthPrograms() async {
    final response = await _request('/api/earth/programs');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createGlobalProgram({
    required String programType,
    required String name,
    required String description,
    required String targetUnits,
    required String authorizedUnits,
    String? matchingAuthorizedUnits,
    int? fundingDeadlineGameDay,
    required String proposalId,
  }) async {
    final response =
        await _request('/api/earth/programs', method: 'POST', body: {
      'programType': programType,
      'name': name,
      'description': description,
      'targetUnits': targetUnits,
      'authorizedUnits': authorizedUnits,
      if (matchingAuthorizedUnits != null)
        'matchingAuthorizedUnits': matchingAuthorizedUnits,
      if (fundingDeadlineGameDay != null)
        'fundingDeadlineGameDay': fundingDeadlineGameDay,
      'proposalId': proposalId,
      'correlationId': newClientCorrelationId('CREATE-EARTH-PROGRAM'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listEarthTechnologyGenerations() async {
    final response = await _request('/api/earth/technology/generations');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getOrganizationAuthority(
      {required String organizationId}) async {
    final response =
        await _request('/api/organizations/$organizationId/authority');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> appointOrganizationOffice(
      {required String organizationId,
      required String officeCode,
      required String targetHumanId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/offices/$officeCode/appoint',
        method: 'POST',
        body: {
          'targetHumanId': targetHumanId,
          'correlationId': newClientCorrelationId('APPOINT-OFFICE'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> resignOrganizationOffice(
      {required String organizationId, required String officeCode}) async {
    final response = await _request(
        '/api/organizations/$organizationId/offices/$officeCode/resign',
        method: 'POST',
        body: {
          'correlationId': newClientCorrelationId('RESIGN-OFFICE'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getAssetOwnership(
      {required String organizationId, required String assetId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/assets/$assetId/ownership');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> subscribeToAssetOwnership(
      {required String organizationId,
      required String assetId,
      required String units,
      required String priceUnits,
      required String sourceAccountId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/assets/$assetId/ownership',
        method: 'POST',
        body: {
          'units': units,
          'priceUnits': priceUnits,
          'sourceAccountId': sourceAccountId,
          'investorType': 'HOUSE',
          'correlationId': newClientCorrelationId('SUBSCRIBE-OWNERSHIP'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> distributeOwnership(
      {required String organizationId,
      required String assetId,
      required String amountUnits}) async {
    final response = await _request(
        '/api/organizations/$organizationId/assets/$assetId/distributions',
        method: 'POST',
        body: {
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('DISTRIBUTE-OWNERSHIP'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listOrganizationContracts(
      {required String organizationId}) async {
    final response =
        await _request('/api/organizations/$organizationId/contracts');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createOrganizationContract(
      {required String organizationId,
      required String counterpartyOrganizationId,
      required String templateId,
      required Map<String, dynamic> terms,
      required int startGameDay,
      required int endGameDay,
      required String amountPerPeriod,
      required int periodDays}) async {
    final response = await _request(
        '/api/organizations/$organizationId/contracts',
        method: 'POST',
        body: {
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

  Future<Map<String, dynamic>> signOrganizationContract(
      {required String organizationId, required String contractId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/contracts/$contractId/sign',
        method: 'POST',
        body: {'correlationId': newClientCorrelationId('SIGN-CONTRACT')});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listContractPerformance(String organizationId) async {
    final response = await _request('/api/organizations/$organizationId/contracts/performance');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> contractPerformanceAction({required String organizationId, required String performanceId, required String action, String? note, String? units, int? qualityBps, String? resolution}) async {
    final response = await _request('/api/organizations/$organizationId/contracts/performance/$performanceId/$action', method: 'POST', body: {
      if (note != null) 'note': note,
      if (units != null) 'units': units,
      if (qualityBps != null) 'qualityBps': qualityBps,
      if (resolution != null) 'resolution': resolution,
      'correlationId': newClientCorrelationId('CONTRACT-PERFORMANCE'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listPublicProjects() async {
    final response = await _request('/api/public-projects');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createPublicProject({
    required String name,
    required String description,
    required String beneficiaryType,
    required String beneficiaryId,
    required String recipientAccountId,
    required String targetUnits,
    required int deadlineGameDay,
    required String matchingPoolAuthorizedUnits,
    required String proposalId,
  }) async {
    final response =
        await _request('/api/public-projects', method: 'POST', body: {
      'name': name,
      'description': description,
      'beneficiaryType': beneficiaryType,
      'beneficiaryId': beneficiaryId,
      'recipientAccountId': recipientAccountId,
      'targetUnits': targetUnits,
      'deadlineGameDay': deadlineGameDay,
      'matchingPoolAuthorizedUnits': matchingPoolAuthorizedUnits,
      'proposalId': proposalId,
      'correlationId': newClientCorrelationId('CREATE-PUBLIC-PROJECT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> fundPublicProjectMatchingPool({
    required String projectId,
    required String proposalId,
    required String amountUnits,
  }) async {
    final response = await _request(
        '/api/public-projects/$projectId/matching-fund',
        method: 'POST',
        body: {
          'proposalId': proposalId,
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('FUND-MATCHING-POOL'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> contributeToPublicProject(
      {required String projectId,
      required String sourceAccountId,
      required String amountUnits}) async {
    final response = await _request(
        '/api/public-projects/$projectId/contributions',
        method: 'POST',
        body: {
          'sourceAccountId': sourceAccountId,
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('CONTRIBUTE-PUBLIC-PROJECT'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getPublicProject(String projectId) async {
    final response = await _request('/api/public-projects/$projectId');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> settlePublicProject(String projectId) async {
    final response = await _request('/api/public-projects/$projectId/settle',
        method: 'POST',
        body: {
          'correlationId': newClientCorrelationId('SETTLE-PUBLIC-PROJECT'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> fundGlobalProgram(
      {required String programId,
      required String proposalId,
      required String sourceAccountId,
      required String destinationAccountId,
      required String amountUnits}) async {
    final response = await _request('/api/earth/programs/$programId/fund',
        method: 'POST',
        body: {
          'proposalId': proposalId,
          'sourceAccountId': sourceAccountId,
          'destinationAccountId': destinationAccountId,
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('FUND-EARTH-PROGRAM'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> contributeToGlobalProgram(
      {required String programId,
      required String sourceAccountId,
      required String amountUnits}) async {
    final response = await _request(
        '/api/earth/programs/$programId/contributions',
        method: 'POST',
        body: {
          'sourceAccountId': sourceAccountId,
          'amountUnits': amountUnits,
          'correlationId': newClientCorrelationId('CONTRIBUTE-EARTH-PROGRAM'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> organizationFinancialRisk(
      String organizationId) async {
    final response =
        await _request('/api/finance/organizations/$organizationId/risk');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createOrganizationResolution({
    required String organizationId,
    required String caseType,
    required String proposalId,
    String? successorOrganizationId,
  }) async {
    final response = await _request(
        '/api/finance/organizations/$organizationId/resolution',
        method: 'POST',
        body: {
          'caseType': caseType,
          'proposalId': proposalId,
          if (successorOrganizationId != null &&
              successorOrganizationId.isNotEmpty)
            'successorOrganizationId': successorOrganizationId,
          'correlationId': newClientCorrelationId('ORG-RESOLUTION'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listOrganizationTechnologyAdoptions(
      String organizationId) async {
    final response = await _request(
        '/api/organizations/$organizationId/technology-adoptions');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adoptTechnologyGeneration(
      {required String organizationId,
      required String generationId,
      required String proposalId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/technology-adoptions',
        method: 'POST',
        body: {
          'generationId': generationId,
          'proposalId': proposalId,
          'correlationId': newClientCorrelationId('ORG-TECH-ADOPTION'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> proposeTechnologyAdoption(
      {required String organizationId, required String generationId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/technology-adoptions/propose',
        method: 'POST',
        body: {
          'generationId': generationId,
          'correlationId': newClientCorrelationId('PROPOSE-ORG-TECH'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> retireTechnologyAdoption(
      {required String organizationId, required String adoptionId}) async {
    final response = await _request(
        '/api/organizations/$organizationId/technology-adoptions/$adoptionId/retire',
        method: 'POST',
        body: {
          'correlationId': newClientCorrelationId('RETIRE-ORG-TECH'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listGlobalProgramContributions(
      String programId) async {
    final response =
        await _request('/api/earth/programs/$programId/contributions');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> settleGlobalProgram(String programId) async {
    final response =
        await _request('/api/earth/programs/$programId/settle', method: 'POST');
    return Map<String, dynamic>.from(response as Map);
  }
}
