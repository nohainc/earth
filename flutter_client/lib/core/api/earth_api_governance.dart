part of 'earth_api.dart';

extension EarthApiGovernance on EarthApi {
  Future<Map<String, dynamic>> getV5Constitution({String? corporationId}) async {
    final suffix = corporationId == null ? '' : '?corporationId=${Uri.encodeQueryComponent(corporationId)}';
    final response = await _request('/api/governance/v5/constitution$suffix');
    return Map<String, dynamic>.from(response as Map);
  }
  Future<Map<String, dynamic>> listV5Proposals() async {
    final response = await _request('/api/governance/v5/proposals');
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'V5 proposals unavailable'};
  }

  Future<Map<String, dynamic>> proposeV5ConstitutionAmendment({
    required String subjectType,
    String? subjectId,
    required String title,
    required String body,
    required List<Map<String, dynamic>> changes,
    int? effectiveFromGameDay,
  }) async {
    final effectiveDay = effectiveFromGameDay ?? await _nextV5ConstitutionGameDay(subjectId);
    final response = await _request('/api/governance/v5/proposals', method: 'POST', body: {
      'subjectType': subjectType,
      'subjectId': subjectId,
      'actionType': 'CONSTITUTION_AMENDMENT',
      'payload': {'effectiveFromGameDay': effectiveDay, 'changes': changes},
      'title': title,
      'body': body,
      'correlationId': newClientCorrelationId('V5-CONSTITUTION-AMENDMENT'),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<int> _nextV5ConstitutionGameDay(String? corporationId) async {
    final current = await getV5Constitution(corporationId: corporationId);
    final gameDay = int.tryParse(current['gameDay']?.toString() ?? '') ?? 0;
    if (gameDay < 1) throw StateError('Canonical Constitution game day is unavailable');
    return gameDay + 1;
  }

  Future<Map<String, dynamic>> previewV5ConstitutionAmendment({
    String? corporationId,
    required List<Map<String, dynamic>> changes,
  }) async {
    final response = await _request('/api/governance/v5/constitution/preview', method: 'POST', body: {
      if (corporationId != null) 'corporationId': corporationId,
      'changes': changes,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> voteV5Proposal(
      String proposalId, String choice) async {
    final response = await _request(
        '/api/governance/v5/proposals/$proposalId/vote',
        method: 'POST',
        body: {
          'choice': choice,
          'correlationId': newClientCorrelationId('VOTE-GOV5'),
        });
    return response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> voteGovernanceV4(
      String proposalId, String choice) async {
    final response = await _request(
        '/api/governance/v4/proposals/$proposalId/vote',
        method: 'POST',
        body: {
          'choice': choice,
          'correlationId': newClientCorrelationId('VOTE-GOV4'),
        });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<EarthState> vote(String proposalId, String choice) async {
    await _request('/api/governance/proposals/$proposalId/vote',
        method: 'POST', body: {'vote': choice});
    return world();
  }

  Future<EarthState> createProposal(String title, String body,
      {String institutionId = 'OUC-001',
      String? targetCategory,
      double? targetRate,
      Map<String, dynamic>? targetValue}) async {
    await _request('/api/governance/proposals', method: 'POST', body: {
      'institutionId': institutionId,
      'title': title,
      'body': body,
      if (targetCategory != null && targetCategory.isNotEmpty)
        'target': {
          'category': targetCategory,
          'value': targetValue ??
              (targetRate != null ? {'rate': targetRate} : <String, dynamic>{}),
        },
      'correlationId': newClientCorrelationId('governance-proposal'),
    });
    return world();
  }
}
