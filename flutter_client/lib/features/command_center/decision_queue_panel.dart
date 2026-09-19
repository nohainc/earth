import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/decision_queue_item.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/earth_primitives.dart';

class DecisionQueuePanel extends StatefulWidget {
  final List<DecisionQueueItem> items;
  final ValueChanged<DecisionQueueItem>? onExecuteDecision;
  /// Optional detail opener. Receives the canonical route and entity ID
  /// together so callers can open a specific proposal, building, or order.
  final ValueChanged<DecisionQueueItem>? onOpenDecision;
  final ValueChanged<String>? onNavigate;

  const DecisionQueuePanel({
    super.key,
    required this.items,
    this.onExecuteDecision,
    this.onOpenDecision,
    this.onNavigate,
  });

  @override
  State<DecisionQueuePanel> createState() => _DecisionQueuePanelState();
}

class _DecisionQueuePanelState extends State<DecisionQueuePanel> {
  String _selectedFilter = 'ALL';

  List<DecisionQueueItem> get _filteredItems {
    switch (_selectedFilter) {
      case 'CRITICAL':
        return widget.items
            .where((i) => i.actionStatus == 'CRITICAL')
            .toList();
      case 'ACTION_REQUIRED':
        return widget.items
            .where((i) => i.actionStatus == 'ACTION REQUIRED')
            .toList();
      case 'HOUSE':
        return widget.items
            .where((i) => i.category.toLowerCase() == 'house')
            .toList();
      case 'BUILDINGS':
      case 'FINANCE':
      case 'GOVERNANCE':
      case 'MARKET':
      case 'TECHNOLOGY':
        return widget.items
            .where((i) => i.category.toUpperCase() == _selectedFilter)
            .toList();
      case 'ALL':
      default:
        return widget.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final criticalCount = widget.items
        .where((i) => i.actionStatus == 'CRITICAL')
        .length;
    final actionRequiredCount = widget.items
        .where((i) => i.actionStatus == 'ACTION REQUIRED')
        .length;

    return EarthPanel(
      title: 'ACTION QUEUE',
      infoDescription:
          'Server-authored actions from current House needs, buildings, finance, governance, technology, succession, and market state. The internal priority score controls ordering but is not shown to players.',
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Status & Summary Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: criticalCount > 0
                      ? context.errorColor.withValues(alpha: 0.14)
                      : context.successColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: criticalCount > 0
                        ? context.errorColor.withValues(alpha: 0.45)
                        : context.successColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Text(
                  criticalCount > 0
                      ? '$criticalCount CRITICAL'
                      : actionRequiredCount > 0
                          ? '$actionRequiredCount ACTION REQUIRED'
                          : 'NO ACTION REQUIRED',
                  style: TextStyle(
                    color: criticalCount > 0
                        ? context.errorColor
                        : context.successColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${widget.items.length} TOTAL DECISIONS',
                style: const TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Tab Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('ALL', 'ALL (${widget.items.length})'),
                const SizedBox(width: 6),
                _buildFilterPill('CRITICAL', 'CRITICAL ($criticalCount)'),
                const SizedBox(width: 6),
                _buildFilterPill('ACTION_REQUIRED', 'ACTION REQUIRED ($actionRequiredCount)'),
                for (final domain in const ['HOUSE', 'BUILDINGS', 'FINANCE', 'GOVERNANCE', 'MARKET', 'TECHNOLOGY']) ...[
                  const SizedBox(width: 6),
                  _buildFilterPill(domain, domain),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Decision List or Empty State
          if (_filteredItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 28),
                  SizedBox(height: 8),
                  Text(
                    'NO ACTION REQUIRED',
                    style: TextStyle(
                      color: inkColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'This domain has no server-authored action waiting for you.',
                    style: TextStyle(color: mutedColor, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildDecisionCard(_filteredItems[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
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

  Widget _buildDecisionCard(DecisionQueueItem item) {
    final statusColor = item.actionStatusColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.actionStatus == 'CRITICAL'
              ? statusColor.withValues(alpha: 0.6)
              : Colors.white12,
          width: item.actionStatus == 'CRITICAL' ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Metadata Tag Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.categoryIcon, size: 14, color: context.mutedColor),
              const SizedBox(width: 6),
              Text(
                item.category.toUpperCase(),
                style: TextStyle(
                  color: context.mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  item.actionStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Main Decision Title
          Text(
            item.title,
            style: TextStyle(
              color: context.inkColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),

          // Why It Matters (Narrative explanation)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: context.mutedColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.whyItMatters,
                    style: TextStyle(
                      color: context.mutedColor,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Metrics & Expected Impact Grid
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildMetricPill(
                icon: Icons.timer_outlined,
                label: 'DEADLINE',
                value: item.deadline,
                valueColor: item.actionStatus == 'CRITICAL'
                    ? context.errorColor
                    : context.warningColor,
              ),
              _buildMetricPill(
                icon: Icons.electric_bolt_outlined,
                label: 'EXPECTED IMPACT',
                value: item.expectedImpact,
                valueColor: context.inkColor,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Primary Action CTA Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: item.viewerCanAct ? () {
                  if (widget.onOpenDecision != null) {
                    widget.onOpenDecision!(item);
                  } else if (widget.onExecuteDecision != null) {
                    widget.onExecuteDecision!(item);
                  } else if (widget.onNavigate != null) {
                    widget.onNavigate!(item.targetRoute);
                  }
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: statusColor.withValues(alpha: 0.2),
                  foregroundColor: statusColor,
                  side: BorderSide(color: statusColor.withValues(alpha: 0.8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
                icon: Icon(item.categoryIcon, size: 14, color: statusColor),
                label: Text(
                  (item.viewerCanAct ? item.primaryActionLabel : 'VIEW ONLY')
                      .toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: valueColor),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: const TextStyle(
              color: mutedColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
