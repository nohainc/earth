import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'earth_state.dart';

class PlayerObjective {
  final String id;
  final String category;
  final String title;
  final String description;
  final double currentValue;
  final double targetValue;
  final double progressPercentage;
  final String metricLabel;
  final String status; // 'in_progress', 'completed', 'claimed'
  final String rewardDescription;
  final String targetSection;
  final String iconName;

  const PlayerObjective({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.currentValue,
    required this.targetValue,
    required this.progressPercentage,
    required this.metricLabel,
    required this.status,
    required this.rewardDescription,
    required this.targetSection,
    this.iconName = 'star',
  });

  bool get isCompleted =>
      status == 'completed' ||
      status == 'claimed' ||
      progressPercentage >= 100.0;

  Color get categoryColor {
    switch (category.toLowerCase()) {
      case 'enterprise':
        return Colors.orangeAccent;
      case 'civic':
        return cyanAccentColor;
      case 'dynasty':
        return const Color(0xFFFFD54F);
      case 'technology':
        return violetColor;
      case 'finance':
        return const Color(0xFF00E676);
      case 'civilization':
        return const Color(0xFFFF4081);
      default:
        return cyanAccentColor;
    }
  }

  String get categoryLabel {
    switch (category.toLowerCase()) {
      case 'enterprise':
        return 'ENTERPRISE & INDUSTRY';
      case 'civic':
        return 'CIVIC & GOVERNANCE';
      case 'dynasty':
        return 'DYNASTY & LEGACY';
      case 'technology':
        return 'TECH & RESEARCH';
      case 'finance':
        return 'FINANCE & WEALTH';
      case 'civilization':
        return 'CIVILIZATION HEALTH';
      default:
        return category.toUpperCase();
    }
  }

  IconData get categoryIcon {
    switch (category.toLowerCase()) {
      case 'enterprise':
        return Icons.business_center_outlined;
      case 'civic':
        return Icons.how_to_vote_outlined;
      case 'dynasty':
        return Icons.account_balance_outlined;
      case 'technology':
        return Icons.biotech_outlined;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'civilization':
        return Icons.volunteer_activism_outlined;
      default:
        return Icons.stars_outlined;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'description': description,
        'currentValue': currentValue,
        'targetValue': targetValue,
        'progressPercentage': progressPercentage,
        'metricLabel': metricLabel,
        'status': status,
        'rewardDescription': rewardDescription,
        'targetSection': targetSection,
        'iconName': iconName,
      };

  factory PlayerObjective.fromJson(Map<String, dynamic> json) =>
      PlayerObjective(
        id: json['id']?.toString() ?? 'obj-generic',
        category: json['category']?.toString() ?? 'enterprise',
        title: json['title']?.toString() ?? 'Strategic Objective',
        description: json['description']?.toString() ?? '',
        currentValue: _toDouble(json['currentValue'], 0.0),
        targetValue: _toDouble(json['targetValue'], 100.0),
        progressPercentage: _toDouble(json['progressPercentage'], 0.0),
        metricLabel: json['metricLabel']?.toString() ?? '0 / 100',
        status: json['status']?.toString() ?? 'in_progress',
        rewardDescription:
            json['rewardDescription']?.toString() ?? 'Legacy & Prestige Points',
        targetSection: json['targetSection']?.toString() ?? 'command',
        iconName: json['iconName']?.toString() ?? 'star',
      );

  static double _toDouble(dynamic val, double fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    final parsed = double.tryParse(val.toString());
    return parsed ?? fallback;
  }

  static List<PlayerObjective> synthesizeFromState(EarthState state) {
    final raw = state.json['objectives'] as List<dynamic>?;
    if (raw != null && raw.isNotEmpty) {
      return raw
          .map((item) =>
              PlayerObjective.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    final rawHuman = state.json['human'];
    final human = rawHuman is Map ? rawHuman : const {};
    final credits = _toDouble(human['credits'], 1000.0);
    final standing = _toDouble(human['standing'], 70.0);

    final rawBiz = state.json['business'];
    final biz = rawBiz is Map ? rawBiz : const {};
    final profit = _toDouble(biz['profit'], 0.0);

    final rawLife = state.json['life'];
    final life = rawLife is Map ? rawLife : const {};
    final gen = _toDouble(life['generation'], 1.0);

    final rawWorld = state.json['world'];
    final world = rawWorld is Map ? rawWorld : const {};
    final serviceIndex = _toDouble(
        world['essentialServicesIndex'] ?? world['essential_services_index'],
        0.75);

    final rawTech = state.json['technology'];
    Map<dynamic, dynamic>? techMap;
    if (rawTech is Map) {
      techMap = rawTech['research'] is Map ? rawTech['research'] : rawTech;
    }
    final researchProgress = _toDouble(techMap?['progress'], 45.0);

    return [
      PlayerObjective(
        id: 'obj-valuable-corporation',
        category: 'enterprise',
        title: 'Build the Most Valuable Corporation',
        description:
            'Grow your enterprise into an industrial conglomerate with an enterprise valuation surpassing 100,000 Credits.',
        currentValue: 35000.0 + profit * 10,
        targetValue: 100000.0,
        progressPercentage:
            ((35000.0 + profit * 10) / 100000.0 * 100.0).clamp(0.0, 100.0),
        metricLabel:
            '${(35000 + profit * 10).round().toString()} / 100,000 C Valuation',
        status:
            (35000.0 + profit * 10) >= 100000.0 ? 'completed' : 'in_progress',
        rewardDescription:
            'Title: "Industrial Titan" · +500 Legacy Points · Corporate Tax Charter Exemption',
        targetSection: 'business',
      ),
      PlayerObjective(
        id: 'obj-civic-delegate',
        category: 'civic',
        title: 'Become a Major Civic Delegate',
        description:
            'Amass democratic delegation and civic standing to command at least 25 voting weight across municipal referendums.',
        currentValue: 8.5,
        targetValue: 25.0,
        progressPercentage: (8.5 / 25.0 * 100.0).clamp(0.0, 100.0),
        metricLabel: '8.5 / 25.0 Voting Weight',
        status: 'in_progress',
        rewardDescription:
            'Title: "Grand Tribune" · Veto Injunction Power on City Budgets · +350 Standing',
        targetSection: 'civic',
      ),
      PlayerObjective(
        id: 'obj-dynasty-traits',
        category: 'dynasty',
        title: 'Create a Dynasty with Sovereign Traits',
        description:
            'Advance your generational lineage to Generation 2+ and unlock at least 3 distinct dynasty traits and heirlooms.',
        currentValue: (gen - 1).clamp(0.0, 3.0),
        targetValue: 3.0,
        progressPercentage:
            (((gen - 1).clamp(0.0, 3.0) + (life['successor'] != null ? 1 : 0)) /
                    3.0 *
                    100.0)
                .clamp(0.0, 100.0),
        metricLabel:
            'Gen ${gen.toInt()} · ${(gen - 1).toInt()} / 3 Dynasty Traits Unlocked',
        status: gen >= 3.0 ? 'completed' : 'in_progress',
        rewardDescription:
            'Title: "Eternal Patriarch" · 100% Estate Inheritance Tax Waiver · Ancestral Vault Access',
        targetSection: 'dynasty',
      ),
      PlayerObjective(
        id: 'obj-technology-licensor',
        category: 'technology',
        title: 'Become a Leading Technology Licensor',
        description:
            'Grant exclusive technology patents and establish active commercial licensing contracts with other corporate enterprises.',
        currentValue: (researchProgress / 20.0).clamp(1.0, 6.0),
        targetValue: 6.0,
        progressPercentage:
            ((researchProgress / 20.0).clamp(1.0, 6.0) / 6.0 * 100.0)
                .clamp(0.0, 100.0),
        metricLabel:
            '${(researchProgress / 30).floor()} Patents · 1 Licenses (${(researchProgress / 20).round()}/6 Pts)',
        status: researchProgress >= 100.0 ? 'completed' : 'in_progress',
        rewardDescription:
            'Title: "Chief Innovator" · 3.5% Global Tech Royalty Fee · Instant Research Accelerator',
        targetSection: 'technology',
      ),
      PlayerObjective(
        id: 'obj-financial-independence',
        category: 'finance',
        title: 'Reach Financial Independence',
        description:
            'Accumulate a verified personal net worth exceeding 50,000 Credits with diversified asset streams.',
        currentValue: credits + 15000.0,
        targetValue: 50000.0,
        progressPercentage:
            ((credits + 15000.0) / 50000.0 * 100.0).clamp(0.0, 100.0),
        metricLabel:
            '${(credits + 15000.0).round().toString()} / 50,000 C Net Worth',
        status: (credits + 15000.0) >= 50000.0 ? 'completed' : 'in_progress',
        rewardDescription:
            'Title: "Sovereign Capitalist" · Private Banking Clearance · Priority Exchange Order Routing',
        targetSection: 'finance',
      ),
      PlayerObjective(
        id: 'obj-public-service-score',
        category: 'civilization',
        title: 'Maintain the Highest Public-Service Score',
        description:
            'Optimize municipal health, utilities, and civic infrastructure to sustain a 90%+ Public Service & Standing rating.',
        currentValue: ((serviceIndex * 100.0 + standing) / 2.0).roundToDouble(),
        targetValue: 90.0,
        progressPercentage:
            (((serviceIndex * 100.0 + standing) / 2.0) / 90.0 * 100.0)
                .clamp(0.0, 100.0),
        metricLabel:
            '${((serviceIndex * 100.0 + standing) / 2.0).round()}% / 90% Service Rating',
        status: ((serviceIndex * 100.0 + standing) / 2.0) >= 90.0
            ? 'completed'
            : 'in_progress',
        rewardDescription:
            'Title: "Planetary Benefactor" · Memorial Monument in Pantheon of Living Legends · +1000 Civic Trust',
        targetSection: 'city',
      ),
    ];
  }
}
