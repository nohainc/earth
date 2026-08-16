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
                  'This permanently decommissions the machine and returns a condition-based fraction of its embedded resources.'),
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
                    await action(() => const EarthApi()
                        .decommissionMachine(machineId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Recycle')),
            ],
          ));
  otp.dispose();
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
                  'Upgrade cost: 600 Credits and 20 Components. Capacity increases by 0.2 and installation reduces condition by 5%.',
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
                    await action(() => const EarthApi()
                        .upgradeMachine(machineId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Upgrade')),
            ],
          ));
  otp.dispose();
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
                    final value = double.tryParse(price.text.trim());
                    if (buyer.text.trim().isEmpty ||
                        value == null ||
                        value <= 0) {
                      return;
                    }
                    await action(() => const EarthApi().sellMachine(
                        machineId, buyer.text, value,
                        otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Sell')),
            ],
          ));
  buyer.dispose();
  price.dispose();
  otp.dispose();
}
