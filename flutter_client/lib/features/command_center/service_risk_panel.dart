import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

class ServiceRiskPanel extends StatelessWidget {
  final EarthState state;

  const ServiceRiskPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final rawNeeds = state.json['serviceNeeds'];
    final needs = rawNeeds is List
        ? rawNeeds.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : <Map<String, dynamic>>[];
    final status = state.json['serviceStatus'] is Map
        ? Map<String, dynamic>.from(state.json['serviceStatus'] as Map)
        : const <String, dynamic>{};
    final critical = needs.where((row) => row['risk_level'] == 'CRITICAL').length;
    final watch = needs.where((row) => row['risk_level'] == 'WATCH').length;
    final total = needs.isNotEmpty ? needs.length : status.length;
    final summary = total == 0
        ? 'No finalized service assessment yet.'
        : critical > 0
            ? '$critical critical service gap${critical == 1 ? '' : 's'}'
            : watch > 0
                ? '$watch service area${watch == 1 ? '' : 's'} to watch'
                : 'All assessed services are stable';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (critical > 0 ? context.warningColor : cyanAccentColor).withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(critical > 0 ? Icons.warning_amber_rounded : Icons.health_and_safety_outlined,
              color: critical > 0 ? context.warningColor : cyanAccentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LIFE & SERVICES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: mutedColor)),
              const SizedBox(height: 4),
              Text(summary, style: TextStyle(color: context.inkColor, fontWeight: FontWeight.w700)),
              if (needs.isNotEmpty)
                Text('${needs.fold<int>(0, (sum, row) => sum + (asInt(row['shortfall_units']) ?? 0))} units currently unallocated',
                    style: const TextStyle(color: mutedColor, fontSize: 11)),
            ]),
          ),
          if (watch > 0 || critical > 0)
            Text('${critical + watch} OPEN', style: const TextStyle(color: mutedColor, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
