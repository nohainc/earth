import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/player_objective.dart';
import '../../shared/widgets/earth_primitives.dart';

class ObjectivesPanel extends StatefulWidget {
  final List<PlayerObjective> objectives;
  final ValueChanged<String>? onNavigate;

  const ObjectivesPanel({
    super.key,
    required this.objectives,
    this.onNavigate,
  });

  @override
  State<ObjectivesPanel> createState() => _ObjectivesPanelState();
}

class _ObjectivesPanelState extends State<ObjectivesPanel> {
  String _selectedCategory = 'ALL';

  List<PlayerObjective> get _filteredObjectives {
    switch (_selectedCategory) {
      case 'ENTERPRISE':
        return widget.objectives
            .where((o) =>
                o.category.toLowerCase() == 'enterprise' ||
                o.category.toLowerCase() == 'territory')
            .toList();
      case 'CIVIC_DYNASTY':
        return widget.objectives
            .where((o) =>
                o.category.toLowerCase() == 'civic' ||
                o.category.toLowerCase() == 'dynasty' ||
                o.category.toLowerCase() == 'civilization')
            .toList();
      case 'TECH_FINANCE':
        return widget.objectives
            .where((o) =>
                o.category.toLowerCase() == 'technology' ||
                o.category.toLowerCase() == 'finance')
            .toList();
      case 'COMPLETED':
        return widget.objectives.where((o) => o.isCompleted).toList();
      case 'ALL':
      default:
        return widget.objectives;
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount =
        widget.objectives.where((o) => o.isCompleted).length;
    final totalCount = widget.objectives.length;
    final overallProgress = totalCount > 0
        ? widget.objectives
                .map((o) => o.progressPercentage)
                .reduce((a, b) => a + b) /
            totalCount
        : 0.0;

    return EarthPanel(
      title: 'LONG-TERM STRATEGIC OBJECTIVES',
      infoDescription:
          '• Long-Term Ambition Codex: Optional, measurable strategic pathways designed for enduring planetary mastery.\n\n• Core Ambition Tracks:\n  - Enterprise Titan: Build the most valuable corporation & industrial infrastructure.\n  - Civic Tribune: Secure dominant voting delegation & direct municipal legislation.\n  - Resource Baron: Monopolize regional concession plots & supply channels.\n  - Sovereign Dynasty: Cultivate deep generational lineages & permanent perks.\n  - Tech Pioneer: License exclusive patents to global manufacturing firms.\n  - Sovereign Capital: Achieve complete personal financial independence.\n  - Public Benefactor: Maximize civic standing & municipal infrastructure.\n\n• Progression: All objectives track automatically against live world metrics and award permanent titles, tax benefits, and legacy points upon completion.',
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Global Ambition Gauge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.stars, color: Color(0xFFFFD54F), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$completedCount OF $totalCount OBJECTIVES MASTERED',
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${overallProgress.round()}% TOTAL AMBITION',
                      style: const TextStyle(
                        color: inkColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (overallProgress / 100.0).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFD54F),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Filter Tab Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('ALL', 'ALL ($totalCount)'),
                const SizedBox(width: 6),
                _buildFilterPill('ENTERPRISE', 'ENTERPRISE & SUPPLY'),
                const SizedBox(width: 6),
                _buildFilterPill('CIVIC_DYNASTY', 'CIVIC & DYNASTY'),
                const SizedBox(width: 6),
                _buildFilterPill('TECH_FINANCE', 'TECH & FINANCE'),
                const SizedBox(width: 6),
                _buildFilterPill('COMPLETED', 'COMPLETED ($completedCount)'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Objectives Cards List
          if (_filteredObjectives.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.flag_outlined, color: mutedColor, size: 28),
                  SizedBox(height: 8),
                  Text(
                    'No objectives in this category.',
                    style: TextStyle(
                      color: inkColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredObjectives.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildObjectiveCard(_filteredObjectives[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String categoryKey, String label) {
    final isSelected = _selectedCategory == categoryKey;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = categoryKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? cyanAccentColor.withValues(alpha: 0.18)
              : surfaceColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? cyanAccentColor.withValues(alpha: 0.8) : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? cyanAccentColor : mutedColor,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildObjectiveCard(PlayerObjective objective) {
    final catColor = objective.categoryColor;
    final isDone = objective.isCompleted;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDone
              ? const Color(0xFF00E676).withValues(alpha: 0.6)
              : Colors.white12,
          width: isDone ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Category & Status Row
          Row(
            children: [
              Icon(objective.categoryIcon, size: 14, color: catColor),
              const SizedBox(width: 6),
              Text(
                objective.categoryLabel,
                style: TextStyle(
                  color: catColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : surfaceColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFF00E676).withValues(alpha: 0.6)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDone) ...[
                      const Icon(Icons.check, size: 10, color: Color(0xFF00E676)),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      isDone ? 'MASTERED' : 'IN PROGRESS',
                      style: TextStyle(
                        color: isDone ? const Color(0xFF00E676) : mutedColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Title & Description
          Text(
            objective.title,
            style: const TextStyle(
              color: inkColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            objective.description,
            style: const TextStyle(color: mutedColor, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 10),

          // Progress Gauge & Metric Label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                objective.metricLabel,
                style: TextStyle(
                  color: catColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${objective.progressPercentage.round()}%',
                style: const TextStyle(
                  color: inkColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (objective.progressPercentage / 100.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? const Color(0xFF00E676) : catColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Rewards Banner & Action CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                const Icon(Icons.military_tech_outlined, size: 14, color: Color(0xFFFFD54F)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    objective.rewardDescription,
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onNavigate != null
                      ? () => widget.onNavigate!(objective.targetSection)
                      : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: catColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PURSUE',
                          style: TextStyle(
                            color: catColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.arrow_forward, size: 10, color: catColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the Long-Term Objectives Codex in a dedicated modal view.
Future<void> showObjectivesDialog(
  BuildContext context, {
  required List<PlayerObjective> objectives,
  ValueChanged<String>? onNavigate,
}) =>
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: canvasColor,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white24),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.stars, color: Color(0xFFFFD54F), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'LONG-TERM STRATEGIC OBJECTIVES',
                      style: TextStyle(
                        color: inkColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: mutedColor, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ObjectivesPanel(
                    objectives: objectives,
                    onNavigate: (section) {
                      Navigator.of(ctx).pop();
                      if (onNavigate != null) onNavigate(section);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
