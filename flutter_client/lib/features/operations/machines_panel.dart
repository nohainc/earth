import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import 'machines_dialogs.dart';

class MachinesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final List<dynamic> productionCatalog;
  final Future<void> Function(Future<EarthState> Function()) action;

  const MachinesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.productionCatalog,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final machines = state.machines;
    return EarthPanel(
      title: 'AUTOMATION / MACHINE INVENTORY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${machines.length} units deployed',
                  style: const TextStyle(color: mutedColor, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showMachineAcquisitionDialog(
                        context, action, productionCatalog),
                child: const Text('ACQUIRE MACHINE'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (machines.isEmpty)
            const Text(
              'No registered machines in active inventory.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...machines.map((raw) {
              final machine = raw as Map<String, dynamic>;
              final id = machine['id']?.toString() ?? '';
              final name = machine['name']?.toString() ?? 'Machine';
              final machineType = (machine['machine_type']?.toString() ?? 'fabrication-rig').toUpperCase();
              final condition = (machine['condition'] as num?)?.toInt() ?? 100;
              final utilization = (machine['utilization'] as num?)?.toInt() ?? 25;
              final capacity = (machine['productive_capacity'] as num?)?.toDouble() ?? 1.0;
              final maintenanceDue = (machine['maintenance_due'] as num?)?.toInt() ?? 0;
              final inputResource = (machine['input_resource']?.toString() ?? 'material').toUpperCase();
              final outputResource = (machine['output_resource']?.toString() ?? 'components').toUpperCase();
              final status = (machine['status']?.toString() ?? 'active').toLowerCase();

              final isInactive = status == 'sold' || status == 'recycled' || status == 'decommissioned';

              Color conditionColor = cyanAccentColor;
              if (condition < 35) {
                conditionColor = Colors.redAccent;
              } else if (condition < 75) {
                conditionColor = Colors.orangeAccent;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$name ($machineType)',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Flow: $inputResource → $outputResource · Capacity: ${capacity.toStringAsFixed(1)}x',
                                style: const TextStyle(fontSize: 10, color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$condition% COND',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: conditionColor,
                              ),
                            ),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                color: isInactive ? Colors.redAccent : mutedColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Maintenance due: ${maintenanceDue > 0 ? '$maintenanceDue game days' : 'Current'} · Utilization: $utilization%',
                      style: const TextStyle(fontSize: 10, color: mutedColor),
                    ),
                    if (!isInactive) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          const Text('UTILIZATION:',
                              style: TextStyle(color: mutedColor, fontSize: 10, height: 2.2)),
                          for (final level in [0, 25, 50, 75, 100])
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                backgroundColor: utilization == level ? Colors.white12 : null,
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .setMachineUtilization(id, level)),
                              child: Text('$level%', style: const TextStyle(fontSize: 10)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().maintainMachine(id)),
                            child: const Text('MAINTAIN (10 COMP)', style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => showMachineUpgradeDialog(context, action, id),
                            child: const Text('UPGRADE (+0.2x)', style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => showMachineSaleDialog(context, action, id),
                            child: const Text('SELL MACHINE', style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => showDecommissionDialog(context, action, id),
                            child: const Text('RECYCLE', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class ProductionEventsPanel extends StatelessWidget {
  final EarthState state;

  const ProductionEventsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final events = state.productionEvents;
    return EarthPanel(
      title: 'INDUSTRIAL PRODUCTION / EVENT STREAM',
      infoDescription:
          'Historical log of machine fleet production runs, output yields, operating cycles, and energy/material conversion events.',
      child: events.isEmpty
          ? const Text(
              'No production cycle events recorded.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: events.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                final gameDay = event['game_day'] ?? state.clock['day'] ?? 184;
                final outputResource =
                    (event['output_resource']?.toString() ?? 'MATERIAL')
                        .toUpperCase();
                final outputAmount = event['output_amount'] ?? 0;
                final machineType =
                    (event['machine_type']?.toString() ?? 'RIG').toUpperCase();

                Color resColor = cyanAccentColor;
                if (outputResource.contains('ENERGY')) resColor = Colors.amberAccent;
                if (outputResource.contains('FOOD')) resColor = Colors.lightGreenAccent;
                if (outputResource.contains('COMPUTE')) resColor = violetColor;
                if (outputResource.contains('COMPONENT')) resColor = Colors.tealAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DAY $gameDay',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: mutedColor,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Machine $machineType Cycle',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: inkColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: resColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: resColor.withValues(alpha: .35)),
                        ),
                        child: Text(
                          '+$outputAmount $outputResource',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: resColor,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
