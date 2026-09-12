import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

class _SuccessorComposerDialog extends StatefulWidget {
  final Future<void> Function(Future<EarthState> Function()) action;

  const _SuccessorComposerDialog({required this.action});

  @override
  State<_SuccessorComposerDialog> createState() => _SuccessorComposerDialogState();
}

class _SuccessorComposerDialogState extends State<_SuccessorComposerDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plan succession & testamentary will'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Designate an existing active Human to receive the estate. If you prefer a new adult, leave succession unregistered and use the separate Civic Rebirth path after mortality.',
              style: TextStyle(fontSize: 11, color: mutedColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Successor name',
                hintText: 'e.g. Kaelen Vance',
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.tealAccent.withValues(alpha: .08),
              child: const Text(
                'Your House remains the persistent owner. The successor becomes its new representative; House assets do not transfer between Humans.',
                style: TextStyle(fontSize: 10.5, color: mutedColor),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final n = _name.text.trim();
            Navigator.pop(context);
            await widget.action(() => const EarthApi().registerSuccessor(
                  n,
                ));
          },
          child: const Text('Save plan'),
        ),
      ],
    );
  }

}

Future<void> showSuccessorComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _SuccessorComposerDialog(action: action),
  );
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
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            final parsed = double.tryParse(amount.text.trim());
            if (parsed == null || parsed <= 0) return;
            Navigator.pop(dialogContext);
            await action(() async {
              await const EarthApi().recoverInstitution(
                institutionId,
                parsed,
                otp: otp.text.trim(),
              );
              return const EarthState({});
            });
          },
          child: const Text('AUTHORIZE RECOVERY'),
        ),
      ],
    ),
  );
}
