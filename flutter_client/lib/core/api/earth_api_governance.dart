part of 'earth_api.dart';

extension EarthApiGovernance on EarthApi {
  Future<EarthState> vote(String proposalId, String choice) async {
    await _request('/api/governance/proposals/$proposalId/vote',
        method: 'POST', body: {'vote': choice});
    return world();
  }

  Future<EarthState> createProposal(String title, String body,
      {String? targetCategory, double? targetRate}) async {
    await _request('/api/governance/proposals', method: 'POST', body: {
      'institutionId': 'OUC-001',
      'title': title,
      'body': body,
      'durationHours': 72,
      if (targetCategory != null && targetCategory.isNotEmpty)
        'target': {
          'category': targetCategory,
          if (targetRate != null) 'value': {'rate': targetRate},
        },
      'correlationId':
          'governance-proposal-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> claimRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/claim', method: 'POST');
    return world();
  }

  Future<EarthState> resignRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/resign', method: 'POST');
    return world();
  }

  Future<EarthState> delegateRole(String roleId, String delegateHumanId) async {
    await _request('/api/governance/roles/$roleId/delegate',
        method: 'POST', body: {'delegateHumanId': delegateHumanId.trim()});
    return world();
  }

  Future<EarthState> recallRole(String roleId) async {
    await _request('/api/governance/roles/$roleId/recall', method: 'POST');
    return world();
  }

}
