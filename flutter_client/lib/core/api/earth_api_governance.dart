part of 'earth_api.dart';

extension EarthApiGovernance on EarthApi {
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
