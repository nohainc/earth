import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
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
      Color color
    })>[
      (
        label: 'RUN THE BUSINESS',
        detail: '${state.businesses.length} active operations',
        section: 'business',
        icon: Icons.storefront_outlined,
        color: cyanAccentColor
      ),
      (
        label: 'CHECK CITY SERVICES',
        detail: membership['city_id'] == null
            ? 'Choose a city to unlock services'
            : 'Review local capacity and projects',
        section: 'city',
        icon: Icons.location_city_outlined,
        color: Colors.tealAccent
      ),
      (
        label: 'DIRECT RESEARCH',
        detail:
            '${researchProgress.toStringAsFixed(0)}% current project progress',
        section: 'technology',
        icon: Icons.biotech_outlined,
        color: violetColor
      ),
      (
        label: 'PROTECT THE DYNASTY',
        detail: successor is Map && successor.isNotEmpty
            ? 'Successor plan is recorded'
            : 'Register a continuity plan',
        section: successor is Map && successor.isNotEmpty ? 'dynasty' : 'life',
        icon: Icons.account_tree_outlined,
        color: Colors.amberAccent
      ),
      (
        label: 'OPEN MESSAGES',
        detail: 'Review people, invitations, and decisions',
        section: 'messages',
        icon: Icons.settings_input_antenna,
        color: Colors.lightBlueAccent
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('QUICK ACTIONS',
            style: TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
        const SizedBox(width: 8),
        Text('Choose the next meaningful move',
            style: TextStyle(
                color: mutedColor.withValues(alpha: .75), fontSize: 10))
      ]),
      const SizedBox(height: 10),
      Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions.map((item) => _action(item)).toList()),
    ]);
  }

  Widget _action(
          ({
            String label,
            String detail,
            String section,
            IconData icon,
            Color color
          }) item) =>
      SizedBox(
        width: 205,
        child: InkWell(
          onTap: onNavigate == null ? null : () => onNavigate!(item.section),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: item.color.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: item.color.withValues(alpha: .24))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(item.icon, size: 18, color: item.color),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.label,
                        style: TextStyle(
                            color: item.color,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4)),
                    const SizedBox(height: 4),
                    Text(item.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: mutedColor, fontSize: 9.5))
                  ]))
            ]),
          ),
        ),
      );
}
