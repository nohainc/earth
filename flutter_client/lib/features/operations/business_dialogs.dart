import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';

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
                    final targetManager = manager.text.trim();
                    if (targetManager.isEmpty) return;
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .appointBusinessManager(businessId, targetManager));
                  },
                  child: const Text('APPOINT')),
            ],
          ));
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
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .liquidateBusiness(businessId, otp: otpCode));
                  },
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: const Text('LIQUIDATE')),
            ],
          ));
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
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .updateBusinessConstitution(
                            businessId, shareValue, boardValue, noticeValue));
                  },
                  child: const Text('SAVE CONSTITUTION')),
            ],
          ));
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
                    final targetRecipient = recipient.text.trim();
                    if (targetRecipient.isEmpty ||
                        amount == null ||
                        amount < 1) {
                      return;
                    }
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .transferShares(targetRecipient, amount, otp: otpCode));
                  },
                  child: const Text('Transfer')),
            ],
          ));
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
                    final targetRecipient = recipient.text.trim();
                    if (targetRecipient.isEmpty ||
                        count == null ||
                        count < 1 ||
                        value == null ||
                        value <= 0) {
                      return;
                    }
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi().issueShares(
                        businessId, targetRecipient, count, value,
                        otp: otpCode));
                  },
                  child: const Text('Issue')),
            ],
          ));
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
                        final bName = name.text.trim();
                        if (bName.length < 3) return;
                        Navigator.pop(dialogContext);
                        await action(() => const EarthApi()
                            .createBusiness(bName, sector));
                      },
                      child: const Text('Register')),
                ],
              )));
}

Future<void> showDividendDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final amount = TextEditingController(text: '100');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final parsedAmount = double.tryParse(amount.text.trim()) ?? 100.0;
        return AlertDialog(
          title: const Text('Distribute dividends'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total distribution (C)'),
                    onChanged: (val) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  ConsequencePreviewCard(
                    consequence: DecisionConsequence.dividendDistribution(
                      businessName: businessId,
                      totalAmount: parsedAmount,
                      shareholderCount: 4,
                    ),
                  ),
                ],
              ),
            ),
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
                Navigator.pop(dialogContext);
                await action(() => const EarthApi().distributeDividends(
                    businessId, value));
              },
              child: const Text('DISTRIBUTE'),
            ),
          ],
        );
      },
    ),
  );
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
            final targetId = target.text.trim();
            if (targetId.isEmpty || value == null || value <= 0) {
              return;
            }
            Navigator.pop(dialogContext);
            await action(() async {
              await const EarthApi().proposeMerger(
                acquirerBusinessId: acquirerBusinessId,
                targetBusinessId: targetId,
                pricePerShare: value,
              );
              return const EarthApi().world();
            });
          },
          child: const Text('PROPOSE'),
        ),
      ],
    ),
  );
}

Future<void> showShareholderResolutionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final titleController = TextEditingController(text: 'Issue 200 New Equity Shares');
  final descriptionController = TextEditingController(
      text: 'Authorize issuance of 200 treasury shares for factory expansion. Requires >66.7% supermajority approval.');
  String resolutionType = 'EQUITY_DILUTION';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Propose shareholder resolution'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Shareholder resolutions protect minority equity holders. Supermajority (>66.7%) approval across all voting shares is legally required for equity dilution or charter changes.',
                style: TextStyle(color: mutedColor, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: resolutionType,
                decoration: const InputDecoration(labelText: 'Resolution type'),
                items: const [
                  DropdownMenuItem(value: 'EQUITY_DILUTION', child: Text('Equity issuance / dilution')),
                  DropdownMenuItem(value: 'CHARTER_AMENDMENT', child: Text('Corporate charter amendment')),
                  DropdownMenuItem(value: 'MERGER_ACQUISITION', child: Text('Corporate merger authorization')),
                  DropdownMenuItem(value: 'DIVIDEND_POLICY', child: Text('Mandatory dividend policy change')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      resolutionType = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Resolution title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description / justification'),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: violetColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: violetColor.withValues(alpha: .3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 14, color: violetColor),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Statutory requirement: >66.7% Supermajority Approval (Spec §1.12.2)',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: violetColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().world());
            },
            child: const Text('TABLE RESOLUTION'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAiAssistantConfigDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  bool autoMaintenance = true;
  bool autoFeedstock = true;
  double computeUnits = 2.0;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('AI Operational Assistant'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deploy automated synthetic operational routines powered by continuous COMP (Compute) resource allocation (Spec §1.13.2).',
                style: TextStyle(color: mutedColor, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automated Machine Maintenance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: const Text('Execute repairs when machine wear drops below 80%', style: TextStyle(fontSize: 10, color: mutedColor)),
                value: autoMaintenance,
                activeThumbColor: cyanAccentColor,
                onChanged: (val) => setDialogState(() => autoMaintenance = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automated Feedstock Reordering', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: const Text('Place batch buy orders when raw materials < 24-hr buffer', style: TextStyle(fontSize: 10, color: mutedColor)),
                value: autoFeedstock,
                activeThumbColor: cyanAccentColor,
                onChanged: (val) => setDialogState(() => autoFeedstock = val),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Allocated Compute Power:', style: TextStyle(fontSize: 11, color: mutedColor)),
                  Text('${computeUnits.toStringAsFixed(1)} COMP / cycle', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cyanAccentColor)),
                ],
              ),
              Slider(
                value: computeUnits,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                activeColor: cyanAccentColor,
                onChanged: (val) => setDialogState(() => computeUnits = val),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().world());
            },
            child: const Text('SAVE AI CONFIG'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showReceivershipRestructuringDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Corporate Insolvency & Restructuring'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Under UC High Court Receivership (Spec §1.16), equity dividends are frozen. Asset liquidations follow strict statutory creditor seniority:',
              style: TextStyle(color: mutedColor, fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                children: [
                  _SeniorityRow(tier: '1', title: 'MUNICIPAL & UC TAX AUTHORITIES', subtitle: 'Senior priority claim on all liquidated assets', color: Colors.redAccent),
                  Divider(height: 12, color: Colors.white10),
                  _SeniorityRow(tier: '2', title: 'SECURED LENDERS & CREDITORS', subtitle: 'Collateralized loans and equipment debentures', color: Colors.orangeAccent),
                  Divider(height: 12, color: Colors.white10),
                  _SeniorityRow(tier: '3', title: 'TRADE SUPPLIERS & CONTRACTORS', subtitle: 'Unpaid raw feedstock and power utility bills', color: Colors.amberAccent),
                  Divider(height: 12, color: Colors.white10),
                  _SeniorityRow(tier: '4', title: 'COMMON EQUITY SHAREHOLDERS', subtitle: 'Residual equity claim after all liabilities satisfied', color: mutedColor),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('CLOSE'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().world());
          },
          child: const Text('SUBMIT WORKOUT PLAN'),
        ),
      ],
    ),
  );
}

class _SeniorityRow extends StatelessWidget {
  final String tier;
  final String title;
  final String subtitle;
  final Color color;

  const _SeniorityRow({required this.tier, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: color.withValues(alpha: .2),
          child: Text(tier, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              Text(subtitle, style: const TextStyle(fontSize: 9, color: mutedColor)),
            ],
          ),
        ),
      ],
    );
  }
}
