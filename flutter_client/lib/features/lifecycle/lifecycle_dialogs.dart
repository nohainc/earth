import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showSuccessorComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController(text: 'Alex Kline');
  final humanId = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Plan succession'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Successor name')),
              const SizedBox(height: 10),
              TextField(
                  controller: humanId,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Existing Human ID (optional)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (name.text.trim().length < 2) return;
                    await action(() => const EarthApi().registerSuccessor(
                        name.text,
                        successorHumanId: humanId.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Save plan')),
            ],
          ));
  name.dispose();
  humanId.dispose();
}

Future<void> showRecoveryDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String institutionId,
  String institutionKind,
) async {
  final amount = TextEditingController(text: '100');
  final otp = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Recover $institutionKind'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
            'Contribute Credits to restore this institution to active status.',
            style: TextStyle(color: mutedColor, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Recovery contribution (Credits)')),
        const SizedBox(height: 8),
        TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Authenticator code (if enabled)')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: () async {
              final parsed = double.tryParse(amount.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().recoverInstitution(
                  institutionId, parsed,
                  otp: otp.text.trim()));
            },
            child: const Text('AUTHORIZE RECOVERY')),
      ],
    ),
  );
  amount.dispose();
  otp.dispose();
}

Future<void> showContractComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final counterparty = TextEditingController();
  final title = TextEditingController();
  final amount = TextEditingController(text: '100');
  var kind = 'intellectual_service';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Propose agreement'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: kind,
                      items: const [
                        DropdownMenuItem(
                            value: 'employment', child: Text('Employment')),
                        DropdownMenuItem(
                            value: 'intellectual_service',
                            child: Text('Intellectual service')),
                        DropdownMenuItem(
                            value: 'capacity', child: Text('Capacity')),
                        DropdownMenuItem(
                            value: 'strategic', child: Text('Strategic')),
                      ],
                      onChanged: (value) =>
                          setState(() => kind = value ?? kind)),
                  TextField(
                      controller: counterparty,
                      decoration: const InputDecoration(
                          labelText: 'Counterparty Human ID')),
                  TextField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'Agreement title')),
                  TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Credits')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        final value = double.tryParse(amount.text.trim());
                        if (counterparty.text.trim().isEmpty ||
                            title.text.trim().length < 3 ||
                            value == null ||
                            value < 0) {
                          return;
                        }
                        await action(() => const EarthApi().createContract(
                            kind, counterparty.text, title.text, value));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Propose')),
                ],
              )));
  counterparty.dispose();
  title.dispose();
  amount.dispose();
}
