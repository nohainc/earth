class InitiativeScope {
  final String type;
  final String? id;
  const InitiativeScope({required this.type, this.id});
  factory InitiativeScope.fromJson(dynamic value) {
    final map = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return InitiativeScope(type: map['type']?.toString() ?? 'EARTH', id: map['id']?.toString());
  }
}

class InitiativeCapabilities {
  final bool canContribute;
  final bool viewerHasSupport;
  final bool canManageFunding;
  final bool canSettle;
  const InitiativeCapabilities({required this.canContribute, required this.viewerHasSupport, required this.canManageFunding, required this.canSettle});
  factory InitiativeCapabilities.fromJson(dynamic value) {
    final map = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return InitiativeCapabilities(canContribute: map['canContribute'] == true, viewerHasSupport: map['viewerHasSupport'] == true, canManageFunding: map['canManageFunding'] == true, canSettle: map['canSettle'] == true);
  }
}

class InitiativeExecution {
  final String? model;
  final String? status;
  final String? progressModel;
  final int progressBps;
  final int? durationGameDays;
  final int? startedGameDay;
  final int? completedGameDay;
  final String? blockedReason;
  final Map<String, dynamic> requiredResources;
  const InitiativeExecution({this.model, this.status, this.progressModel, required this.progressBps, this.durationGameDays, this.startedGameDay, this.completedGameDay, this.blockedReason, this.requiredResources = const {}});
  factory InitiativeExecution.fromJson(dynamic value) {
    final map = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return InitiativeExecution(model: map['model']?.toString(), status: map['status']?.toString(), progressModel: map['progressModel']?.toString(), progressBps: int.tryParse('${map['progressBps'] ?? 0}') ?? 0, durationGameDays: int.tryParse('${map['durationGameDays']}'), startedGameDay: int.tryParse('${map['startedGameDay']}'), completedGameDay: int.tryParse('${map['completedGameDay']}'), blockedReason: map['blockedReason']?.toString(), requiredResources: map['requiredResources'] is Map ? Map<String, dynamic>.from(map['requiredResources'] as Map) : const {});
  }
}

class InitiativeReadModel {
  final String id;
  final InitiativeScope scope;
  final String type;
  final String name;
  final String description;
  final String status;
  final String fundingTargetUnits;
  final String communityContributionUnits;
  final String matchCommittedUnits;
  final String matchAppliedUnits;
  final String treasuryCommittedUnits;
  final int fundingProgressBps;
  final int supporterCount;
  final int? deadlineGameDay;
  final String houseContributionUnits;
  final dynamic outcomePreview;
  final InitiativeExecution execution;
  final InitiativeCapabilities capabilities;
  const InitiativeReadModel({required this.id, required this.scope, required this.type, required this.name, required this.description, required this.status, required this.fundingTargetUnits, required this.communityContributionUnits, required this.matchCommittedUnits, required this.matchAppliedUnits, required this.treasuryCommittedUnits, required this.fundingProgressBps, required this.supporterCount, this.deadlineGameDay, required this.houseContributionUnits, this.outcomePreview, required this.execution, required this.capabilities});
  factory InitiativeReadModel.fromJson(Map<String, dynamic> map) => InitiativeReadModel(id: map['id']?.toString() ?? '', scope: InitiativeScope.fromJson(map['scope']), type: map['type']?.toString() ?? 'PUBLIC_PROJECT', name: map['name']?.toString() ?? 'Initiative', description: map['description']?.toString() ?? '', status: map['status']?.toString() ?? 'UNKNOWN', fundingTargetUnits: map['fundingTargetUnits']?.toString() ?? '0', communityContributionUnits: map['communityContributionUnits']?.toString() ?? '0', matchCommittedUnits: map['matchCommittedUnits']?.toString() ?? '0', matchAppliedUnits: map['matchAppliedUnits']?.toString() ?? '0', treasuryCommittedUnits: map['treasuryCommittedUnits']?.toString() ?? '0', fundingProgressBps: int.tryParse('${map['fundingProgressBps'] ?? 0}') ?? 0, supporterCount: int.tryParse('${map['supporterCount'] ?? 0}') ?? 0, deadlineGameDay: int.tryParse('${map['deadlineGameDay']}'), houseContributionUnits: map['houseContributionUnits']?.toString() ?? '0', outcomePreview: map['outcomePreview'], execution: InitiativeExecution.fromJson(map['execution']), capabilities: InitiativeCapabilities.fromJson(map['capabilities']));
}

class InitiativeSummary {
  final int activeCount;
  final int fundingCount;
  final int completedCount;
  final String communityCapitalUnits;
  final int supportingInitiativesCount;
  const InitiativeSummary({required this.activeCount, required this.fundingCount, required this.completedCount, required this.communityCapitalUnits, required this.supportingInitiativesCount});
  factory InitiativeSummary.fromJson(dynamic value) { final map = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{}; return InitiativeSummary(activeCount: int.tryParse('${map['activeCount'] ?? 0}') ?? 0, fundingCount: int.tryParse('${map['fundingCount'] ?? 0}') ?? 0, completedCount: int.tryParse('${map['completedCount'] ?? 0}') ?? 0, communityCapitalUnits: map['communityCapitalUnits']?.toString() ?? '0', supportingInitiativesCount: int.tryParse('${map['supportingInitiativesCount'] ?? 0}') ?? 0); }
}

class InitiativesReadModel {
  final List<InitiativeReadModel> initiatives;
  final InitiativeSummary summary;
  const InitiativesReadModel({required this.initiatives, required this.summary});
  factory InitiativesReadModel.fromJson(Map<String, dynamic> map) => InitiativesReadModel(initiatives: (map['initiatives'] is List ? (map['initiatives'] as List) : const []).whereType<Map>().map((row) => InitiativeReadModel.fromJson(Map<String, dynamic>.from(row))).toList(), summary: InitiativeSummary.fromJson(map['summary']));
}

class InitiativeContributionQuote {
  final String initiativeId;
  final String initiativeName;
  final String walletBeforeUnits;
  final String walletAfterUnits;
  final String contributionUnits;
  final String projectedMatchingUnits;
  final String remainingFundingRequirementUnits;
  final int? deadlineGameDay;
  const InitiativeContributionQuote({required this.initiativeId, required this.initiativeName, required this.walletBeforeUnits, required this.walletAfterUnits, required this.contributionUnits, required this.projectedMatchingUnits, required this.remainingFundingRequirementUnits, this.deadlineGameDay});
  factory InitiativeContributionQuote.fromJson(Map<String, dynamic> map) => InitiativeContributionQuote(initiativeId: map['initiativeId']?.toString() ?? '', initiativeName: map['initiativeName']?.toString() ?? 'Initiative', walletBeforeUnits: map['walletBeforeUnits']?.toString() ?? '0', walletAfterUnits: map['walletAfterUnits']?.toString() ?? '0', contributionUnits: map['contributionUnits']?.toString() ?? '0', projectedMatchingUnits: map['projectedMatchingUnits']?.toString() ?? '0', remainingFundingRequirementUnits: map['remainingFundingRequirementUnits']?.toString() ?? '0', deadlineGameDay: int.tryParse('${map['deadlineGameDay']}'));
}
