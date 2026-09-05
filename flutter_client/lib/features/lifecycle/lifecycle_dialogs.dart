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
  final _humanId = TextEditingController();
  final _estateDays = TextEditingController(text: '30');
  List<Map<String, dynamic>> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final result = await const EarthApi().socialDirectory();
      final humans = (result['humans'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (mounted) setState(() => _candidates = humans);
    } catch (_) {
      // Manual Human ID entry remains available if the directory is offline.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _humanId.dispose();
    _estateDays.dispose();
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
            if (_candidates.isNotEmpty) ...[
              const Text('Choose an active person', style: TextStyle(fontSize: 11, color: mutedColor)),
              const SizedBox(height: 6),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _candidates.map((candidate) {
                    final id = candidate['id']?.toString() ?? '';
                    final name = candidate['display_name']?.toString() ?? id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('$name ($id)', style: const TextStyle(fontSize: 10)),
                        onPressed: () {
                          _humanId.text = id;
                          _name.text = name;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 6),
            ],
            TextField(
              controller: _humanId,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Existing Human ID (required for heir claim)',
                hintText: 'e.g. H-0045',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _estateDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estate period (7–90 days)',
                hintText: '30',
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.tealAccent.withValues(alpha: .08),
              child: const Text(
                'Current inheritance rule: 80% of the estate transfers to the successor after the canonical 20% estate tax. Asset ownership and house lineage transfer with the estate.',
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
            final parsedDays = int.tryParse(_estateDays.text.trim()) ?? 30;
            final clampedDays = parsedDays.clamp(7, 90);
            final n = _name.text.trim();
            final hId = _humanId.text.trim();
            Navigator.pop(context);
            await widget.action(() => const EarthApi().registerSuccessor(
                  n,
                  successorHumanId: hId,
                  estatePeriodDays: clampedDays,
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

class _SettleInheritanceDialog extends StatefulWidget {
  final Future<void> Function(Future<EarthState> Function()) action;
  final String predecessorId;
  final String defaultSuccessorName;

  const _SettleInheritanceDialog({
    required this.action,
    required this.predecessorId,
    required this.defaultSuccessorName,
  });

  @override
  State<_SettleInheritanceDialog> createState() => _SettleInheritanceDialogState();
}

class _SettleInheritanceDialogState extends State<_SettleInheritanceDialog> {
  late final TextEditingController _successorName;
  final _successorId = TextEditingController();
  List<Map<String, dynamic>> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _successorName = TextEditingController(text: widget.defaultSuccessorName);
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final result = await const EarthApi().socialDirectory();
      final humans = (result['humans'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (mounted) setState(() => _candidates = humans);
    } catch (_) {
      // Manual Human ID entry remains available if the directory is offline.
    }
  }

  @override
  void dispose() {
    _successorName.dispose();
    _successorId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settle Estate Inheritance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Transfer estate balances and assets to the designated successor. This operation is authoritative and final.',
            style: TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _successorName,
            decoration: const InputDecoration(labelText: 'Successor name'),
          ),
          const SizedBox(height: 10),
          if (_candidates.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose an active successor', style: TextStyle(fontSize: 11, color: mutedColor)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _candidates.map((candidate) {
                  final id = candidate['id']?.toString() ?? '';
                  final name = candidate['display_name']?.toString() ?? id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(name, style: const TextStyle(fontSize: 10)),
                      onPressed: () {
                        _successorId.text = id;
                        _successorName.text = name;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
          ],
          TextField(
            controller: _successorId,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Successor Human ID'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (_successorName.text.trim().length < 2 || _successorId.text.trim().isEmpty) return;
            final sName = _successorName.text.trim();
            final sId = _successorId.text.trim();
            Navigator.pop(context);
            await widget.action(() => const EarthApi().settleInheritance(
                  predecessorId: widget.predecessorId,
                  successorId: sId,
                  successorName: sName,
                ));
          },
          child: const Text('Execute inheritance'),
        ),
      ],
    );
  }
}

Future<void> showSettleInheritanceDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  required String predecessorId,
  required String defaultSuccessorName,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _SettleInheritanceDialog(
      action: action,
      predecessorId: predecessorId,
      defaultSuccessorName: defaultSuccessorName,
    ),
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
