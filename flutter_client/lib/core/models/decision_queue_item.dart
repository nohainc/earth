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
      case 'organization':
        return Icons.business_center_outlined;
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
        category: json['category']?.toString() ?? 'organization',
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
          .map((item) => DecisionQueueItem.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
    }

    final items = <DecisionQueueItem>[];

    // Organization energy & resource deficit
    final rawResources = state.json['resources'];
    final resources = rawResources is Map ? rawResources : const {};
    final energy = asDoubleOr(resources['energy'], 100.0);
    final materials =
        asDoubleOr(resources['material'] ?? resources['materials'], 100.0);
    final rawOrganization =
        state.json['organization'] ?? state.json['business'];
    final organization = rawOrganization is Map ? rawOrganization : const {};
    final profit = asDoubleOr(organization['profit'], 0.0);

    final rawTerritory = state.json['territory'];
    final territory = rawTerritory is Map ? rawTerritory : const {};
    final territoryId = territory['id']?.toString();
    if (territoryId != null && territoryId.isNotEmpty) {
      final residents =
          asDoubleOr(territory['residents'], 1.0).clamp(1.0, double.infinity);
      final energyCapacity = asDoubleOr(territory['energy_capacity'], 0.0);
      final healthCapacity = asDoubleOr(territory['health_capacity'], 0.0);
      final energyRatio = energyCapacity / residents;
      if (energyRatio < 1.0) {
        items.add(DecisionQueueItem(
          id: 'decision-territory-energy-$territoryId',
          category: 'civic',
          title: 'Your Territory needs an energy recovery plan',
          whyItMatters:
              'The local grid provides ${energyCapacity.round()} capacity for ${residents.round()} residents.',
          deadline: 'Before the next settlement',
          expectedImpact:
              'Restore reliable local services and protect productive assets from brownouts.',
          riskLevel: energyRatio < 0.75 ? 'critical' : 'high',
          primaryActionLabel: 'Review Territory Capacity',
          targetSection: 'territory',
          urgencyScore: 85.0 + ((1.0 - energyRatio).clamp(0.0, 1.0) * 15.0),
        ));
      }
      if (healthCapacity / 100.0 < 0.5) {
        items.add(DecisionQueueItem(
          id: 'decision-territory-health-$territoryId',
          category: 'civic',
          title: 'Your Territory needs a health recovery plan',
          whyItMatters:
              'Health capacity is at ${(healthCapacity / 100.0 * 100).round()}%; prolonged deficits can reduce quality of life.',
          deadline: 'Before the next settlement',
          expectedImpact:
              'Raise health capacity and keep your household and workforce in place.',
          riskLevel: 'critical',
          primaryActionLabel: 'Review Territory Capacity',
          targetSection: 'territory',
          urgencyScore: 92.0,
        ));
      }
    }

    if (energy <= 50) {
      items.add(DecisionQueueItem(
        id: 'decision-organization-energy-deficit',
        category: 'organization',
        title: 'An Organization is losing energy',
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
        id: 'decision-organization-material-deficit',
        category: 'organization',
        title: 'Organization materials are running low',
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
        id: 'decision-organization-negative-cashflow',
        category: 'organization',
        title: 'Organization is operating at a net loss',
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

    // 2. Unresolved governance votes
    final rawGov = state.json['governance'];
    final governance = rawGov is Map ? rawGov : const {};
    final proposals = (governance['proposals'] as List<dynamic>?) ?? const [];
    final openProps = proposals
        .where(
            (p) => p is Map && (p['status'] == 'open' || p['status'] == null))
        .toList();
    if (openProps.isNotEmpty) {
      final p = Map<String, dynamic>.from(openProps.first as Map);
      items.add(DecisionQueueItem(
        id: 'decision-governance-vote-${p['id'] ?? 'p1'}',
        category: 'governance',
        title: 'You have an unresolved governance vote',
        whyItMatters:
            'A governance proposal closes this cycle and may change shared rules or spending priorities.',
        deadline: 'Voting Closes Today',
        expectedImpact:
            'Shape the rules and shared investments that affect your House and Territory.',
        riskLevel: 'medium',
        primaryActionLabel: 'Cast Ballot',
        targetSection: 'civic',
        urgencyScore: 65.0,
      ));
    }

    // 3. Expiring contracts
    final rawContracts = state.json['contracts'];
    final contracts = rawContracts is List ? rawContracts : const [];
    final activeContracts = contracts
        .where(
            (c) => c is Map && (c['status'] == 'active' || c['status'] == null))
        .toList();
    if (activeContracts.isNotEmpty) {
      final c = Map<String, dynamic>.from(activeContracts.first as Map);
      items.add(DecisionQueueItem(
        id: 'decision-contract-expiring-${c['id'] ?? 'c1'}',
        category: 'organization',
        title: 'A contract expires in 2 days',
        whyItMatters:
            'Unfulfilled supply obligations risk penalty fees and client relationship suspension.',
        deadline: 'In 2 Game Days',
        expectedImpact:
            'Complete deliveries and renew the commercial partnership.',
        riskLevel: 'medium',
        primaryActionLabel: 'View Contracts',
        targetSection: 'market',
        urgencyScore: 60.0,
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
            'Protect House continuity across succession and preserve durable assets for the next generation.',
        riskLevel: 'high',
        primaryActionLabel: 'Manage House',
        targetSection: 'house',
        urgencyScore: 78.0,
      ));
    }

    return items..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
  }
}
