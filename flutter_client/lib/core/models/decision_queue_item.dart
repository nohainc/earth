import 'package:flutter/material.dart';
import '../../shared/widgets/format_helpers.dart';

class DecisionQueueItem {
  final String id;
  final String category;
  final String title;
  final String whyItMatters;
  final String deadline;
  final String expectedImpact;
  final String riskLevel; // 'critical', 'high', 'medium', 'low'
  final String primaryActionLabel;
  final String targetRoute;
  final String? targetEntityId;
  final bool viewerCanAct;
  final double urgencyScore;
  final Map<String, dynamic> metadata;

  const DecisionQueueItem({
    required this.id,
    required this.category,
    required this.title,
    required this.whyItMatters,
    required this.deadline,
    required this.expectedImpact,
    required this.riskLevel,
    required this.primaryActionLabel,
    required this.targetRoute,
    this.targetEntityId,
    this.viewerCanAct = true,
    this.urgencyScore = 50.0,
    this.metadata = const {},
  });

  Color get riskColor {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'high':
        return const Color(0xFFF59E0B);
      case 'medium':
        return const Color(0xFF818CF8);
      case 'low':
      default:
        return const Color(0xFF10B981);
    }
  }

  /// Player-facing urgency vocabulary. The numeric priority remains internal
  /// and is never presented as a speculative risk assessment.
  String get actionStatus {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return 'CRITICAL';
      case 'high':
        return 'ACTION REQUIRED';
      case 'medium':
        return 'ATTENTION';
      case 'low':
      default:
        return 'OPPORTUNITY';
    }
  }

  Color get actionStatusColor {
    switch (actionStatus) {
      case 'CRITICAL':
        return const Color(0xFFEF4444);
      case 'ACTION REQUIRED':
        return const Color(0xFFF59E0B);
      case 'ATTENTION':
        return const Color(0xFF818CF8);
      default:
        return const Color(0xFF10B981);
    }
  }

  IconData get categoryIcon {
    switch (category.toLowerCase()) {
      case 'governance':
      case 'civic':
        return Icons.how_to_vote_outlined;
      case 'technology':
        return Icons.biotech_outlined;
      case 'house':
        return Icons.home_work_outlined;
      case 'market':
        return Icons.storefront_outlined;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'whyItMatters': whyItMatters,
        'deadline': deadline,
        'expectedImpact': expectedImpact,
        'riskLevel': riskLevel,
        'primaryActionLabel': primaryActionLabel,
        'targetRoute': targetRoute,
        if (targetEntityId != null) 'targetEntityId': targetEntityId,
        'viewerCanAct': viewerCanAct,
        'urgencyScore': urgencyScore,
        'metadata': metadata,
      };

  factory DecisionQueueItem.fromJson(Map<String, dynamic> json) {
    const validRoutes = {
      'market', 'buildings', 'finance', 'technology', 'civic', 'governance',
      'house', 'life', 'citizen', 'corporation',
    };
    final requestedRoute = json['targetRoute']?.toString() ?? '';
    return DecisionQueueItem(
        id: json['id']?.toString() ?? 'decision-generic',
        category: json['category']?.toString() ?? 'house',
        title: json['title']?.toString() ?? 'Pending Decision',
        whyItMatters: json['whyItMatters']?.toString() ??
            'Action is required to maintain operational stability.',
        deadline: json['deadline']?.toString() ?? 'Next Tick',
        expectedImpact: json['expectedImpact']?.toString() ??
            'Maintain continuous operations.',
        riskLevel: json['riskLevel']?.toString() ?? 'medium',
        primaryActionLabel:
            json['primaryActionLabel']?.toString() ?? 'Take Action',
        targetRoute: validRoutes.contains(requestedRoute) ? requestedRoute : 'house',
        targetEntityId: json['targetEntityId']?.toString(),
        viewerCanAct: json['viewerCanAct'] != false,
        urgencyScore: asDoubleOr(json['urgencyScore'], 50.0),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );
  }

}
