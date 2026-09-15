import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

class WorldConditionsPanel extends StatelessWidget {
  final EarthState state;
  const WorldConditionsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final raw = state.json['worldConditions'];
    final conditions = raw is List ? raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
    return Container(
      key: const Key('world-conditions-panel'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyanAccentColor.withValues(alpha: .35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.public, color: cyanAccentColor), const SizedBox(width: 8), Text('WORLD CONDITIONS', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
        const SizedBox(height: 6),
        Text(conditions.isEmpty ? 'No active conditions. The core economy is operating under its baseline rules.' : 'Transparent conditions currently affecting the world. Each item shows its source, scope, modifier, and expiry.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (conditions.isEmpty) const Text('BASELINE REGIME', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .7)) else ...conditions.map((condition) {
          final effect = condition['effect'] is Map ? Map<String, dynamic>.from(condition['effect'] as Map) : const <String, dynamic>{};
          final source = condition['source'] is Map ? Map<String, dynamic>.from(condition['source'] as Map) : const <String, dynamic>{};
          final exposure = condition['exposure']?.toString() ?? 'WORLDWIDE';
          final expires = condition['effectiveToGameDay'] == null ? 'No scheduled expiry' : 'Ends day ${condition['effectiveToGameDay']}';
          return ListTile(contentPadding: EdgeInsets.zero, leading: Icon(exposure == 'YOUR_TERRITORY' || exposure == 'WORLDWIDE' ? Icons.tune : Icons.visibility_outlined, size: 20), title: Text('${condition['title'] ?? condition['code'] ?? 'World condition'}'), subtitle: Text('${condition['description'] ?? ''}\n$exposure · ${effect['type'] ?? 'EFFECT'} · ${effect['modifierBps'] ?? 0} bps · $expires · Source ${source['type'] ?? 'SYSTEM'}'), isThreeLine: true);
        }),
      ]),
    );
  }
}
