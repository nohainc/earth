import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'machines_dialogs.dart';

class MachinesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final List<dynamic> productionCatalog;
  final Map<String, dynamic>? activeBusiness;
  final Future<void> Function(Future<EarthState> Function()) action;

  const MachinesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.productionCatalog,
    this.activeBusiness,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final machines = state.machines;
    final activeMachines = machines.where((raw) {
      final status = (raw as Map)['status']?.toString() ?? 'active';
      return status != 'sold' && status != 'recycled' && status != 'decommissioned';
    }).toList();
    final totalCapacity = activeMachines.fold<double>(
        0, (sum, raw) => sum + asDoubleOr((raw as Map)['productive_capacity'], 1));
    final averageUtilization = activeMachines.isEmpty
        ? 0.0
        : activeMachines.fold<double>(
                0, (sum, raw) => sum + asDoubleOr((raw as Map)['utilization'], 0)) /
            activeMachines.length;
    final averageCondition = activeMachines.isEmpty
        ? 0.0
        : activeMachines.fold<double>(
                0, (sum, raw) => sum + asDoubleOr((raw as Map)['condition'], 100)) /
            activeMachines.length;
    return EarthPanel(
      title: 'AUTOMATION / MACHINE INVENTORY',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Fleet Inventory: Total count of active, idle, and decommissioned machines.\n\n• Machine Telemetry Indicators:\n  - Physical Condition: Structural wear percentage. Below 35% risks critical failure; below 75% increases power draw.\n  - Utilization Rate: Current workload percentage relative to maximum operational speed.\n  - Productive Capacity: Output scaling multiplier.\n  - Conversion Rates: Required input raw materials consumed per cycle to synthesize output products.\n  - Maintenance Due: Countdown of operational cycles until compulsory preventative overhaul.\n\n• Fleet Actions: Dispatch maintenance, acquire new machinery from the catalog, assign units to a business workplace, or sell idle units. Machine upgrades are researched and authorized through a city affiliation.',
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
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _capacityMetric('ACTIVE CAPACITY', '${totalCapacity.toStringAsFixed(1)}x', Icons.speed_outlined),
                _capacityMetric('UTILIZATION', '${averageUtilization.toStringAsFixed(0)}%', Icons.bolt_outlined),
                _capacityMetric('FLEET CONDITION', '${averageCondition.toStringAsFixed(0)}%', Icons.health_and_safety_outlined),
                _capacityMetric('GROWTH DECISION', activeMachines.isEmpty ? 'START FLEET' : 'EXPAND OR OPTIMIZE', Icons.trending_up_outlined),
              ],
            ),
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
              final machineType =
                  (machine['machine_type']?.toString() ?? 'fabrication-rig')
                      .toUpperCase();
              final condition = asIntOr(machine['condition'], 100);
              final utilization = asIntOr(machine['utilization'], 25);
              final capacity =
                  asDoubleOr(machine['productive_capacity'], 1.0);
              final maintenanceDue = asIntOr(machine['maintenance_due'], 0);
              final inputResource =
                  (machine['input_resource']?.toString() ?? 'material')
                      .toUpperCase();
              final outputResource =
                  (machine['output_resource']?.toString() ?? 'components')
                      .toUpperCase();
              final status =
                  (machine['status']?.toString() ?? 'active').toLowerCase();
              final businessName = machine['business_name']?.toString();
              final workplace = businessName == null || businessName.isEmpty
                  ? 'PERSONAL WORK UNIT'
                  : 'WORKPLACE · $businessName';
              final businessId = (activeBusiness ?? state.business)['id']?.toString();

              final isInactive = status == 'sold' ||
                  status == 'recycled' ||
                  status == 'decommissioned';

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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Flow: $inputResource → $outputResource · Capacity: ${capacity.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                    fontSize: 10, color: mutedColor),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                workplace,
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: .6,
                                  fontWeight: FontWeight.w700,
                                  color: businessName == null
                                      ? Colors.orangeAccent
                                      : cyanAccentColor,
                                ),
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
                                color:
                                    isInactive ? Colors.redAccent : mutedColor,
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
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 10,
                                  height: 2.2)),
                          for (final level in [0, 25, 50, 75, 100])
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                backgroundColor: utilization == level
                                    ? Colors.white12
                                    : null,
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .setMachineUtilization(id, level)),
                              child: Text('$level%',
                                  style: const TextStyle(fontSize: 10)),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(
                                    () => const EarthApi().maintainMachine(id)),
                            child: const Text('MAINTAIN (10 COMP)',
                                style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () => showMachineUpgradeDialog(
                                    context, action, id),
                            child: const Text('UPGRADE (+0.2x)',
                                style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () =>
                                    showMachineSaleDialog(context, action, id),
                            child: const Text('SELL MACHINE',
                                style: TextStyle(fontSize: 10)),
                          ),
                          if (businessId != null && businessId.isNotEmpty)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi().assignMachineToBusiness(
                                        id,
                                        businessName == null || businessName.isEmpty ? businessId : null,
                                      )),
                              child: Text(
                                businessName == null || businessName.isEmpty ? 'ASSIGN TO BUSINESS' : 'RELEASE TO PERSONAL',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            onPressed: busy
                                ? null
                                : () =>
                                    showDecommissionDialog(context, action, id),
                            child: const Text('RECYCLE',
                                style: TextStyle(fontSize: 10)),
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

  Widget _capacityMetric(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: cyanAccentColor),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 8.5, color: mutedColor, letterSpacing: .6)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
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
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Production Audit Stream: Immutable chronological record of manufacturing, fabrication, and chemical synthesis runs executed across your automated machine fleet.\n\n• Event Indicators:\n  - Cycle Day: Canonical game day when the production run settled.\n  - Machine Class: Model of fabrication rig or synthesis reactor.\n  - Yield & Resource: Net units produced and specific commodity type (Food, Materials, Energy, Components, Compute).',
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
                if (outputResource.contains('ENERGY'))
                  resColor = Colors.amberAccent;
                if (outputResource.contains('FOOD'))
                  resColor = Colors.lightGreenAccent;
                if (outputResource.contains('COMPUTE')) resColor = violetColor;
                if (outputResource.contains('COMPONENT'))
                  resColor = Colors.tealAccent;

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
                          border: Border.all(
                              color: resColor.withValues(alpha: .35)),
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
