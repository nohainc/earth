class GovernanceProposal {
  final String id;
  final String title;
  final String? body;
  final String subjectType;
  final String? subjectId;
  final String subjectName;
  final String actionType;
  final String category;
  final Map<String, dynamic> payload;
  final String? impactSummary;
  final Map<String, dynamic>? impact;
  final String status;
  final int submittedGameDay;
  final int votingStartGameDay;
  final int votingEndGameDay;
  final int effectiveGameDay;
  final int? executedGameDay;
  final bool? quorumMet;
  final int electorateSize;
  final int quorumBps;
  final int quorumRequired;
  final int approvalBps;
  final int support;
  final int oppose;
  final int abstain;
  final int uncast;
  final int participationBps;
  final int decisiveApprovalBps;
  final bool eligible;
  final bool canVote;
  final bool voted;
  final String? choice;
  final String? rulesVersion;
  final int votingPeriodDays;
  final int implementationDelayDays;

  const GovernanceProposal({
    required this.id,
    required this.title,
    required this.body,
    required this.subjectType,
    required this.subjectId,
    required this.subjectName,
    required this.actionType,
    required this.category,
    required this.payload,
    required this.impactSummary,
    required this.impact,
    required this.status,
    required this.submittedGameDay,
    required this.votingStartGameDay,
    required this.votingEndGameDay,
    required this.effectiveGameDay,
    required this.executedGameDay,
    required this.quorumMet,
    required this.electorateSize,
    required this.quorumBps,
    required this.quorumRequired,
    required this.approvalBps,
    required this.support,
    required this.oppose,
    required this.abstain,
    required this.uncast,
    required this.participationBps,
    required this.decisiveApprovalBps,
    required this.eligible,
    required this.canVote,
    required this.voted,
    required this.choice,
    required this.rulesVersion,
    required this.votingPeriodDays,
    required this.implementationDelayDays,
  });

  static int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  factory GovernanceProposal.fromJson(Map<String, dynamic> json) {
    final identity = _map(json['identity']);
    final scope = _map(json['scope']);
    final action = _map(json['action']);
    final status = _map(json['status']);
    final electorate = _map(json['electorate']);
    final votes = _map(json['votes']);
    final viewer = _map(json['viewer']);
    final policy = _map(json['governancePolicy']);
    return GovernanceProposal(
      id: identity['id']?.toString() ?? '',
      title: identity['title']?.toString() ?? 'V5 governance proposal',
      body: identity['body']?.toString(),
      subjectType: scope['subjectType']?.toString() ?? 'EARTH',
      subjectId: scope['subjectId']?.toString(),
      subjectName: scope['subjectName']?.toString() ?? 'EARTH',
      actionType: action['actionType']?.toString() ?? 'UNKNOWN',
      category: action['category']?.toString() ?? 'POLICY',
      payload: _map(action['payload']),
      impactSummary: action['impactSummary']?.toString(),
      impact: action['impact'] is Map
          ? Map<String, dynamic>.from(action['impact'] as Map)
          : null,
      status: status['status']?.toString() ?? 'VOTING',
      submittedGameDay: _int(status['submittedGameDay']),
      votingStartGameDay: _int(status['votingStartGameDay']),
      votingEndGameDay: _int(status['votingEndGameDay']),
      effectiveGameDay: _int(status['effectiveGameDay']),
      executedGameDay: status['executedGameDay'] == null
          ? null
          : _int(status['executedGameDay']),
      quorumMet:
          status['quorumMet'] == null ? null : status['quorumMet'] == true,
      electorateSize: _int(electorate['electorateSize']),
      quorumBps: _int(electorate['quorumBps']),
      quorumRequired: _int(electorate['quorumRequired']),
      approvalBps: _int(electorate['approvalBps']),
      support: _int(votes['support']),
      oppose: _int(votes['oppose']),
      abstain: _int(votes['abstain']),
      uncast: _int(votes['uncast']),
      participationBps: _int(votes['participationBps']),
      decisiveApprovalBps: _int(votes['decisiveApprovalBps']),
      eligible: viewer['eligible'] == true,
      canVote: viewer['canVote'] == true,
      voted: viewer['voted'] == true,
      choice: viewer['choice']?.toString(),
      rulesVersion: policy['rulesVersion']?.toString(),
      votingPeriodDays: _int(policy['votingPeriodDays']),
      implementationDelayDays: _int(policy['implementationDelayDays']),
    );
  }

  Map<String, dynamic> toCardMap() {
    final normalizedStatus = status.toUpperCase();
    final outcome = switch (normalizedStatus) {
      'PASSED' => 'passed',
      'REJECTED' || 'STALE' || 'CANCELLED' => 'rejected',
      'FAILED' => 'failed',
      _ => 'pending',
    };
    return {
      'id': id,
      'title': title,
      'body': body ?? '',
      'scope': subjectType,
      'institution_id': subjectId,
      'submitted_game_day': submittedGameDay,
      'status': status == 'VOTING' ? 'OPEN' : status,
      'voting_start_game_day': votingStartGameDay,
      'voting_end_game_day': votingEndGameDay,
      'closes_game_day': votingEndGameDay,
      'effective_from_game_day': effectiveGameDay,
      'executed_game_day': executedGameDay,
      'impact_summary': impactSummary,
      'impact': impact,
      'votes': {
        'support': support,
        'oppose': oppose,
        'abstain': abstain,
        'uncast': uncast,
        'participation_bps': participationBps,
        'decisive_approval_bps': decisiveApprovalBps
      },
      'my_vote': choice,
      'eligible_voter_count': electorateSize,
      'quorum_bps': quorumBps,
      'approval_bps': approvalBps,
      'quorum_met': quorumMet,
      'viewer': {
        'canVote': canVote,
        'eligible': eligible,
        'voted': voted,
        'ineligibleReason':
            eligible ? null : 'Not in this proposal\'s frozen electorate.'
      },
      'outcome': outcome,
      'execution_status':
          normalizedStatus == 'EXECUTED' || normalizedStatus == 'ACTIVATED'
              ? 'executed'
              : null,
      'quorum_required': quorumRequired,
      'action_type': actionType,
      'payload': payload,
    };
  }
}
