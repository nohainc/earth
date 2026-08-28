import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'technology_dialogs.dart';

class TechnologyPortfolioPanel extends StatelessWidget {
  final EarthState state;
  final Future<void> Function(Future<EarthState> Function())? action;

  const TechnologyPortfolioPanel({super.key, required this.state, this.action});

  @override
  Widget build(BuildContext context) {
    final technology = state.technologyRegistry;
    final research = technology['research'] is Map
        ? Map<String, dynamic>.from(technology['research'] as Map)
        : technology;
    final name =
        (research['name'] ?? technology['name'] ?? 'Current research project')
            .toString();
    final progress =
        (asDouble(research['progress']) ?? 0).clamp(0, 100).toStringAsFixed(0);
    final adopted = _names(technology['adopted'] ??
        technology['adoptedTechnologies'] ??
        technology['capabilities']);
    final catalog = _names(technology['catalog']);
    final available = _names(technology['available'] ??
        technology['availableTechnologies'] ??
        catalog
            .where((item) => item != name && !adopted.contains(item))
            .toList());
    final applied = adopted;

    return EarthPanel(
      title: 'TECHNOLOGY PORTFOLIO',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Researched does not always mean deployed. A capability must be adopted by a business, city service, or personal life before it changes outcomes.\n\n• Use this view to see what is active, what is ready to adopt, and what still needs investment.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _portfolioRow('IN DEVELOPMENT', name, '$progress% complete',
            Colors.lightBlueAccent),
        const SizedBox(height: 8),
        _portfolioRow(
            'ADOPTED / IN USE',
            applied.isEmpty ? 'Nothing deployed yet' : applied.join(' · '),
            applied.isEmpty
                ? 'Choose where research should matter'
                : 'Changing current outcomes',
            cyanAccentColor),
        const SizedBox(height: 8),
        _portfolioRow(
            'READY TO EXPLORE',
            available.isEmpty
                ? 'New capabilities will appear as research advances'
                : available.join(' · '),
            'Potential next directions',
            violetColor),
        const SizedBox(height: 12),
        if (progress == '100' &&
            research['id'] != null &&
            state.businesses.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: action == null
                  ? null
                  : () => _showAdoptionDialog(
                      context, research['id'].toString(), name),
              icon: const Icon(Icons.upgrade_outlined, size: 15),
              label: const Text('ADOPT FOR A BUSINESS'),
            ),
          ),
        const Text(
            'A breakthrough becomes valuable when you decide where to apply it.',
            style: TextStyle(color: mutedColor, fontSize: 10.5)),
      ]),
    );
  }

  Future<void> _showAdoptionDialog(
      BuildContext context, String technologyId, String technologyName) async {
    String? businessId;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Deploy $technologyName'),
          content: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Business workplace'),
            items: state.businesses
                .map((business) {
                  final id = business['id']?.toString() ?? '';
                  return DropdownMenuItem(
                      value: id,
                      child: Text(business['name']?.toString() ?? id));
                })
                .where((item) => item.value!.isNotEmpty)
                .toList(),
            onChanged: (value) => setState(() => businessId = value),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: businessId == null
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await action?.call(() => const EarthApi()
                          .adoptTechnology(businessId!, technologyId));
                    },
              child: const Text('DEPLOY'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _names(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => item is Map
            ? (item['name'] ?? item['title'] ?? item['id'])?.toString()
            : item.toString())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Widget _portfolioRow(String label, String value, String note, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .28))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: inkColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(note, style: const TextStyle(color: mutedColor, fontSize: 9.5)),
        ])),
      ]),
    );
  }
}

class TechnologyOutcomePanel extends StatefulWidget {
  final EarthState state;

  const TechnologyOutcomePanel({super.key, required this.state});

  @override
  State<TechnologyOutcomePanel> createState() => _TechnologyOutcomePanelState();
}

class _TechnologyOutcomePanelState extends State<TechnologyOutcomePanel> {
  String _selectedBranch = 'ALL';

  @override
  Widget build(BuildContext context) {
    final rawCatalog = widget.state.technologyRegistry['catalog'];
    final catalog = rawCatalog is List && rawCatalog.isNotEmpty
        ? rawCatalog
        : const [
            {
              'name': 'Automated Assembly',
              'branch': 'Construction & Industry',
              'description':
                  'Improves building construction and component output for industrial facilities.',
              'effect': 'Higher building output',
              'target': 'Industrial buildings · Components',
            },
            {
              'name': 'Clean Energy Systems',
              'branch': 'Energy & Infrastructure',
              'description':
                  'Reduces energy demand across productive buildings and civic infrastructure.',
              'effect': 'Lower energy upkeep',
              'target': 'Utilities · Operating buildings',
            },
            {
              'name': 'Food Synthesis',
              'branch': 'Life Support',
              'description':
                  'Expands reliable food production and improves city resilience during shortages.',
              'effect': 'Stronger food supply',
              'target': 'Food buildings · City services',
            },
            {
              'name': 'Predictive Maintenance',
              'branch': 'Construction & Industry',
              'description':
                  'Reduces building upkeep pressure and protects productive capacity over time.',
              'effect': 'Lower upkeep pressure',
              'target': 'Industrial buildings · Estates',
            },
            {
              'name': 'Civic Network Infrastructure',
              'branch': 'Civic Systems',
              'description':
                  'Improves the coordination capacity of city services and civic institutions.',
              'effect': 'Better civic capacity',
              'target': 'Civic buildings · Public services',
            },
          ];
    final items = catalog
        .map((raw) => raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{'name': raw.toString()})
        .toList();
    final branches = <String>[];
    for (final item in items) {
      final branch = _branchFor(item);
      if (!branches.contains(branch)) branches.add(branch);
    }
    final visibleItems = _selectedBranch == 'ALL'
        ? items
        : items.where((item) => _branchFor(item) == _selectedBranch).toList();
    final adoptedNames = _names(widget.state.technologyRegistry['adopted'] ??
        widget.state.technologyRegistry['adoptedTechnologies'] ??
        widget.state.technologyRegistry['capabilities']);
    final resourceFlows = widget.state.json['resourceFlows'] is Map
        ? Map<String, dynamic>.from(widget.state.json['resourceFlows'] as Map)
        : const <String, dynamic>{};
    final pressuredResource = ['energy', 'food', 'material', 'components', 'compute']
        .map((key) {
          final raw = resourceFlows[key] ??
              (key == 'material' ? resourceFlows['materials'] : null);
          return MapEntry(key, asDoubleOr(raw is Map ? raw['net'] : raw, 0));
        })
        .where((entry) => entry.value < 0)
        .fold<MapEntry<String, double>?>(null, (current, entry) =>
            current == null || entry.value < current.value ? entry : current);
    final recommendation = pressuredResource == null
        ? 'Choose the path that supports your next building milestone.'
        : 'Consider ${_recommendationFor(pressuredResource.key)} because ${pressuredResource.key} is in net decline.';
    return EarthPanel(
      title: 'CAPABILITY OUTCOMES',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      titleColor: mutedColor,
      helpAfterTitle: true,
      infoDescription:
          '• Each approved capability has a practical target.\n\n• Research creates potential; adoption connects it to a business or civic workplace.\n\n• Compare the outcome with your current bottleneck before spending research Credits.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: violetColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: violetColor.withValues(alpha: .28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 17, color: violetColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NEXT RESEARCH DIRECTION',
                        style: TextStyle(
                            color: violetColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8)),
                    const SizedBox(height: 3),
                    Text(recommendation,
                        style: const TextStyle(
                            color: inkColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('RESEARCH PATHS',
            style: TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: ['ALL', ...branches]
              .map((branch) => ActionChip(
                    label: Text(branch,
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700)),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: (_selectedBranch == branch
                                ? cyanAccentColor
                                : violetColor)
                            .withValues(alpha: .45)),
                    backgroundColor: (_selectedBranch == branch
                            ? cyanAccentColor
                            : surfaceColor)
                        .withValues(alpha: .65),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    avatar: null,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _selectedBranch = branch),
                  ))
              .toList(),
        ),
        const SizedBox(height: 14),
        ...visibleItems.take(8).map((item) {
        final name =
            (item['name'] ?? item['title'] ?? 'Approved capability').toString();
        final description = (item['description'] ??
                'Approved capability with a defined gameplay effect.')
            .toString();
        final effect = (item['effect'] ?? 'Practical capability improvement')
            .toString()
            .replaceAll('_', ' ');
        final branch = _branchFor(item);
        final target = (item['target'] ??
                item['affected_buildings'] ??
                item['resource_effect'] ??
                'Buildings, businesses, or civic services')
            .toString()
            .replaceAll('_', ' ');
        final requirement = item['requirements'] ?? item['requirement'];
        final locked = item['locked'] == true;
        final prerequisite = item['prerequisites'] ?? item['requires'];
        final prerequisiteText = _formatPrerequisites(prerequisite);
        final researchCost = item['researchCost'] ??
            item['research_cost'] ??
            item['cost'] ??
            item['cost_credits'];
        final before = item['before'] ?? item['currentValue'] ?? item['current_value'];
        final after = item['after'] ?? item['projectedValue'] ?? item['projected_value'];
        final milestone = item['milestone'] ?? item['tier'] ?? _milestoneFor(item);
        final adopted = adoptedNames.contains(name);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 16, color: cyanAccentColor),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w800))),
                    Text(_effectLabel(effect).toUpperCase(),
                        style: const TextStyle(
                            color: violetColor,
                            fontSize: 8,
                            fontWeight: FontWeight.w800))
                  ]),
                  const SizedBox(height: 3),
                  Text(description,
                      style: const TextStyle(color: mutedColor, fontSize: 9.5)),
                  const SizedBox(height: 5),
                  Text('PATH: $branch · $milestone · APPLIES TO: $target',
                      style: const TextStyle(
                          color: cyanAccentColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      'COST: ${researchCost == null ? 'Set by project' : '${researchCost.toString()} C'} · PREREQUISITE: $prerequisiteText',
                      style: const TextStyle(
                          color: mutedColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600)),
                  if (before != null || after != null) ...[
                    const SizedBox(height: 5),
                    Text('BEFORE → AFTER: ${before ?? 'Current'} → ${after ?? 'Improved'}',
                        style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                  ],
                  if (adopted) ...[
                    const SizedBox(height: 3),
                    const Text('ADOPTED · Currently affecting outcomes',
                        style: TextStyle(
                            color: cyanAccentColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                  ],
                  if (prerequisite != null) ...[
                    const SizedBox(height: 3),
                    Text('PREREQUISITE · $prerequisite',
                        style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                  ],
                  if (locked || requirement != null) ...[
                    const SizedBox(height: 3),
                    Text(
                        locked
                            ? 'LOCKED · ${requirement ?? 'Complete the prerequisite research first.'}'
                            : 'REQUIREMENT · $requirement',
                        style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ])),
          ]),
        );
        }),
      ]),
    );
  }

  List<String> _names(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => item is Map
            ? (item['name'] ?? item['title'] ?? item['id'])?.toString()
            : item.toString())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  String _milestoneFor(Map<String, dynamic> item) {
    final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
    if (name.contains('civic')) return 'CIVIC INNOVATION';
    if (name.contains('energy') || name.contains('food')) {
      return 'APPLIED SYSTEMS';
    }
    return 'FOUNDATION';
  }

  String _branchFor(Map<String, dynamic> item) {
    final explicit = item['branch'] ?? item['category'] ?? item['domain'];
    if (explicit != null && explicit.toString().trim().isNotEmpty) {
      return explicit.toString().replaceAll('_', ' ');
    }
    final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
    if (name.contains('energy')) return 'Energy & Infrastructure';
    if (name.contains('food')) return 'Life Support';
    if (name.contains('civic')) return 'Civic Systems';
    if (name.contains('assembly') || name.contains('maintenance')) {
      return 'Construction & Industry';
    }
    return 'General Capability';
  }

  String _recommendationFor(String resource) {
    switch (resource) {
      case 'energy':
        return 'Energy & Infrastructure';
      case 'food':
        return 'Life Support';
      case 'material':
      case 'components':
        return 'Construction & Industry';
      case 'compute':
        return 'Computing & Research';
      default:
        return 'the path matching your current bottleneck';
    }
  }

  String _formatPrerequisites(dynamic raw) {
    if (raw == null) return 'None';
    if (raw is List) {
      if (raw.isEmpty) return 'None';
      return raw
          .map((item) => item is Map
              ? (item['name'] ?? item['title'] ?? item['id'])?.toString()
              : item.toString())
          .whereType<String>()
          .join(', ');
    }
    final text = raw.toString().trim();
    return text.isEmpty ? 'None' : text;
  }

  String _effectLabel(String effect) {
    switch (effect) {
      case 'assembly_output_bonus':
        return 'Higher building output';
      case 'energy_efficiency':
        return 'Lower energy upkeep';
      case 'food_output_bonus':
        return 'Stronger food supply';
      case 'maintenance_reduction':
        return 'Lower building upkeep';
      case 'civic_capacity_bonus':
        return 'Higher civic capacity';
      default:
        return effect.replaceAll('_', ' ');
    }
  }
}

class TechnologyPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const TechnologyPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tech = state.technology;
    final research = tech['research'] is Map<String, dynamic>
        ? (tech['research'] as Map<String, dynamic>)
        : tech;
    final techName = (research['name'] as String?)?.toUpperCase() ??
        (tech['name'] as String?)?.toUpperCase() ??
        'ADAPTIVE MAINTENANCE AI';
    final techId = research['id']?.toString() ?? 'TECH-001';
    final progress =
        (asDouble(research['progress']) ?? asDouble(tech['progress']) ?? 0.0)
            .clamp(0.0, 100.0);
    final focus = (research['focus'] ?? tech['focus'] ?? 'efficiency')
        .toString()
        .toUpperCase();
    final budgetNum = research['budget'] ?? research['budgetPerDay'] ?? 240;
    final budget = asDoubleOr(budgetNum, 240.0);
    final isComplete = progress >= 100;
    final computeReserve = asDoubleOr(state.resources['compute'], 0);
    final buildingCount = state.buildings.length;
    final historyEvents = state.history['events'] is List
        ? (state.history['events'] as List).whereType<Map>().toList()
        : <Map>[];
    final researchEvents = historyEvents.where((event) {
      final text = '${event['event_type'] ?? ''} ${event['title'] ?? ''} ${event['details'] ?? ''}'.toLowerCase();
      return text.contains('research') || text.contains('technology');
    }).take(4).toList();


    Color focusColor = cyanAccentColor;
    if (focus == 'DURABILITY') focusColor = Colors.tealAccent;
    if (focus == 'SAFETY') focusColor = Colors.lightGreenAccent;
    if (focus == 'COST') focusColor = Colors.amberAccent;

    return EarthPanel(
      key: panelKey,
      title: 'RESEARCH / CURRENT BREAKTHROUGH',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Research is a city capability: you must be affiliated with a city before starting or funding an upgrade. Independent characters can use their existing starter capability, but cannot expand the technology tree until they join a city.\n\n• Choose and fund a capability that improves your businesses, city, or personal life. Compare the practical benefit: efficiency, durability, safety, or lower cost.\n\n• Once complete, adopt the capability where it matters in Businesses & Operations or civic infrastructure.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ACTIVE RESEARCH PROJECT COCKPIT
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: violetColor.withValues(alpha: .4)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.biotech_outlined,
                        size: 22,
                        color: cyanAccentColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  techName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: inkColor,
                                    letterSpacing: .5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: (isComplete
                                          ? cyanAccentColor
                                          : Colors.lightBlueAccent)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: (isComplete
                                            ? cyanAccentColor
                                            : Colors.lightBlueAccent)
                                        .withValues(alpha: .4),
                                  ),
                                ),
                                child: Text(
                                  isComplete ? 'COMPLETED' : 'IN RESEARCH',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color: isComplete
                                        ? cyanAccentColor
                                        : Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PROJECT ID: $techId  ·  FOCUS: ${focus.toLowerCase()}  ·  STATUS: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: mutedColor,
                              letterSpacing: .6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Progress Bar & Percentage
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RESEARCH PROGRESSION',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: mutedColor.withValues(alpha: .9),
                      ),
                    ),
                    Text(
                      '${progress.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: isComplete ? cyanAccentColor : inkColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    minHeight: 8,
                    color:
                        isComplete ? cyanAccentColor : Colors.lightBlueAccent,
                    backgroundColor: Colors.white10,
                  ),
                ),

                const SizedBox(height: 14),

                // Focus & Budget Breakdown Badges (Wrap to prevent horizontal overflow)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: focusColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: focusColor.withValues(alpha: .3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 12, color: focusColor),
                          const SizedBox(width: 5),
                          Text(
                            'FOCUS: $focus',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: focusColor,
                              letterSpacing: .5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        'Funding: ${formatWholeNumber(budget)} C · Compute reserve: ${formatWholeNumber(computeReserve)} · ${isComplete ? 'Ready to deploy' : '${(100 - progress).toStringAsFixed(0)}% remaining'}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        'City context: $buildingCount active building${buildingCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // R&D ACTIONS
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'RESEARCH DECISIONS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cyanAccentColor,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy || isComplete
                      ? null
                      : () => action(() => const EarthApi().fundResearch()),
                  icon: const Icon(Icons.bolt_rounded, size: 15),
                  label: const Text(
                    'FUND 240 C · +4% MAX',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: inkColor,
                    side: const BorderSide(color: Colors.white24),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy
                      ? null
                      : () => showResearchComposerDialog(context, action),
                  icon: const Icon(Icons.science_outlined, size: 15),
                  label: const Text(
                    'NEW PROJECT · 240 C',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (researchEvents.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'RESEARCH RECORD',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 8),
            ...researchEvents.map((event) {
              final title = (event['title'] ??
                      event['event_type'] ??
                      'Research event')
                  .toString()
                  .replaceAll('_', ' ');
              final day = event['game_day'] ?? event['day'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 13, color: mutedColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        day == null ? title : 'Day $day · $title',
                        style: const TextStyle(
                            color: mutedColor, fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

}
