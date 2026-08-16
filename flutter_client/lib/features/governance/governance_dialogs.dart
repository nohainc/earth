import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showProposalComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final title = TextEditingController();
  final body = TextEditingController();
  final targetRate = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Create UC proposal'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    maxLength: 140,
                    decoration: const InputDecoration(
                        labelText: 'Title (8–140 characters)')),
                const SizedBox(height: 12),
                TextField(
                    controller: body,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                        labelText: 'Policy proposal (20–4000 characters)')),
                const SizedBox(height: 12),
                TextField(
                    controller: targetRate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Optional UC finance rate (0–0.25)')),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (title.text.trim().length < 8 ||
                        body.text.trim().length < 20) {
                      return;
                    }
                    final rate = targetRate.text.trim().isEmpty
                        ? null
                        : double.tryParse(targetRate.text.trim());
                    if (targetRate.text.trim().isNotEmpty &&
                        (rate == null || rate < 0 || rate > .25)) {
                      return;
                    }
                    await action(() => const EarthApi().createProposal(
                        title.text.trim(), body.text.trim(),
                        targetCategory: rate == null ? null : 'finance',
                        targetRate: rate));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit proposal')),
            ],
          ));
}

Future<void> showDelegateDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String roleId) async {
  final delegate = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Delegate authority'),
            content: TextField(
                controller: delegate,
                decoration:
                    const InputDecoration(labelText: 'Active Human ID')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (delegate.text.trim().isEmpty) return;
                    await action(() =>
                        const EarthApi().delegateRole(roleId, delegate.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Delegate')),
            ],
          ));
}

Future<void> showChallengeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String proposalId) async {
  final reason = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('File constitutional challenge'),
            content: TextField(
                controller: reason,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                    labelText: 'Constitutional grounds (10–2000 characters)')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (reason.text.trim().length < 10) return;
                    await action(() => const EarthApi()
                        .challengeProposal(proposalId, reason.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('File challenge')),
            ],
          ));
}

Future<void> showAppealRulingDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String proposalId) async {
  final rationale = TextEditingController();
  var ruling = 'uphold';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Issue High Court ruling'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: ruling,
                      items: const [
                        DropdownMenuItem(
                            value: 'uphold', child: Text('Uphold proposal')),
                        DropdownMenuItem(
                            value: 'void', child: Text('Void proposal')),
                      ],
                      onChanged: (value) =>
                          setState(() => ruling = value ?? ruling)),
                  TextField(
                      controller: rationale,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                          labelText:
                              'Judicial rationale (10–2000 characters)')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        if (rationale.text.trim().length < 10) return;
                        await action(() => const EarthApi()
                            .resolveConstitutionalAppeal(
                                proposalId, ruling, rationale.text));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Issue ruling')),
                ],
              )));
}

Future<void> showDisputeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String contractId) async {
  final reason = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Open UC arbitration'),
            content: TextField(
                controller: reason,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Reason (10–1000 characters)')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    if (reason.text.trim().length < 10) return;
                    await action(() => const EarthApi()
                        .disputeContract(contractId, reason.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit dispute')),
            ],
          ));
}

Future<void> showResolveDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String contractId) async {
  final resolution = TextEditingController();
  var outcome = 'uphold';
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Resolve UC arbitration'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: outcome,
                      items: const [
                        DropdownMenuItem(
                            value: 'uphold', child: Text('Uphold contract')),
                        DropdownMenuItem(
                            value: 'void', child: Text('Void and refund')),
                      ],
                      onChanged: (value) =>
                          setState(() => outcome = value ?? outcome)),
                  TextField(
                      controller: resolution,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Resolution (10–1000 characters)')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        if (resolution.text.trim().length < 10) return;
                        await action(() => const EarthApi().resolveContract(
                            contractId, outcome, resolution.text));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Resolve')),
                ],
              )));
}
