import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

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
  String selectedType = 'fabrication-rig';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Acquire Machine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a production unit from the machine catalog to expand capacity.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedType,
              items: const [
                DropdownMenuItem(
                  value: 'fabrication-rig',
                  child: Text('Fabrication Rig · 850 C + 50 Material'),
                ),
                DropdownMenuItem(
                  value: 'extraction-unit',
                  child: Text('Extraction Unit · 600 C + 40 Material'),
                ),
                DropdownMenuItem(
                  value: 'refining-matrix',
                  child: Text('Refining Matrix · 1200 C + 80 Material'),
                ),
                DropdownMenuItem(
                  value: 'compute-cluster',
                  child: Text('Compute Cluster · 950 C + 30 Material'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => selectedType = val);
              },
            ),
          ],
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
