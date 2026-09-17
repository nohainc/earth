import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';

/// Read-only physical context for historical Territory records.
///
/// V5 does not expose Territory leases, residence moves, or use-right
/// mutations. Capacity is pooled at Earth/Corporation/House scope and its
/// authoritative financial state is shown by the V5 finance read models.
class TerritoryCommonsPanel extends StatelessWidget {
  final Map<String, dynamic> data;

  const TerritoryCommonsPanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final statement = data['commons'] is Map
        ? Map<String, dynamic>.from(data['commons'] as Map)
        : const <String, dynamic>{};
    final policy = statement['policy'] is Map
        ? Map<String, dynamic>.from(statement['policy'] as Map)
        : const <String, dynamic>{};

    return EarthSection(
      title: 'EARTH PHYSICAL CAPACITY CONTEXT',
      showSurface: false,
      infoBulletPoints: const [
        'Earth owns physical capacity; V5 Houses and Corporations use a pooled capacity model.',
        'Territory records remain available as historical or physical context, not as a separate political or lease authority.',
        'Capacity rent and obligations are shown in the V5 House and Corporation finance read models.',
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        EarthMetricGrid(
          metrics: [
            EarthMetricTile(
              label: 'CAPACITY MODEL',
              value: 'POOLED / EARTH',
              icon: Icons.location_on_outlined,
              accentColor: context.primaryColor,
            ),
            EarthMetricTile(
              label: 'TERRITORY RECORDS',
              value: 'READ ONLY',
              icon: Icons.history_outlined,
              accentColor: context.secondaryColor,
            ),
            EarthMetricTile(
              label: 'DIVIDEND RATE',
              value: policy.isEmpty ? 'NONE' : '${policy['dividend_bps'] ?? 0} BPS',
              icon: Icons.payments_outlined,
              accentColor: context.secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('No Territory use-right or relocation action is required in V5.', style: context.widgetFooterStyle),
        const SizedBox(height: 16),
        Text('COMMONS POLICY & ACCOUNTING STATUS', style: context.topicTitleStyle),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              policy.isEmpty
                  ? 'No active dividend policy is reported for this territory.'
                  : 'Policy: ${policy['reserve_bps'] ?? '—'} bps reserve · ${policy['dividend_bps'] ?? '—'} bps resident dividend',
              style: context.widgetFooterStyle,
            ),
            const SizedBox(height: 4),
            const Text(
              'Figures are server-derived canonical facts. All lease revenues and dividend payments are double-entry verified against the canonical ledger.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ]),
        ),
      ]),
    );
  }
}
