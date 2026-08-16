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
    return EarthPanel(
      title: 'AUTOMATION / MACHINES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.machines.isEmpty)
            const Text('No registered machines.')
          else
            ...state.machines.map((raw) {
              final machine = raw as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${machine['name']}\n${machine['machine_type']}\n${machine['input_resource']} → ${machine['output_resource']}',
                          ),
                        ),
                        Text(
                          '${machine['condition']}%\n${machine['maintenance_due']} due',
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .maintainMachine(machine['id'] as String)),
                          child: const Text('MAINTAIN'),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showDecommissionDialog(
                                  context, action, machine['id'] as String),
                          child: const Text('RECYCLE'),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showMachineUpgradeDialog(
                                  context, action, machine['id'] as String),
                          child: const Text('UPGRADE'),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showMachineSaleDialog(
                                  context, action, machine['id'] as String),
                          child: const Text('SELL'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        const Text('UTILIZATION',
                            style: TextStyle(color: mutedColor, fontSize: 11)),
                        for (final level in [0, 25, 50, 75, 100])
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi()
                                    .setMachineUtilization(
                                        machine['id'] as String, level)),
                            child: Text('$level%'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          const Text('Acquire a specialized production unit:',
              style: TextStyle(color: mutedColor, fontSize: 11)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: productionCatalog.isEmpty
                ? [
                    const Text('Production catalog is loading…',
                        style: TextStyle(color: mutedColor, fontSize: 11))
                  ]
                : productionCatalog
                    .where((raw) =>
                        (raw as Map<String, dynamic>)['acquisition'] != null)
                    .expand((raw) {
                    final sector = raw as Map<String, dynamic>;
                    final types =
                        (sector['machineTypes'] as List<dynamic>?) ?? const [];
                    return types.map((type) => OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .acquireMachine(type.toString())),
                          child: Text(
                            '${type.toString().toUpperCase()} · ${sector['name']} · ${sector['acquisition']?['credit'] ?? '—'} C / ${sector['acquisition']?['material'] ?? '—'} M',
                          ),
                        ));
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
    return EarthPanel(
      title: 'PRODUCTION / AUTHORITATIVE OUTPUT',
      child: state.productionEvents.isEmpty
          ? const Text(
              'Production history will appear after an active machine completes a settlement cycle.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.productionEvents.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    'DAY ${event['game_day']}  ·  +${event['amount']} ${event['resource']}  ·  ${event['machine_name'] ?? event['machine_id']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
