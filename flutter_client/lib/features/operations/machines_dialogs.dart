import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showDecommissionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Recycle machine?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'This permanently decommissions the machine and salvages 25 Material and 5 Components.'),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .decommissionMachine(machineId, otp: otpCode));
                  },
                  child: const Text('Recycle')),
            ],
          ));
}

Future<void> showMachineUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Upgrade machine'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Upgrade cost: 600 Credits and 20 Components. Capacity increases by +0.2 and installation reduces condition by 5%.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .upgradeMachine(machineId, otp: otpCode));
                  },
                  child: const Text('Upgrade')),
            ],
          ));
}

Future<void> showMachineSaleDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final buyer = TextEditingController();
  final price = TextEditingController(text: '1200');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Sell machine'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: buyer,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Buyer Human ID')),
              TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price in Credits')),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final targetBuyer = buyer.text.trim();
                    final parsedPrice = double.tryParse(price.text.trim());
                    if (targetBuyer.isEmpty || parsedPrice == null || parsedPrice <= 0) return;
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi().sellMachine(
                        machineId, targetBuyer, parsedPrice,
                        otp: otpCode));
                  },
                  child: const Text('Sell')),
            ],
          ));
}

Future<void> showMachineAcquisitionDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  List<dynamic> productionCatalog,
) async {
  final catalogOptions = productionCatalog
      .whereType<Map>()
      .expand((sector) => (sector['machineTypes'] is List ? sector['machineTypes'] as List : const []).map((type) {
        final machineType = type.toString();
        final acquisition = sector['acquisition'] is Map ? Map<String, dynamic>.from(sector['acquisition'] as Map) : const <String, dynamic>{};
        return {'type': machineType, 'output': sector['output']?.toString() ?? 'resource', ...acquisition};
      }))
      .where((option) => option['credit'] != null)
      .toList();
  final options = catalogOptions.isNotEmpty
      ? catalogOptions
      : [
          {'type': 'fabrication-rig', 'output': 'components', 'credit': 850, 'material': 50},
          {'type': 'extraction-unit', 'output': 'material', 'credit': 600, 'material': 40},
          {'type': 'refining-matrix', 'output': 'material', 'credit': 1200, 'material': 80},
          {'type': 'compute-cluster', 'output': 'compute', 'credit': 950, 'material': 30},
          {'type': 'food-synthesizer', 'output': 'food', 'credit': 4400, 'material': 75},
        ];
  String selectedType = options.first['type'].toString();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Acquire Machine'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const Text(
                'Select a production unit from the machine catalog to expand capacity.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedType,
                items: options.map((option) => DropdownMenuItem<String>(
                  value: option['type'].toString(),
                  child: Text('${option['type'].toString().replaceAll('-', ' ').toUpperCase()} · ${option['credit']} C + ${option['material']} Material'),
                )).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => selectedType = val);
                },
              ),
              const SizedBox(height: 14),
              ConsequencePreviewCard(
                consequence: DecisionConsequence.machineAcquisition(
                  machineName: selectedType.replaceAll('-', ' ').toUpperCase(),
                  costCredits: (options.firstWhere((option) => option['type'].toString() == selectedType)['credit'] as num).toDouble(),
                  outputYield: '${options.firstWhere((option) => option['type'].toString() == selectedType)['output']} production capacity',
                  businessName: 'Primary Enterprise',
                ),
              ),
            ],
          ),
        ),
      ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().acquireMachine(selectedType));
            },
            child: const Text('Acquire'),
          ),
        ],
      ),
    ),
  );
}
