import 'package:flutter/material.dart';
import '../../shared/widgets/format_helpers.dart';
import 'earth_state.dart';

class DecisionQueueItem {
  final String id;
  final String category;
  final String title;
  final String whyItMatters;
  final String deadline;
  final String expectedImpact;
  final String riskLevel; // 'critical', 'high', 'medium', 'low'
  final String primaryActionLabel;
  final String targetSection;
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
    required this.targetSection,
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

  String get riskLabel {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return 'CRITICAL RISK';
      case 'high':
        return 'HIGH RISK';
      case 'medium':
        return 'MEDIUM RISK';
      case 'low':
      default:
        return 'LOW RISK';
    }
  }

  IconData get categoryIcon {
    switch (category.toLowerCase()) {
      case 'business':
        return Icons.business_center_outlined;
      case 'contracts':
        return Icons.description_outlined;
      case 'governance':
      case 'civic':
        return Icons.how_to_vote_outlined;
      case 'technology':
        return Icons.biotech_outlined;
      case 'machines':
        return Icons.precision_manufacturing_outlined;
      case 'dynasty':
        return Icons.account_balance_outlined;
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
        'targetSection': targetSection,
        'urgencyScore': urgencyScore,
        'metadata': metadata,
      };

  factory DecisionQueueItem.fromJson(Map<String, dynamic> json) =>
      DecisionQueueItem(
        id: json['id']?.toString() ?? 'decision-generic',
        category: json['category']?.toString() ?? 'business',
        title: json['title']?.toString() ?? 'Pending Decision',
        whyItMatters: json['whyItMatters']?.toString() ??
            'Action is required to maintain operational stability.',
        deadline: json['deadline']?.toString() ?? 'Next Tick',
        expectedImpact: json['expectedImpact']?.toString() ??
            'Maintain continuous operations.',
        riskLevel: json['riskLevel']?.toString() ?? 'medium',
        primaryActionLabel:
            json['primaryActionLabel']?.toString() ?? 'Take Action',
        targetSection: json['targetSection']?.toString() ?? 'command',
        urgencyScore: asDoubleOr(json['urgencyScore'], 50.0),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );

  /// Synthesizes complete DecisionQueue from EarthState when backend
  /// provides partial or raw state data.
  static List<DecisionQueueItem> synthesizeFromState(EarthState state) {
    final raw = state.json['decisionQueue'] as List<dynamic>?;
    if (raw != null && raw.isNotEmpty) {
      return raw
          .map((item) =>
              DecisionQueueItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
    }

    final items = <DecisionQueueItem>[];

    // 1. Corporation energy & resource deficit
    final rawResources = state.json['resources'];
    final resources = rawResources is Map ? rawResources : const {};
    final energy = asDoubleOr(resources['energy'], 100.0);
    final materials = asDoubleOr(
        resources['material'] ?? resources['materials'], 100.0);
    final rawBusiness = state.json['business'];
    final business = rawBusiness is Map ? rawBusiness : const {};
    final profit = asDoubleOr(business['profit'], 0.0);

    if (energy <= 50) {
      items.add(DecisionQueueItem(
        id: 'decision-corp-energy-deficit',
        category: 'business',
        title: 'Your corporation is losing energy',
        whyItMatters:
            'Energy reserves are dangerously depleted; factory operations and machinery will freeze if energy drops to zero.',
        deadline: energy <= 20 ? 'Immediate (Next Tick)' : 'Next Game Day',
        expectedImpact:
            'Prevent emergency production blackout and avoid idle capacity penalties.',
        riskLevel: energy <= 20 ? 'critical' : 'high',
        primaryActionLabel: 'Procure Energy',
        targetSection: 'market',
        urgencyScore: 100.0 - energy,
      ));
    } else if (materials < 25) {
      items.add(const DecisionQueueItem(
        id: 'decision-corp-material-deficit',
        category: 'business',
        title: 'Production materials running low',
        whyItMatters:
            'Manufacturing lines cannot fulfill output quotas without raw components and materials.',
        deadline: 'In 1 Game Day',
        expectedImpact:
            'Keep industrial assembly lines running at 100% capacity.',
        riskLevel: 'high',
        primaryActionLabel: 'Buy Materials',
        targetSection: 'market',
        urgencyScore: 75.0,
      ));
    } else if (profit < 0) {
      items.add(const DecisionQueueItem(
        id: 'decision-corp-negative-cashflow',
        category: 'business',
        title: 'Corporation is operating at a net loss',
        whyItMatters:
            'Operating expenses exceed daily revenues, eroding working capital.',
        deadline: 'End of Fiscal Cycle',
        expectedImpact:
            'Adjust production pricing and policy to restore positive operating margins.',
        riskLevel: 'high',
        primaryActionLabel: 'Review Financials',
        targetSection: 'business',
        urgencyScore: 70.0,
      ));
    }

    // 2. Contracts expiring
    final rawContracts = state.json['contracts'];
    final contracts = rawContracts is List ? rawContracts : const [];
    if (contracts.isNotEmpty) {
      final active = contracts
          .where((c) =>
              c is Map &&
              (c['status'] == 'active' ||
                  c['status'] == 'pending' ||
                  c['status'] == 'open'))
          .toList();
      if (active.isNotEmpty) {
        final c = Map<String, dynamic>.from(active.first as Map);
        items.add(DecisionQueueItem(
          id: 'decision-contract-expiry-${c['id'] ?? 'c1'}',
          category: 'contracts',
          title: 'A contract expires in 2 days',
          whyItMatters:
              'Unfulfilled supply obligations risk forfeiture of escrow collateral and damage commercial reliability standing.',
          deadline: 'In 2 Game Days',
          expectedImpact:
              'Fulfill shipment to unlock full credit payout and improve corporate credit score.',
          riskLevel: 'high',
          primaryActionLabel: 'Review Contract',
          targetSection: 'contracts',
          urgencyScore: 85.0,
        ));
      }
    }

    // 3. Unresolved governance votes
    final rawGov = state.json['governance'];
    final governance = rawGov is Map ? rawGov : const {};
    final proposals = (governance['proposals'] as List<dynamic>?) ?? const [];
    final openProps = proposals
        .where((p) => p is Map && (p['status'] == 'open' || p['status'] == null))
        .toList();
    if (openProps.isNotEmpty) {
      final p = Map<String, dynamic>.from(openProps.first as Map);
      items.add(DecisionQueueItem(
        id: 'decision-governance-vote-${p['id'] ?? 'p1'}',
        category: 'governance',
        title: 'You have an unresolved governance vote',
        whyItMatters:
            'A municipal referendum regarding city tax charters and public services closes this cycle.',
        deadline: 'Voting Closes Today',
        expectedImpact:
            'Shape tax regulations and direct municipal infrastructure investments.',
        riskLevel: 'medium',
        primaryActionLabel: 'Cast Ballot',
        targetSection: 'civic',
        urgencyScore: 65.0,
      ));
    }

    // 4. Machine maintenance
    final rawMachines = state.json['machines'];
    final machines = rawMachines is List ? rawMachines : const [];
    final degraded = machines.where((m) {
      if (m is! Map) return false;
      final c = asDoubleOr(m['condition'], 100.0);
      return c < 60.0;
    }).toList();
    if (degraded.isNotEmpty) {
      final m = Map<String, dynamic>.from(degraded.first as Map);
      final cond = asDoubleOr(m['condition'], 45.0);
      items.add(DecisionQueueItem(
        id: 'decision-machine-maintenance-${m['id'] ?? 'm1'}',
        category: 'machines',
        title: 'Your machine needs maintenance',
        whyItMatters:
            '${m['name'] ?? 'Primary Machinery'} is at ${cond.round()}% condition. Degraded machinery suffers severe breakdown risk and reduced output rate.',
        deadline: 'Before Next Production Cycle',
        expectedImpact:
            'Restore 100% productive capacity and prevent permanent machinery destruction.',
        riskLevel: cond < 30 ? 'critical' : 'high',
        primaryActionLabel: 'Service Machine',
        targetSection: 'business',
        urgencyScore: cond < 30 ? 95.0 : 80.0,
      ));
    }

    // 5. Research funding
    final rawTech = state.json['technology'];
    Map<dynamic, dynamic>? researchMap;
    if (rawTech is Map) {
      final sub = rawTech['research'];
      if (sub is Map) {
        researchMap = sub;
      } else {
        researchMap = rawTech;
      }
    }
    final progress = asDoubleOr(researchMap?['progress'], 45.0);
    if (progress < 100.0) {
      items.add(const DecisionQueueItem(
        id: 'decision-tech-funding-available',
        category: 'technology',
        title: 'Research funding is available',
        whyItMatters:
            'Fund research to unlock new building, business, and civic capabilities.',
        deadline: 'Current Research Cycle',
        expectedImpact:
            'Advance the current technology and prepare it for direct adoption.',
        riskLevel: 'low',
        primaryActionLabel: 'Fund Research',
        targetSection: 'technology',
        urgencyScore: 40.0,
      ));
    }

    // 5. House & successor
    final rawLife = state.json['life'];
    final life = rawLife is Map ? rawLife : const {};
    final successor = life['successor'];
    if (successor == null) {
      items.add(const DecisionQueueItem(
        id: 'decision-house-successor-pending',
        category: 'house',
        title: 'A house decision is pending',
        whyItMatters:
            'No legal successor is registered for your lineage. In the event of mortal transition, your accumulated estate faces heavy OUC liquidation penalties.',
        deadline: 'Prior to Transition',
        expectedImpact:
            'Guarantee 100% generational wealth preservation and unlock family house perks.',
        riskLevel: 'high',
        primaryActionLabel: 'Manage House',
        targetSection: 'house',
        urgencyScore: 78.0,
      ));
    }

    return items..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
  }
}
