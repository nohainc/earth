import 'package:flutter/material.dart';
import '../../core/models/player_objective.dart';
import '../../shared/design_system/design_system.dart';

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
            .where((o) => o.category.toLowerCase() == 'enterprise')
            .toList();
      case 'CIVIC_HOUSE':
      case 'CIVIC_DYNASTY':
        return widget.objectives
            .where((o) =>
                o.category.toLowerCase() == 'civic' ||
                o.category.toLowerCase() == 'house' ||
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
        final highlights = <PlayerObjective>[];
        for (final category in ['enterprise', 'civic', 'house', 'dynasty']) {
          final match = widget.objectives.cast<PlayerObjective?>().firstWhere(
                (objective) => objective?.category.toLowerCase() == category,
                orElse: () => null,
              );
          if (match != null) highlights.add(match);
        }
        return highlights;
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = widget.objectives.where((o) => o.isCompleted).length;
    final totalCount = widget.objectives.length;
    final overallProgress = totalCount > 0
        ? widget.objectives
                .map((o) => o.progressPercentage)
                .reduce((a, b) => a + b) /
            totalCount
        : 0.0;

    return EarthSection(
      title: 'CURRENT DIRECTION',
      showSurface: false,
      infoBulletPoints: const [
        'Current Direction: Choose the kind of manager and citizen you want to become.',
        'Direction Tracks: Enterprise (profitable businesses), Civic (city laws & capacity), House (family succession), Technology (research and capabilities), Finance (solvency and independence).',
        'Progression: Directions track against live world metrics and unlock practical rewards, titles, and new opportunities.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Global Ambition Gauge
          Container(
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.stars, color: context.warningColor, size: context.iconSize),
                    SizedBox(width: context.spacingInline),
                    Text(
                      '$completedCount OF $totalCount DIRECTIONS COMPLETED',
                      style: context.widgetTitleStyle.copyWith(
                        color: context.warningColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${overallProgress.round()}% OVERALL PROGRESS',
                      style: context.widgetTitleStyle.copyWith(color: context.inkColor),
                    ),
                  ],
                ),
                SizedBox(height: context.spacingControl),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (overallProgress / 100.0).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(context.warningColor),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.spacingTitleOffset),

          // Filter Tab Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('ALL', 'ALL ($totalCount)'),
                const SizedBox(width: 6),
                _buildFilterPill('ENTERPRISE', 'ENTERPRISE'),
                const SizedBox(width: 6),
                _buildFilterPill('CIVIC_HOUSE', 'CIVIC & HOUSE'),
                const SizedBox(width: 6),
                _buildFilterPill('TECH_FINANCE', 'TECH & FINANCE'),
                const SizedBox(width: 6),
                _buildFilterPill('COMPLETED', 'COMPLETED ($completedCount)'),
              ],
            ),
          ),
          SizedBox(height: context.spacingTitleOffset),

          // Objectives Cards List
          if (_filteredObjectives.isEmpty)
            const EarthEmptyState(
              message: 'No objectives in this category.',
              icon: Icons.flag_outlined,
            )
          else
            EarthDataList(
              children: _filteredObjectives.indexed.map((indexed) {
                final item = indexed.$2;
                final isLast = indexed.$1 == _filteredObjectives.length - 1;
                return _buildObjectiveCardContent(item, isLast);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String categoryKey, String label) {
    final isSelected = _selectedCategory == categoryKey;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = categoryKey),
      borderRadius: BorderRadius.circular(context.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: 0.18)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusControl),
          border: Border.all(
            color: isSelected
                ? context.primaryColor.withValues(alpha: 0.8)
                : context.subtleBorderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: context.captionStyle.copyWith(
            color: isSelected ? context.primaryColor : context.mutedColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildObjectiveCardContent(PlayerObjective objective, bool isLast) {
    final catColor = objective.categoryColor;
    final isDone = objective.isCompleted;

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast ? BorderSide.none : BorderSide(color: context.subtleBorderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Category & Status Row
          Row(
            children: [
              Icon(objective.categoryIcon, size: context.iconSize, color: catColor),
              SizedBox(width: context.spacingInline),
              Text(
                objective.categoryLabel,
                style: context.captionStyle.copyWith(
                  color: catColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              EarthBadge(
                label: isDone ? 'MASTERED' : 'IN PROGRESS',
                variant: isDone ? EarthBadgeVariant.success : EarthBadgeVariant.neutral,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Title & Description
          Text(objective.title, style: context.widgetValueStyle),
          const SizedBox(height: 4),
          Text(
            objective.description,
            style: context.widgetFooterStyle.copyWith(height: 1.3),
          ),
          SizedBox(height: context.spacingInline),

          // Progress Gauge & Metric Label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                objective.metricLabel,
                style: context.widgetTitleStyle.copyWith(color: catColor),
              ),
              Text(
                '${objective.progressPercentage.round()}%',
                style: context.widgetTitleStyle.copyWith(color: context.inkColor),
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
                isDone ? context.successColor : catColor,
              ),
            ),
          ),
          SizedBox(height: context.spacingControl),

          // Rewards Banner & Action CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Icon(Icons.military_tech_outlined, size: context.iconSize, color: context.warningColor),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Text(
                    objective.rewardDescription,
                    style: context.widgetFooterStyle.copyWith(
                      color: context.warningColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: context.spacingInline),
                EarthButton(
                  label: 'PURSUE',
                  icon: Icons.arrow_forward,
                  variant: EarthButtonVariant.primary,
                  onPressed: widget.onNavigate != null
                      ? () => widget.onNavigate!(objective.targetSection)
                      : null,
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
        backgroundColor: context.panelColor,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.stars, color: context.warningColor, size: context.iconSize + 4),
                    SizedBox(width: context.spacingInline),
                    Text(
                      'LONG-TERM STRATEGIC OBJECTIVES',
                      style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: context.mutedColor, size: 20),
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
