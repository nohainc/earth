class HouseOnboardingMilestone {
  final String code;
  final String title;
  final String description;

  const HouseOnboardingMilestone({
    required this.code,
    required this.title,
    required this.description,
  });

  factory HouseOnboardingMilestone.fromJson(Map<String, dynamic> json) =>
      HouseOnboardingMilestone(
        code: '${json['code'] ?? ''}',
        title: '${json['title'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

class HouseOnboardingState {
  final String status;
  final String version;
  final int currentGameDay;
  final Set<String> completedMilestones;
  final List<HouseOnboardingMilestone> milestones;
  final HouseOnboardingMilestone? recommendedNext;

  const HouseOnboardingState({
    required this.status,
    required this.version,
    required this.currentGameDay,
    required this.completedMilestones,
    required this.milestones,
    required this.recommendedNext,
  });

  factory HouseOnboardingState.fromJson(Map<String, dynamic> json) {
    final rawCompleted = json['completedMilestones'] is List
        ? (json['completedMilestones'] as List)
            .map((value) => value.toString())
            .toSet()
        : <String>{};
    final rawMilestones = json['milestones'] is List
        ? (json['milestones'] as List)
            .whereType<Map>()
            .map((value) => HouseOnboardingMilestone.fromJson(
                Map<String, dynamic>.from(value)))
            .toList()
        : <HouseOnboardingMilestone>[];
    final rawNext = json['recommendedNext'];
    return HouseOnboardingState(
      status: '${json['status'] ?? 'ACTIVE'}',
      version: '${json['version'] ?? 'onboarding-v4-1'}',
      currentGameDay: int.tryParse('${json['currentGameDay'] ?? 1}') ?? 1,
      completedMilestones: rawCompleted,
      milestones: rawMilestones,
      recommendedNext: rawNext is Map
          ? HouseOnboardingMilestone.fromJson(Map<String, dynamic>.from(rawNext))
          : null,
    );
  }
}
