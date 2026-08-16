import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showBusinessManagerDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final manager = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Appoint business manager'),
            content: TextField(
                controller: manager,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Manager Human ID')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    if (manager.text.trim().isEmpty) return;
                    await action(() => const EarthApi()
                        .appointBusinessManager(businessId, manager.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('APPOINT')),
            ],
          ));
  manager.dispose();
}

Future<void> showBusinessLiquidationDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Liquidate business?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'This permanently closes the business. Its machines will be detached and preserved for future disposition; financial and production history remains recorded.',
                  style: TextStyle(color: mutedColor, fontSize: 12)),
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
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    await action(() => const EarthApi()
                        .liquidateBusiness(businessId, otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: const Text('LIQUIDATE')),
            ],
          ));
  otp.dispose();
}

Future<void> showBusinessConstitutionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    Map<String, dynamic> business) async {
  final shareholder = TextEditingController(
      text: '${business['shareholder_vote_threshold'] ?? 0.5}');
  final board = TextEditingController(
      text: '${business['board_approval_threshold'] ?? 0.5}');
  final notice =
      TextEditingController(text: '${business['dilution_notice_days'] ?? 3}');
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Business Constitution'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Separate ownership from management with explicit approval thresholds and dilution notice.',
                  style: TextStyle(color: mutedColor, fontSize: 12)),
              TextField(
                  controller: shareholder,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Shareholder vote threshold (0–1)')),
              TextField(
                  controller: board,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Board approval threshold (0–1)')),
              TextField(
                  controller: notice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Dilution notice (days)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () async {
                    final shareValue = double.tryParse(shareholder.text.trim());
                    final boardValue = double.tryParse(board.text.trim());
                    final noticeValue = int.tryParse(notice.text.trim());
                    final businessId = business['id'] as String?;
                    if (businessId == null ||
                        shareValue == null ||
                        boardValue == null ||
                        noticeValue == null) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .updateBusinessConstitution(
                            businessId, shareValue, boardValue, noticeValue));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('SAVE CONSTITUTION')),
            ],
          ));
  shareholder.dispose();
  board.dispose();
  notice.dispose();
}

Future<void> showShareTransferDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final recipient = TextEditingController();
  final shares = TextEditingController(text: '1');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Transfer business shares'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: recipient,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Recipient Human ID')),
                const SizedBox(height: 12),
                TextField(
                    controller: shares,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Shares to transfer')),
                const SizedBox(height: 12),
                TextField(
                    controller: otp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Authenticator code (if enabled)')),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final amount = int.tryParse(shares.text.trim());
                    if (recipient.text.trim().isEmpty ||
                        amount == null ||
                        amount < 1) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .transferShares(recipient.text, amount, otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Transfer')),
            ],
          ));
  recipient.dispose();
  shares.dispose();
  otp.dispose();
}

Future<void> showShareIssueDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final recipient = TextEditingController();
  final shares = TextEditingController(text: '10');
  final price = TextEditingController(text: '10');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Issue business shares'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: recipient,
                  decoration:
                      const InputDecoration(labelText: 'Buyer Human ID')),
              TextField(
                  controller: shares,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Shares')),
              TextField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Price per share')),
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
                    final count = int.tryParse(shares.text.trim());
                    final value = double.tryParse(price.text.trim());
                    if (recipient.text.trim().isEmpty ||
                        count == null ||
                        count < 1 ||
                        value == null ||
                        value <= 0) {
                      return;
                    }
                    await action(() => const EarthApi().issueShares(
                        businessId, recipient.text, count, value,
                        otp: otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Issue')),
            ],
          ));
  recipient.dispose();
  shares.dispose();
  price.dispose();
  otp.dispose();
}

Future<void> showBusinessComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController();
  String sector = 'maintenance';
  const sectors = [
    'energy',
    'extraction',
    'components',
    'machines',
    'maintenance',
    'housing',
    'compute',
    'r-and-d'
  ];
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Register a Business'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Business name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                      initialValue: sector,
                      items: sectors
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => sector = value);
                      },
                      decoration: const InputDecoration(labelText: 'Sector')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        if (name.text.trim().length < 3) return;
                        await action(() => const EarthApi()
                            .createBusiness(name.text.trim(), sector));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Register')),
                ],
              )));
  name.dispose();
}

Future<void> showDividendDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final amount = TextEditingController(text: '100');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Distribute dividends'),
      content: TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Total distribution (C)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            final value = double.tryParse(amount.text.trim());
            if (value == null || value <= 0) return;
            await action(() => const EarthApi().distributeDividends(
                businessId, value));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('DISTRIBUTE'),
        ),
      ],
    ),
  );
  amount.dispose();
}

Future<void> showMergerDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? acquirerBusinessId) async {
  if (acquirerBusinessId == null || acquirerBusinessId.isEmpty) return;
  final target = TextEditingController();
  final price = TextEditingController(text: '10');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Propose merger tender offer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The target owner must accept the offer before ownership and assets transfer.',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
          TextField(
            controller: target,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Target business ID'),
          ),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price per share (C)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            final value = double.tryParse(price.text.trim());
            if (target.text.trim().isEmpty || value == null || value <= 0) {
              return;
            }
            await action(() async {
              await const EarthApi().proposeMerger(
                acquirerBusinessId: acquirerBusinessId,
                targetBusinessId: target.text.trim(),
                pricePerShare: value,
              );
              return const EarthApi().world();
            });
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('PROPOSE'),
        ),
      ],
    ),
  );
  target.dispose();
  price.dispose();
}
