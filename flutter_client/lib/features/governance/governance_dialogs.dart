import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

Future<void> showProposalComposer(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  String institutionId = 'OUC-001',
  String scopeLabel = 'UC',
}) async {
  final title = TextEditingController();
  final body = TextEditingController();
  final targetRate = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Create $scopeLabel proposal',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              maxLength: 140,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Title (8–140 characters)',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              minLines: 4,
              maxLines: 7,
              maxLength: 4000,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Policy proposal (20–4000 characters)',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Optional UC finance rate (0–0.25)',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Submit proposal',
          onPressed: () async {
            if (title.text.trim().length < 8 || body.text.trim().length < 20) {
              return;
            }
            final rate = targetRate.text.trim().isEmpty
                ? null
                : double.tryParse(targetRate.text.trim());
            if (targetRate.text.trim().isNotEmpty && (rate == null || rate < 0 || rate > .25)) {
              return;
            }
            await action(() => const EarthApi().createProposal(
                  title.text.trim(),
                  body.text.trim(),
                  institutionId: institutionId,
                  targetCategory: rate == null ? null : 'finance',
                  targetRate: rate,
                ));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
      ],
    ),
  );
}

Future<void> showDelegateDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String roleId,
) async {
  final delegate = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Delegate authority',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: delegate,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: 'Active Human ID',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Delegate',
          onPressed: () async {
            if (delegate.text.trim().isEmpty) return;
            await action(() => const EarthApi().delegateRole(roleId, delegate.text.trim()));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
      ],
    ),
  );
}

Future<void> showChallengeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String proposalId,
) async {
  final reason = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'File constitutional challenge',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: reason,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: 'Constitutional grounds (10–2000 characters)',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'File challenge',
          variant: EarthButtonVariant.danger,
          onPressed: () async {
            if (reason.text.trim().length < 10) return;
            await action(() => const EarthApi().challengeProposal(proposalId, reason.text.trim()));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
      ],
    ),
  );
}

Future<void> showAppealRulingDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String proposalId,
) async {
  final rationale = TextEditingController();
  var ruling = 'uphold';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: context.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        title: Text(
          'Issue High Court ruling',
          style: context.topicTitleStyle.copyWith(color: context.primaryColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: ruling,
              dropdownColor: context.surfaceColor,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              items: const [
                DropdownMenuItem(value: 'uphold', child: Text('Uphold proposal')),
                DropdownMenuItem(value: 'void', child: Text('Void proposal')),
              ],
              onChanged: (value) => setState(() => ruling = value ?? ruling),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rationale,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Judicial rationale (10–2000 characters)',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
          ),
          EarthButton(
            label: 'Issue ruling',
            onPressed: () async {
              if (rationale.text.trim().length < 10) return;
              await action(() => const EarthApi().resolveConstitutionalAppeal(
                    proposalId,
                    ruling,
                    rationale.text.trim(),
                  ));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> showDisputeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String contractId,
) async {
  final reason = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Open UC arbitration',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: reason,
        maxLines: 4,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: 'Reason (10–1000 characters)',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Submit dispute',
          variant: EarthButtonVariant.danger,
          onPressed: () async {
            if (reason.text.trim().length < 10) return;
            await action(() => const EarthApi().disputeContract(contractId, reason.text.trim()));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
        ),
      ],
    ),
  );
}

Future<void> showResolveDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String contractId,
) async {
  final resolution = TextEditingController();
  var outcome = 'uphold';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: context.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        title: Text(
          'Resolve UC arbitration',
          style: context.topicTitleStyle.copyWith(color: context.primaryColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: outcome,
              dropdownColor: context.surfaceColor,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              items: const [
                DropdownMenuItem(value: 'uphold', child: Text('Uphold contract')),
                DropdownMenuItem(value: 'void', child: Text('Void and refund')),
              ],
              onChanged: (value) => setState(() => outcome = value ?? outcome),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: resolution,
              maxLines: 4,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Resolution (10–1000 characters)',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
          ),
          EarthButton(
            label: 'Resolve',
            onPressed: () async {
              if (resolution.text.trim().length < 10) return;
              await action(() => const EarthApi().resolveContract(
                    contractId,
                    outcome,
                    resolution.text.trim(),
                  ));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
          ),
        ],
      ),
    ),
  );
}
