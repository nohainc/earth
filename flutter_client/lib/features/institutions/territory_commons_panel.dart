import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';

class TerritoryCommonsPanel extends StatelessWidget {
  final Map<String, dynamic> data;

  const TerritoryCommonsPanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final residency = data['residency'] is Map ? Map<String, dynamic>.from(data['residency'] as Map) : const <String, dynamic>{};
    final rights = (data['rights'] as List<dynamic>?) ?? const [];
    final statement = data['commons'] is Map ? Map<String, dynamic>.from(data['commons'] as Map) : const <String, dynamic>{};
    final territory = residency['currentTerritoryId'] ?? residency['territoryId'] ?? 'unassigned';
    final policy = statement['policy'] is Map ? Map<String, dynamic>.from(statement['policy'] as Map) : const <String, dynamic>{};
    return EarthSection(
      title: 'TERRITORY COMMONS',
      showSurface: false,
      infoBulletPoints: const [
        'Territory capacity is a time-bounded use right, separate from building ownership.',
        'Rent funds the governing commons account; it is not a login reward.',
        'Commons dividends are declared by the governing authority and paid only from collected rent.',
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CURRENT TERRITORY', style: context.topicTitleStyle),
        const SizedBox(height: 6),
        Text('$territory', style: context.widgetFooterStyle),
        const SizedBox(height: 16),
        Text('YOUR USE RIGHTS', style: context.topicTitleStyle),
        const SizedBox(height: 6),
        if (rights.isEmpty)
          Text('No active private use rights. Acquire one before starting private construction.', style: context.widgetFooterStyle)
        else
          ...rights.whereType<Map>().map((right) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${right['slot_quantity'] ?? 0} private slots'),
                subtitle: Text('Rent/day: ${right['rent_per_game_day_units'] ?? '—'} · ends: ${right['effective_to_game_day'] ?? 'open'}'),
                trailing: Text('${right['status'] ?? 'ACTIVE'}'),
              )),
        const SizedBox(height: 12),
        Text('COMMONS STATEMENT', style: context.topicTitleStyle),
        const SizedBox(height: 6),
        Text(policy.isEmpty ? 'No active dividend policy is published.' : 'Reserve: ${policy['reserve_bps'] ?? '—'} bps · dividend: ${policy['dividend_bps'] ?? '—'} bps', style: context.widgetFooterStyle),
        const SizedBox(height: 6),
        Text('Revenue and declarations below are server-derived canonical facts.', style: context.widgetFooterStyle),
      ]),
    );
  }
}
