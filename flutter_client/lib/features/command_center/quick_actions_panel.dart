import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

class QuickActionsPanel extends StatelessWidget {
  final EarthState state;
  final ValueChanged<String>? onNavigate;

  const QuickActionsPanel({super.key, required this.state, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final membership = state.membership ?? const <String, dynamic>{};
    final research = state.technology['research'] is Map
        ? Map<String, dynamic>.from(state.technology['research'] as Map)
        : state.technology;
    final researchProgress = asDoubleOr(research['progress'], 0);
    final successor = state.life['successor'];

    final actions = <({
      String label,
      String detail,
      String section,
      IconData icon,
      Color color,
    })>[
      (
        label: 'RUN THE BUSINESS',
        detail: '${state.businesses.length} active operations',
        section: 'business',
        icon: Icons.storefront_outlined,
        color: context.primaryColor,
      ),
      (
        label: 'CHECK CITY SERVICES',
        detail: membership['city_id'] == null
            ? 'Choose a city to unlock services'
            : 'Review local capacity and projects',
        section: 'city',
        icon: Icons.location_city_outlined,
        color: context.successColor,
      ),
      (
        label: 'DIRECT RESEARCH',
        detail: '${researchProgress.toStringAsFixed(0)}% current project progress',
        section: 'technology',
        icon: Icons.biotech_outlined,
        color: context.secondaryColor,
      ),
      (
        label: 'PROTECT THE DYNASTY',
        detail: successor is Map && successor.isNotEmpty
            ? 'Successor plan is recorded'
            : 'Register a continuity plan',
        section: successor is Map && successor.isNotEmpty ? 'dynasty' : 'life',
        icon: Icons.account_tree_outlined,
        color: context.warningColor,
      ),
      (
        label: 'OPEN MESSAGES',
        detail: 'Review people, invitations, and decisions',
        section: 'messages',
        icon: Icons.settings_input_antenna,
        color: context.primaryColor,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('QUICK ACTIONS', style: context.topicTitleStyle),
            SizedBox(width: context.spacingInline),
            Text(
              'Choose the next meaningful move',
              style: context.widgetFooterStyle.copyWith(
                color: context.mutedColor.withValues(alpha: .75),
              ),
            ),
          ],
        ),
        SizedBox(height: context.spacingControl),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions.map((item) => _action(context, item)).toList(),
        ),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    ({
      String label,
      String detail,
      String section,
      IconData icon,
      Color color,
    }) item,
  ) {
    return SizedBox(
      width: 205,
      child: InkWell(
        onTap: onNavigate == null ? null : () => onNavigate!(item.section),
        borderRadius: BorderRadius.circular(context.radiusCard),
        child: Container(
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: item.color.withValues(alpha: .24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, size: context.iconSize, color: item.color),
              SizedBox(width: context.spacingInline),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: context.widgetTitleStyle.copyWith(
                        color: item.color,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
