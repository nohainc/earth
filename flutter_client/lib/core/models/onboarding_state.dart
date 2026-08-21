import 'package:flutter/material.dart';

class OnboardingStep {
  final int index;
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String actionLabel;
  final String targetSection;
  final IconData icon;

  const OnboardingStep({
    required this.index,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.actionLabel,
    required this.targetSection,
    required this.icon,
  });

  static const List<OnboardingStep> steps = [
    OnboardingStep(
      index: 0,
      id: 'world_status',
      title: 'READ WORLD STATUS',
      subtitle: 'Cosmic Clock & Unified Currency',
      description: 'Observe the planetary clock (1s = 1m in World time) and the Credits (CR) monetary standard that powers the United Corporations federation.',
      actionLabel: 'INSPECT WORLD METRICS',
      targetSection: 'command',
      icon: Icons.public_outlined,
    ),
    OnboardingStep(
      index: 1,
      id: 'personal_resources',
      title: 'REVIEW PERSONAL RESOURCES',
      subtitle: 'Energy, Materials, Compute & Food',
      description: 'Check your liquid Credits and 4 fundamental commodity balances required for daily metabolic survival and industrial operations.',
      actionLabel: 'VIEW ASSET PORTFOLIO',
      targetSection: 'net_worth',
      icon: Icons.account_balance_wallet_outlined,
    ),
    OnboardingStep(
      index: 2,
      id: 'join_community',
      title: 'JOIN OR INSPECT A COMMUNITY',
      subtitle: 'Municipal Charters & Civic Residency',
      description: 'Explore the 4 sovereign city-states (New Geneva, Neo Kyoto, Valparaíso, Aethelgard) and inspect municipal tax charters and capacity pressures.',
      actionLabel: 'VISIT CITY-STATE CIVIC',
      targetSection: 'city',
      icon: Icons.location_city_outlined,
    ),
    OnboardingStep(
      index: 3,
      id: 'first_market_decision',
      title: 'MAKE FIRST MARKET DECISION',
      subtitle: 'Periodic Batch Auctions (P*)',
      description: 'Review live supply & demand clearing prices, orderbooks, and submit your inaugural spot auction trade with zero slippage.',
      actionLabel: 'EXPLORE COMMODITY MARKET',
      targetSection: 'market',
      icon: Icons.swap_horiz,
    ),
    OnboardingStep(
      index: 4,
      id: 'start_enterprise',
      title: 'START BUSINESS OR RESEARCH',
      subtitle: 'Corporate Creation & Technological Mastery',
      description: 'Incorporate a commercial enterprise, deploy automated machines, or allocate compute nodes to pioneer next-generation technologies.',
      actionLabel: 'OPEN ENTERPRISE REGISTRY',
      targetSection: 'business',
      icon: Icons.storefront_outlined,
    ),
    OnboardingStep(
      index: 5,
      id: 'receive_consequence',
      title: 'RECEIVE WORLD SIGNAL',
      subtitle: 'Live Outbox & Sub-Space Dispatch',
      description: 'Review your personal activity stream and sub-space comm-link to verify the consequences of your economic actions and claim your civic stipend.',
      actionLabel: 'CHECK ACTIVITY & DISPATCH',
      targetSection: 'activity',
      icon: Icons.notifications_active_outlined,
    ),
  ];
}

class OnboardingProgress {
  final int currentStepIndex;
  final Set<String> completedStepIds;
  final bool isDismissed;
  final bool isCompleted;

  const OnboardingProgress({
    this.currentStepIndex = 0,
    this.completedStepIds = const {},
    this.isDismissed = false,
    this.isCompleted = false,
  });

  OnboardingProgress copyWith({
    int? currentStepIndex,
    Set<String>? completedStepIds,
    bool? isDismissed,
    bool? isCompleted,
  }) {
    return OnboardingProgress(
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      completedStepIds: completedStepIds ?? this.completedStepIds,
      isDismissed: isDismissed ?? this.isDismissed,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'currentStepIndex': currentStepIndex,
        'completedStepIds': completedStepIds.toList(),
        'isDismissed': isDismissed,
        'isCompleted': isCompleted,
      };

  factory OnboardingProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OnboardingProgress();
    final rawCompleted = json['completedStepIds'] as List<dynamic>? ?? [];
    return OnboardingProgress(
      currentStepIndex: json['currentStepIndex'] as int? ?? 0,
      completedStepIds: rawCompleted.map((e) => e.toString()).toSet(),
      isDismissed: json['isDismissed'] as bool? ?? false,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }
}
