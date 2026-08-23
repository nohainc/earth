import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showHireEmployeeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final name = TextEditingController();
  final role = TextEditingController(text: 'Operations Specialist');
  final wage = TextEditingController(text: '55');
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Hire a staff member', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: role, decoration: const InputDecoration(labelText: 'Role')),
              const SizedBox(height: 8),
              TextField(
                controller: wage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Wage / cycle (C)'),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'CANCEL',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'HIRE',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final amount = double.tryParse(wage.text.trim());
                  if (name.text.trim().length < 2 || role.text.trim().length < 2 || amount == null || amount <= 0) return;
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi().hireEmployee(businessId, name.text, role.text, amount));
                },
              ),
            ],
          ));
}

Future<void> showBusinessManagerDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  if (businessId == null || businessId.isEmpty) return;
  final manager = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Appoint business manager', style: dialogContext.pageTitleStyle),
            content: TextField(
                controller: manager,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Manager Human ID')),
            actions: [
              EarthButton(
                label: 'CANCEL',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'APPOINT',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final targetManager = manager.text.trim();
                  if (targetManager.isEmpty) return;
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .appointBusinessManager(businessId, targetManager));
                },
              ),
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
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.errorColor.withValues(alpha: 0.5)),
            ),
            title: Text('Liquidate business?', style: dialogContext.pageTitleStyle.copyWith(color: dialogContext.errorColor)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'This permanently closes the business. Its machines will be detached and preserved for future disposition; financial and production history remains recorded.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'CANCEL',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'LIQUIDATE',
                variant: EarthButtonVariant.danger,
                onPressed: () async {
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .liquidateBusiness(businessId, otp: otpCode));
                },
              ),
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
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Business Constitution', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Separate ownership from management with explicit approval thresholds and dilution notice.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: shareholder,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Shareholder vote threshold (0–1)')),
              const SizedBox(height: 8),
              TextField(
                  controller: board,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Board approval threshold (0–1)')),
              const SizedBox(height: 8),
              TextField(
                  controller: notice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Dilution notice (days)')),
            ]),
            actions: [
              EarthButton(
                label: 'CANCEL',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'SAVE CONSTITUTION',
                variant: EarthButtonVariant.primary,
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
              ),
            ],
          ));
}

Future<void> showShareTransferDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String? businessId) async {
  final recipient = TextEditingController();
  final shares = TextEditingController(text: '1');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Transfer business shares', style: dialogContext.pageTitleStyle),
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
              EarthButton(
                label: 'CANCEL',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Transfer',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final amount = int.tryParse(shares.text.trim());
                  final targetRecipient = recipient.text.trim();
                  if (targetRecipient.isEmpty || amount == null || amount < 1) {
                    return;
                  }
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .transferShares(targetRecipient, amount,
                          otp: otpCode, businessId: businessId));
                },
              ),
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
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Issue business shares', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: recipient,
                  decoration:
                      const InputDecoration(labelText: 'Buyer Human ID')),
              const SizedBox(height: 8),
              TextField(
                  controller: shares,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Shares')),
              const SizedBox(height: 8),
              TextField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Price per share')),
              const SizedBox(height: 8),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Issue',
                variant: EarthButtonVariant.primary,
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
              ),
            ],
          ));
}

Future<void> showBusinessComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    {bool hasCity = false, bool hasCorporation = false}) async {
  final name = TextEditingController();
  String sector = 'maintenance';
  const allSectors = [
    'energy',
    'extraction',
    'components',
    'machines',
    'maintenance',
    'housing',
    'compute',
    'r-and-d',
    'it-services',
    'consulting',
    'logistics',
    'healthcare',
    'education',
  ];
  final sectors = allSectors.where((item) =>
      (hasCity || ['components', 'machines', 'maintenance'].contains(item)) &&
      (hasCorporation || !['it-services', 'consulting', 'logistics', 'healthcare', 'education'].contains(item))).toList();
  const groups = <String, List<String>>{
    'Production': ['energy', 'extraction', 'components', 'machines', 'maintenance'],
    'Infrastructure': ['housing', 'compute', 'r-and-d'],
    'Services': ['it-services', 'consulting', 'logistics', 'healthcare', 'education'],
  };
  final availableGroups = groups.entries
      .map((entry) => MapEntry(entry.key, entry.value.where(sectors.contains).toList()))
      .where((entry) => entry.value.isNotEmpty)
      .toList();
  String group = availableGroups.first.key;
  sector = availableGroups.first.value.first;
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                backgroundColor: dialogContext.panelColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
                  side: BorderSide(color: dialogContext.subtleBorderColor),
                ),
                title: Text('Register a Business', style: dialogContext.pageTitleStyle),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Business name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                      initialValue: group,
                      items: availableGroups
                          .map((item) => DropdownMenuItem(value: item.key, child: Text(item.key)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            group = value;
                            sector = groups[group]!.firstWhere(sectors.contains);
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Business group')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                      key: ValueKey(group),
                      initialValue: sector,
                      items: groups[group]!
                          .where(sectors.contains)
                          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => sector = value);
                      },
                      decoration: const InputDecoration(labelText: 'Specialization')),
                ]),
                actions: [
                  EarthButton(
                    label: 'Cancel',
                    variant: EarthButtonVariant.neutral,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                  EarthButton(
                    label: 'Register',
                    variant: EarthButtonVariant.primary,
                    onPressed: () async {
                      final bName = name.text.trim();
                      if (bName.length < 3) return;
                      Navigator.pop(dialogContext);
                      await action(() => const EarthApi()
                          .createBusiness(bName, sector));
                    },
                  ),
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
          backgroundColor: dialogContext.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
            side: BorderSide(color: dialogContext.subtleBorderColor),
          ),
          title: Text('Distribute dividends', style: dialogContext.pageTitleStyle),
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
            EarthButton(
              label: 'CANCEL',
              variant: EarthButtonVariant.neutral,
              onPressed: () => Navigator.pop(dialogContext),
            ),
            EarthButton(
              label: 'DISTRIBUTE',
              variant: EarthButtonVariant.primary,
              onPressed: () async {
                final val = double.tryParse(amount.text.trim());
                if (val == null || val <= 0) return;
                Navigator.pop(dialogContext);
                await action(() => const EarthApi().distributeDividends(
                    businessId, val));
              },
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
      backgroundColor: dialogContext.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
        side: BorderSide(color: dialogContext.subtleBorderColor),
      ),
      title: Text('Propose merger tender offer', style: dialogContext.pageTitleStyle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The target owner must accept the offer before ownership and assets transfer.',
            style: dialogContext.widgetFooterStyle,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: target,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Target business ID'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price per share (C)'),
          ),
        ],
      ),
      actions: [
        EarthButton(
          label: 'CANCEL',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        EarthButton(
          label: 'PROPOSE',
          variant: EarthButtonVariant.primary,
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
        backgroundColor: dialogContext.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
          side: BorderSide(color: dialogContext.subtleBorderColor),
        ),
        title: Text('Propose shareholder resolution', style: dialogContext.pageTitleStyle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shareholder resolutions protect minority equity holders. Supermajority (>66.7%) approval across all voting shares is legally required for equity dilution or charter changes.',
                style: dialogContext.widgetFooterStyle,
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
                  color: dialogContext.secondaryColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(dialogContext.radiusControl),
                  border: Border.all(color: dialogContext.secondaryColor.withValues(alpha: .3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: dialogContext.iconSize, color: dialogContext.secondaryColor),
                    SizedBox(width: dialogContext.spacingInline),
                    Expanded(
                      child: Text(
                        'Statutory requirement: >66.7% Supermajority Approval (Spec §1.12.2)',
                        style: dialogContext.widgetFooterStyle.copyWith(
                          color: dialogContext.secondaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          EarthButton(
            label: 'TABLE RESOLUTION',
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              if (titleController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().world());
            },
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
        backgroundColor: dialogContext.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
          side: BorderSide(color: dialogContext.subtleBorderColor),
        ),
        title: Text('AI Operational Assistant', style: dialogContext.pageTitleStyle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deploy automated synthetic operational routines powered by continuous COMP (Compute) resource allocation (Spec §1.13.2).',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Automated Machine Maintenance', style: dialogContext.widgetTitleStyle),
                subtitle: Text('Execute repairs when machine wear drops below 80%', style: dialogContext.widgetFooterStyle),
                value: autoMaintenance,
                activeThumbColor: dialogContext.primaryColor,
                onChanged: (val) => setDialogState(() => autoMaintenance = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Automated Feedstock Reordering', style: dialogContext.widgetTitleStyle),
                subtitle: Text('Place batch buy orders when raw materials < 24-hr buffer', style: dialogContext.widgetFooterStyle),
                value: autoFeedstock,
                activeThumbColor: dialogContext.primaryColor,
                onChanged: (val) => setDialogState(() => autoFeedstock = val),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Allocated Compute Power:', style: dialogContext.widgetFooterStyle),
                  Text('${computeUnits.toStringAsFixed(1)} COMP / cycle', style: dialogContext.widgetTitleStyle.copyWith(color: dialogContext.primaryColor)),
                ],
              ),
              Slider(
                value: computeUnits,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                activeColor: dialogContext.primaryColor,
                onChanged: (val) => setDialogState(() => computeUnits = val),
              ),
            ],
          ),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          EarthButton(
            label: 'SAVE AI CONFIG',
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().world());
            },
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
      backgroundColor: dialogContext.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
        side: BorderSide(color: dialogContext.subtleBorderColor),
      ),
      title: Text('Corporate Insolvency & Restructuring', style: dialogContext.pageTitleStyle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Under UC High Court Receivership (Spec §1.16), equity dividends are frozen. Asset liquidations follow strict statutory creditor seniority:',
              style: dialogContext.widgetFooterStyle,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: dialogContext.surfaceColor,
                borderRadius: BorderRadius.circular(dialogContext.radiusCard),
                border: Border.all(color: dialogContext.subtleBorderColor),
              ),
              child: Column(
                children: [
                  _SeniorityRow(tier: '1', title: 'MUNICIPAL & UC TAX AUTHORITIES', subtitle: 'Senior priority claim on all liquidated assets', color: dialogContext.errorColor),
                  Divider(height: 12, color: dialogContext.subtleBorderColor),
                  _SeniorityRow(tier: '2', title: 'SECURED LENDERS & CREDITORS', subtitle: 'Collateralized loans and equipment debentures', color: dialogContext.warningColor),
                  Divider(height: 12, color: dialogContext.subtleBorderColor),
                  _SeniorityRow(tier: '3', title: 'TRADE SUPPLIERS & CONTRACTORS', subtitle: 'Unpaid raw feedstock and power utility bills', color: dialogContext.warningColor),
                  Divider(height: 12, color: dialogContext.subtleBorderColor),
                  _SeniorityRow(tier: '4', title: 'COMMON EQUITY SHAREHOLDERS', subtitle: 'Residual equity claim after all liabilities satisfied', color: dialogContext.mutedColor),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        EarthButton(
          label: 'CLOSE',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        EarthButton(
          label: 'SUBMIT WORKOUT PLAN',
          variant: EarthButtonVariant.primary,
          onPressed: () async {
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().world());
          },
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
              Text(title, style: context.widgetTitleStyle.copyWith(color: color, fontSize: 10)),
              Text(subtitle, style: context.widgetFooterStyle),
            ],
          ),
        ),
      ],
    );
  }
}
