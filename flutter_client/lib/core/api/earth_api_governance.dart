part of 'earth_api.dart';

extension EarthApiGovernance on EarthApi {
  Future<EarthState> vote(String proposalId, String choice) async {
    await _request('/api/governance/proposals/$proposalId/vote',
        method: 'POST', body: {'vote': choice});
    return world();
  }

  Future<EarthState> createProposal(String title, String body,
      {String institutionId = 'OUC-001', String? targetCategory, double? targetRate, Map<String, dynamic>? targetValue}) async {
    await _request('/api/governance/proposals', method: 'POST', body: {
      'institutionId': institutionId,
      'title': title,
      'body': body,
      if (targetCategory != null && targetCategory.isNotEmpty)
        'target': {
          'category': targetCategory,
          'value': targetValue ?? (targetRate != null ? {'rate': targetRate} : <String, dynamic>{}),
        },
      'correlationId':
          newClientCorrelationId('governance-proposal'),
    });
    return world();
  }

  Future<EarthState> challengeProposal(String proposalId, String reason) async {
    await _request('/api/governance/proposals/$proposalId/challenge',
        method: 'POST',
        body: {
          'reason': reason.trim(),
          'correlationId':
              newClientCorrelationId('governance-challenge'),
        });
    return world();
  }

  Future<EarthState> resolveConstitutionalAppeal(
      String proposalId, String ruling, String rationale) async {
    await _request('/api/governance/proposals/$proposalId/appeal-ruling',
        method: 'POST',
        body: {
          'ruling': ruling,
          'rationale': rationale.trim(),
          'correlationId':
          newClientCorrelationId('governance-ruling'),
        });
    return world();
  }

  Future<EarthState> executeProposal(String proposalId) async {
    await _request('/api/governance/proposals/$proposalId/execute',
        method: 'POST');
    return world();
  }
}
