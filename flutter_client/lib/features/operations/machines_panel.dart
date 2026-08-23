import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
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

    return EarthSection(
      title: 'AUTOMATION / MACHINE INVENTORY',
      showSurface: false,
      infoBulletPoints: const [
        'Fleet Inventory: Total count of active, idle, and decommissioned machines.',
        'Physical Condition: Structural wear percentage. Below 35% risks critical failure; below 75% increases power draw.',
        'Utilization Rate: Current workload percentage relative to maximum operational speed.',
        'Productive Capacity: Output scaling multiplier.',
        'Conversion Rates: Required input raw materials consumed per cycle to synthesize output products.',
        'Maintenance Due: Countdown of operational cycles until compulsory preventative overhaul.',
        'Fleet Actions: Dispatch maintenance, acquire new machinery from the catalog, assign units to a business workplace, or sell idle units.',
      ],
      trailing: EarthButton(
        label: 'ACQUIRE MACHINE',
        icon: Icons.add_circle_outline,
        variant: EarthButtonVariant.primary,
        onPressed: busy
            ? null
            : () {
                EarthAudioEngine.instance.playClick();
                showMachineAcquisitionDialog(context, action, productionCatalog);
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'FLEET UNITS',
                value: '${machines.length} DEPLOYED',
                icon: Icons.precision_manufacturing_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'ACTIVE CAPACITY',
                value: '${totalCapacity.toStringAsFixed(1)}x',
                icon: Icons.speed_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'UTILIZATION',
                value: '${averageUtilization.toStringAsFixed(0)}%',
                icon: Icons.bolt_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'FLEET CONDITION',
                value: '${averageCondition.toStringAsFixed(0)}%',
                icon: Icons.health_and_safety_outlined,
                accentColor: averageCondition > 75
                    ? context.successColor
                    : averageCondition > 40
                        ? context.warningColor
                        : context.errorColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingTopic),
          if (machines.isEmpty)
            const EarthEmptyState(
              message: 'No registered machines in active inventory.',
              icon: Icons.precision_manufacturing_outlined,
            )
          else
            Column(
              children: machines.map((raw) {
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

                Color conditionColor = context.primaryColor;
                if (condition < 35) {
                  conditionColor = context.errorColor;
                } else if (condition < 75) {
                  conditionColor = context.warningColor;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$name ($machineType)',
                                  style: context.widgetTitleStyle,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Flow: $inputResource → $outputResource · Capacity: ${capacity.toStringAsFixed(1)}x',
                                  style: context.widgetFooterStyle,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  workplace,
                                  style: context.captionStyle.copyWith(
                                    color: businessName == null
                                        ? context.warningColor
                                        : context.primaryColor,
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
                                style: context.widgetValueStyle.copyWith(color: conditionColor),
                              ),
                              EarthBadge(
                                label: status.toUpperCase(),
                                variant: isInactive ? EarthBadgeVariant.danger : EarthBadgeVariant.success,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Maintenance due: ${maintenanceDue > 0 ? '$maintenanceDue game days' : 'Current'} · Utilization: $utilization%',
                        style: context.widgetFooterStyle,
                      ),
                      if (!isInactive) ...[
                        SizedBox(height: context.spacingControl),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('UTILIZATION:', style: context.captionStyle),
                            for (final level in [0, 25, 50, 75, 100])
                              InkWell(
                                onTap: busy
                                    ? null
                                    : () {
                                        EarthAudioEngine.instance.playClick();
                                        action(() => const EarthApi().setMachineUtilization(id, level));
                                      },
                                borderRadius: BorderRadius.circular(context.radiusControl),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: utilization == level
                                        ? context.primaryColor.withValues(alpha: .2)
                                        : context.surfaceColor,
                                    borderRadius: BorderRadius.circular(context.radiusControl),
                                    border: Border.all(
                                      color: utilization == level
                                          ? context.primaryColor
                                          : context.subtleBorderColor,
                                    ),
                                  ),
                                  child: Text(
                                    '$level%',
                                    style: context.captionStyle.copyWith(
                                      color: utilization == level ? context.primaryColor : context.mutedColor,
                                      fontWeight: utilization == level ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: context.spacingControl),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            EarthButton(
                              label: 'MAINTAIN (10 COMP)',
                              variant: EarthButtonVariant.primary,
                              onPressed: busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      action(() => const EarthApi().maintainMachine(id));
                                    },
                            ),
                            EarthButton(
                              label: 'UPGRADE (+0.2x)',
                              onPressed: busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      showMachineUpgradeDialog(context, action, id);
                                    },
                            ),
                            EarthButton(
                              label: 'SELL MACHINE',
                              onPressed: busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      showMachineSaleDialog(context, action, id);
                                    },
                            ),
                            if (businessId != null && businessId.isNotEmpty)
                              EarthButton(
                                label: businessName == null || businessName.isEmpty
                                    ? 'ASSIGN TO BUSINESS'
                                    : 'RELEASE TO PERSONAL',
                                onPressed: busy
                                    ? null
                                    : () {
                                        EarthAudioEngine.instance.playClick();
                                        action(() => const EarthApi().assignMachineToBusiness(
                                              id,
                                              businessName == null || businessName.isEmpty ? businessId : null,
                                            ));
                                      },
                              ),
                            EarthButton(
                              label: 'RECYCLE',
                              variant: EarthButtonVariant.danger,
                              onPressed: busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      showDecommissionDialog(context, action, id);
                                    },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
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
    return EarthSection(
      title: 'INDUSTRIAL PRODUCTION / EVENT STREAM',
      showSurface: false,
      infoBulletPoints: const [
        'Production Audit Stream: Immutable chronological record of manufacturing, fabrication, and chemical synthesis runs executed across your automated machine fleet.',
        'Cycle Day: Canonical game day when the production run settled.',
        'Machine Class: Model of fabrication rig or synthesis reactor.',
        'Yield & Resource: Net units produced and specific commodity type (Energy, Food, Materials, Components, Compute).',
      ],
      child: events.isEmpty
          ? const EarthEmptyState(
              message: 'No production cycle events recorded.',
              icon: Icons.precision_manufacturing_outlined,
            )
          : EarthDataList(
              children: events.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                final gameDay = event['game_day'] ?? state.clock['day'] ?? 184;
                final outputResource =
                    (event['resource']?.toString() ?? event['output_resource']?.toString() ?? 'MATERIAL')
                        .toUpperCase();
                final outputAmount = event['amount'] ?? event['output_amount'] ?? 0;
                final machineType =
                    (event['machine_name']?.toString() ?? event['machine_type']?.toString() ?? 'RIG').toUpperCase();

                return EarthDataRow(
                  title: 'Machine $machineType Cycle',
                  subtitle: 'Day $gameDay settlement',
                  badges: [
                    EarthBadge(
                      label: '+$outputAmount $outputResource',
                      variant: EarthBadgeVariant.success,
                    ),
                  ],
                );
              }).toList(),
            ),
    );
  }
}
