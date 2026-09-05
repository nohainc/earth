import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/consequence_preview_card.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showFormationComposer(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  required bool city,
  String? communityId,
  String? cityId,
}) async {
  final name = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        city ? 'Form a City' : 'Form a Corporation',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: name,
        autofocus: true,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: city ? 'City name' : 'Corporation name',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Submit',
          onPressed: () async {
            final selectedName = name.text.trim();
            if (selectedName.length < 2) return;
            Navigator.pop(dialogContext);
            await action(() => city
                ? const EarthApi().createCity(selectedName, communityId)
                : const EarthApi().createCorporation(selectedName, cityId ?? 'CITY-0084'));
          },
        ),
      ],
    ),
  );
}

Future<void> showCommunityComposer(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final name = TextEditingController();
  final description = TextEditingController();
  final question = TextEditingController();
  String admissionPolicy = 'open';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedName = name.text.trim();
        final selectedDesc = description.text.trim();
        final selectedQuestion = question.text.trim();
        final isValid = selectedName.length >= 3 &&
            selectedDesc.isNotEmpty &&
            (admissionPolicy != 'approval' || selectedQuestion.isNotEmpty);

        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Row(
            children: [
              Icon(Icons.add_business_outlined, color: context.primaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Found New Community',
                  style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Community Name (Required)',
                      labelStyle: context.widgetFooterStyle,
                      hintText: 'e.g. Carthage Makers Guild',
                      hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.primaryColor),
                      ),
                      filled: true,
                      fillColor: context.surfaceColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 4,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Manifesto & Purpose (Required)',
                      labelStyle: context.widgetFooterStyle,
                      hintText: 'What is the goal and purpose of this community?',
                      hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.primaryColor),
                      ),
                      filled: true,
                      fillColor: context.surfaceColor,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ADMISSION POLICY',
                    style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: admissionPolicy == 'open',
                          label: 'OPEN ACCESS policy',
                          child: InkWell(
                            onTap: () => setDialogState(() => admissionPolicy = 'open'),
                            borderRadius: BorderRadius.circular(context.radiusControl),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(context.radiusControl),
                                border: Border.all(
                                  color: admissionPolicy == 'open'
                                      ? context.primaryColor
                                      : context.subtleBorderColor,
                                  width: admissionPolicy == 'open' ? 2 : 1,
                                ),
                                color: admissionPolicy == 'open'
                                    ? context.primaryColor.withValues(alpha: 0.1)
                                    : Colors.transparent,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.lock_open_rounded,
                                          size: 14,
                                          color: admissionPolicy == 'open'
                                              ? context.primaryColor
                                              : context.mutedColor),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text('OPEN ACCESS',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.widgetTitleStyle.copyWith(
                                                color: context.primaryColor)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text('Instant Join',
                                      style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: admissionPolicy == 'approval',
                          label: 'APPROVAL REQUIRED policy',
                          child: InkWell(
                            onTap: () => setDialogState(() => admissionPolicy = 'approval'),
                            borderRadius: BorderRadius.circular(context.radiusControl),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(context.radiusControl),
                                border: Border.all(
                                  color: admissionPolicy == 'approval'
                                      ? context.primaryColor
                                      : context.subtleBorderColor,
                                  width: admissionPolicy == 'approval' ? 2 : 1,
                                ),
                                color: admissionPolicy == 'approval'
                                    ? context.primaryColor.withValues(alpha: 0.1)
                                    : Colors.transparent,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.verified_user_outlined,
                                          size: 14,
                                          color: admissionPolicy == 'approval'
                                              ? context.primaryColor
                                              : context.mutedColor),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text('APPROVAL REQUIRED',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.widgetTitleStyle.copyWith(
                                                color: context.primaryColor)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text('Review Applicants',
                                      style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (admissionPolicy == 'approval') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: question,
                      minLines: 2,
                      maxLines: 3,
                      style: context.bodyStyle.copyWith(color: context.inkColor),
                      decoration: InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'Application Question / Requirement (Required)',
                        labelStyle: context.widgetFooterStyle,
                        hintText: 'What question should applicants answer when applying?',
                        hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.radiusControl),
                          borderSide: BorderSide(color: context.subtleBorderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.radiusControl),
                          borderSide: BorderSide(color: context.subtleBorderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.radiusControl),
                          borderSide: BorderSide(color: context.primaryColor),
                        ),
                        filled: true,
                        fillColor: context.surfaceColor,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'Found Community',
              variant: EarthButtonVariant.primary,
              onPressed: isValid
                  ? () async {
                      Navigator.pop(dialogContext);
                      await action(() => const EarthApi().createCommunity(
                            name: selectedName,
                            description: selectedDesc,
                            admissionPolicy: admissionPolicy,
                            applicationQuestion: admissionPolicy == 'approval' ? selectedQuestion : null,
                          ));
                    }
                  : null,
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showCommunityApplicationDialog(
  BuildContext context,
  Map<String, dynamic> community,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final id = community['id']?.toString() ?? 'COM-001';
  final name = community['name']?.toString() ?? 'Community';
  final rawQuestion = community['application_question']?.toString() ?? '';
  final question = rawQuestion.trim().isNotEmpty
      ? rawQuestion.trim()
      : 'Why would you like to join this community and what will you contribute?';

  final messageController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final answer = messageController.text.trim();
        final isValid = answer.isNotEmpty;

        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Row(
            children: [
              Icon(Icons.assignment_outlined, color: context.primaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Apply to $name',
                  style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusCard),
                      border: Border.all(color: context.subtleBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.help_outline_rounded, size: 14, color: context.primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              'COMMUNITY QUESTION',
                              style: context.widgetTitleStyle.copyWith(
                                color: context.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          question,
                          style: context.bodyStyle.copyWith(color: context.inkColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: messageController,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 5,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Your Answer / Application Note (Required)',
                      labelStyle: context.widgetFooterStyle,
                      hintText: 'Provide your response to the community...',
                      hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.subtleBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.radiusControl),
                        borderSide: BorderSide(color: context.primaryColor),
                      ),
                      filled: true,
                      fillColor: context.surfaceColor,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'SUBMIT APPLICATION',
              variant: EarthButtonVariant.primary,
              onPressed: isValid
                  ? () async {
                      Navigator.pop(dialogContext);
                      await action(() => const EarthApi().joinCommunity(
                            id,
                            applicationMessage: answer,
                          ));
                    }
                  : null,
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showCommunityDetailsDialog(
  BuildContext context,
  Map<String, dynamic> community,
  EarthState state,
  bool busy,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final id = community['id']?.toString() ?? 'COM-001';
  final name = community['name']?.toString() ?? 'Community';
  final founderName = community['founder_name']?.toString() ?? 'Founder';
  final description = community['description']?.toString() ?? '';
  final admissionPolicy = (community['admission_policy']?.toString() ?? 'open').toUpperCase();
  final myRole = community['my_role']?.toString();
  final isPending = community['my_request_status'] == 'pending';
  final members = asIntOr(community['member_count'], 12);
  final isOwner = myRole == 'founder';
  final isAdmin = myRole == 'admin';
  final isMember = isOwner || isAdmin || myRole == 'member';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.groups_rounded, color: context.primaryColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: context.topicTitleStyle.copyWith(color: context.primaryColor),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'MANIFESTO & PURPOSE',
                style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Text(
                  description.isNotEmpty ? description : 'No specific manifesto provided for this community.',
                  style: context.bodyStyle.copyWith(color: context.inkColor),
                ),
              ),
              const SizedBox(height: 16),
              EarthMetricGrid(
                metrics: [
                  EarthMetricTile(
                    label: 'FOUNDED BY',
                    value: founderName,
                    subtitle: 'Community Creator',
                    icon: Icons.person_outline_rounded,
                  ),
                  EarthMetricTile(
                    label: 'MEMBERS',
                    value: '$members',
                    subtitle: 'Citizens active',
                    icon: Icons.groups_outlined,
                  ),
                  EarthMetricTile(
                    label: 'ADMISSION',
                    value: admissionPolicy,
                    subtitle: 'Entry policy',
                    icon: Icons.policy_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CLOSE', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        if (isOwner || isAdmin) ...[
          EarthButton(
            label: 'MANAGE COMMUNITY',
            icon: Icons.settings_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: busy
                ? null
                : () {
                    Navigator.pop(dialogContext);
                    showCommunityManageDialog(context, community, state, action);
                  },
          ),
        ] else if (isMember) ...[
          EarthButton(
            label: 'LEAVE',
            variant: EarthButtonVariant.danger,
            onPressed: busy
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi().leaveCommunity(id));
                  },
          ),
        ] else if (isPending) ...[
          EarthButton(
            label: 'CANCEL APPLICATION',
            variant: EarthButtonVariant.danger,
            onPressed: busy
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi().leaveCommunity(id));
                  },
          ),
        ] else ...[
          EarthButton(
            label: admissionPolicy == 'APPROVAL' ? 'APPLY TO JOIN' : 'JOIN COMMUNITY',
            variant: EarthButtonVariant.primary,
            onPressed: busy
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    if (admissionPolicy == 'APPROVAL') {
                      showCommunityApplicationDialog(context, community, action);
                    } else {
                      await action(() => const EarthApi().joinCommunity(id));
                    }
                  },
          ),
        ],
      ],
    ),
  );
}

Future<void> showCommunityManageDialog(
  BuildContext context,
  Map<String, dynamic> community,
  EarthState state,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final id = community['id']?.toString() ?? 'COM-001';
  final name = community['name']?.toString() ?? 'Community';
  final myRole = community['my_role']?.toString();
  final isOwner = myRole == 'founder';
  final descController = TextEditingController(text: community['description']?.toString() ?? '');
  final questionController = TextEditingController(text: community['application_question']?.toString() ?? '');
  String admissionPolicy = community['admission_policy']?.toString() ?? 'open';

  List<dynamic> members = [];
  List<dynamic> requests = [];
  bool loading = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        if (loading) {
          Future.microtask(() async {
            try {
              final memRes = await const EarthApi().listCommunityMembers(id);
              members = memRes['members'] as List<dynamic>? ?? [];
              if (admissionPolicy == 'approval') {
                final reqRes = await const EarthApi().listCommunityRequests(id);
                requests = reqRes['requests'] as List<dynamic>? ?? [];
              }
            } catch (_) {}
            setDialogState(() => loading = false);
          });
        }

        return DefaultTabController(
          length: isOwner ? 4 : 3,
          child: AlertDialog(
            backgroundColor: context.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.radiusPanel),
              side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_outlined, color: context.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Manage $name',
                        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  isScrollable: true,
                  indicatorColor: context.primaryColor,
                  labelColor: context.primaryColor,
                  unselectedLabelColor: context.mutedColor,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: [
                    const Tab(text: 'SETTINGS'),
                    Tab(text: 'MEMBERS (${members.length})'),
                    Tab(text: 'REQUESTS (${requests.length})'),
                    if (isOwner) const Tab(text: 'DANGER ZONE'),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 380,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        // Tab 1: Settings
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: descController,
                                minLines: 3,
                                maxLines: 4,
                                style: context.bodyStyle.copyWith(color: context.inkColor),
                                decoration: InputDecoration(
                                  alignLabelWithHint: true,
                                  labelText: 'Manifesto & Description',
                                  labelStyle: context.widgetFooterStyle,
                                  hintText: 'Describe the core mission and goals of this community...',
                                  hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(context.radiusControl),
                                    borderSide: BorderSide(color: context.subtleBorderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(context.radiusControl),
                                    borderSide: BorderSide(color: context.subtleBorderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(context.radiusControl),
                                    borderSide: BorderSide(color: context.primaryColor),
                                  ),
                                  filled: true,
                                  fillColor: context.surfaceColor,
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text('ADMISSION POLICY',
                                  style: context.widgetTitleStyle.copyWith(color: context.mutedColor)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setDialogState(() => admissionPolicy = 'open'),
                                      borderRadius: BorderRadius.circular(context.radiusControl),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: admissionPolicy == 'open'
                                                ? context.primaryColor
                                                : context.subtleBorderColor,
                                            width: admissionPolicy == 'open' ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(context.radiusControl),
                                          color: admissionPolicy == 'open'
                                              ? context.primaryColor.withValues(alpha: 0.1)
                                              : Colors.transparent,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.lock_open_rounded,
                                                    size: 14,
                                                    color: admissionPolicy == 'open'
                                                        ? context.primaryColor
                                                        : context.mutedColor),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text('OPEN ACCESS',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: context.widgetTitleStyle.copyWith(
                                                          color: context.primaryColor)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text('Instant Join',
                                                style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setDialogState(() => admissionPolicy = 'approval'),
                                      borderRadius: BorderRadius.circular(context.radiusControl),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: admissionPolicy == 'approval'
                                                ? context.primaryColor
                                                : context.subtleBorderColor,
                                            width: admissionPolicy == 'approval' ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(context.radiusControl),
                                          color: admissionPolicy == 'approval'
                                              ? context.primaryColor.withValues(alpha: 0.1)
                                              : Colors.transparent,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.verified_user_outlined,
                                                    size: 14,
                                                    color: admissionPolicy == 'approval'
                                                        ? context.primaryColor
                                                        : context.mutedColor),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text('APPROVAL REQUIRED',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: context.widgetTitleStyle.copyWith(
                                                          color: context.primaryColor)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text('Review Applicants',
                                                style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (admissionPolicy == 'approval') ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: questionController,
                                  minLines: 2,
                                  maxLines: 3,
                                  style: context.bodyStyle.copyWith(color: context.inkColor),
                                  decoration: InputDecoration(
                                    alignLabelWithHint: true,
                                    labelText: 'Application Question / Requirement',
                                    labelStyle: context.widgetFooterStyle,
                                    hintText: 'What question should applicants answer when applying?',
                                    hintStyle: context.bodyStyle.copyWith(color: context.mutedColor),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(context.radiusControl),
                                      borderSide: BorderSide(color: context.subtleBorderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(context.radiusControl),
                                      borderSide: BorderSide(color: context.subtleBorderColor),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(context.radiusControl),
                                      borderSide: BorderSide(color: context.primaryColor),
                                    ),
                                    filled: true,
                                    fillColor: context.surfaceColor,
                                    contentPadding: const EdgeInsets.all(12),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              EarthButton(
                                label: 'SAVE SETTINGS',
                                variant: EarthButtonVariant.primary,
                                onPressed: () async {
                                  Navigator.pop(dialogContext);
                                  await action(() => const EarthApi().updateCommunity(
                                        communityId: id,
                                        description: descController.text.trim(),
                                        admissionPolicy: admissionPolicy,
                                        applicationQuestion: admissionPolicy == 'approval' ? questionController.text.trim() : null,
                                      ));
                                },
                              ),
                            ],
                          ),
                        ),
                        // Tab 2: Members
                        members.isEmpty
                            ? const Center(child: Text('No members found.'))
                            : ListView.builder(
                                itemCount: members.length,
                                itemBuilder: (context, idx) {
                                  final m = members[idx] as Map<String, dynamic>;
                                  final hId = m['human_id']?.toString() ?? '';
                                  final hName = m['human_name']?.toString() ?? hId;
                                  final role = (m['role']?.toString() ?? 'member').toUpperCase();
                                  final isMFounder = role == 'FOUNDER';

                                  return ListTile(
                                    title: Text(hName, style: context.bodyStyle.copyWith(fontSize: 13)),
                                    subtitle: Text('$hId · Joined Day ${m['joined_game_day']}',
                                        style: context.widgetFooterStyle.copyWith(fontSize: 11, color: context.mutedColor)),
                                    trailing: Wrap(
                                      spacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        EarthBadge(
                                          label: role,
                                          variant: isMFounder
                                              ? EarthBadgeVariant.primary
                                              : role == 'ADMIN'
                                                  ? EarthBadgeVariant.secondary
                                                  : EarthBadgeVariant.neutral,
                                        ),
                                        if (isOwner && !isMFounder) ...[
                                          if (role == 'ADMIN')
                                            EarthButton(
                                              label: 'DEMOTE',
                                              variant: EarthButtonVariant.ghost,
                                              onPressed: () async {
                                                await const EarthApi().setCommunityMemberRole(
                                                  communityId: id,
                                                  targetHumanId: hId,
                                                  role: 'member',
                                                );
                                                setDialogState(() => loading = true);
                                              },
                                            )
                                          else
                                            EarthButton(
                                              label: 'MAKE ADMIN',
                                              variant: EarthButtonVariant.secondary,
                                              onPressed: () async {
                                                await const EarthApi().setCommunityMemberRole(
                                                  communityId: id,
                                                  targetHumanId: hId,
                                                  role: 'admin',
                                                );
                                                setDialogState(() => loading = true);
                                              },
                                            ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                        // Tab 3: Requests
                        requests.isEmpty
                            ? const Center(child: Text('No pending membership requests.'))
                            : ListView.builder(
                                itemCount: requests.length,
                                itemBuilder: (context, idx) {
                                  final req = requests[idx] as Map<String, dynamic>;
                                  final reqId = req['id']?.toString() ?? '';
                                  final applicant = req['human_name']?.toString() ?? req['human_id']?.toString() ?? '';
                                  final appMsg = req['application_message']?.toString() ?? '';

                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: context.surfaceColor,
                                      borderRadius: BorderRadius.circular(context.radiusCard),
                                      border: Border.all(color: context.subtleBorderColor),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(applicant, style: context.bodyStyle.copyWith(fontSize: 13, fontWeight: FontWeight.bold)),
                                            Text('Day ${req['requested_game_day']}',
                                                style: TextStyle(fontSize: 11, color: context.mutedColor)),
                                          ],
                                        ),
                                        if (appMsg.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: context.panelColor,
                                              borderRadius: BorderRadius.circular(context.radiusControl),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.format_quote_rounded, size: 14, color: context.primaryColor),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    appMsg,
                                                    style: TextStyle(fontSize: 12, color: context.inkColor, fontStyle: FontStyle.italic),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            EarthButton(
                                              label: 'REJECT',
                                              variant: EarthButtonVariant.danger,
                                              onPressed: () async {
                                                final reasonController = TextEditingController();
                                                final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  builder: (rejectCtx) => AlertDialog(
                                                    backgroundColor: context.panelColor,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(context.radiusPanel),
                                                      side: BorderSide(color: context.dangerColor.withValues(alpha: .35)),
                                                    ),
                                                    title: Text(
                                                      'Decline Membership Request',
                                                      style: context.topicTitleStyle.copyWith(color: context.dangerColor),
                                                    ),
                                                    content: SizedBox(
                                                      width: 400,
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                                        children: [
                                                          Text(
                                                            'Please provide a reason for declining $applicant\'s application:',
                                                            style: context.bodyStyle.copyWith(fontSize: 13),
                                                          ),
                                                          const SizedBox(height: 12),
                                                          TextField(
                                                            controller: reasonController,
                                                            autofocus: true,
                                                            maxLines: 3,
                                                            style: context.bodyStyle.copyWith(fontSize: 13),
                                                            decoration: InputDecoration(
                                                              labelText: 'Reason for Rejection (Required)',
                                                              labelStyle: context.widgetFooterStyle.copyWith(fontSize: 12),
                                                              hintText: 'e.g. Guild capacity full, requirements not met...',
                                                              hintStyle: context.bodyStyle.copyWith(fontSize: 12, color: context.mutedColor),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(rejectCtx, false),
                                                        child: Text('CANCEL', style: TextStyle(color: context.mutedColor)),
                                                      ),
                                                      EarthButton(
                                                        label: 'CONFIRM DECLINE',
                                                        variant: EarthButtonVariant.danger,
                                                        onPressed: () {
                                                          if (reasonController.text.trim().isNotEmpty) {
                                                            Navigator.pop(rejectCtx, true);
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (confirmed == true) {
                                                  await const EarthApi().decideCommunityRequest(
                                                    communityId: id,
                                                    requestId: reqId,
                                                    action: 'reject',
                                                    rejectionReason: reasonController.text.trim(),
                                                  );
                                                  setDialogState(() => loading = true);
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            EarthButton(
                                              label: 'APPROVE',
                                              variant: EarthButtonVariant.primary,
                                              onPressed: () async {
                                                await const EarthApi().decideCommunityRequest(
                                                  communityId: id,
                                                  requestId: reqId,
                                                  action: 'approve',
                                                );
                                                setDialogState(() => loading = true);
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                        // Tab 4: Danger Zone
                        if (isOwner)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 48, color: context.dangerColor),
                                const SizedBox(height: 12),
                                Text(
                                  'Disband Community',
                                  textAlign: TextAlign.center,
                                  style: context.topicTitleStyle.copyWith(color: context.dangerColor),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Disbanding is irreversible. All community records and memberships will be dissolved permanently.',
                                  textAlign: TextAlign.center,
                                  style: context.widgetFooterStyle.copyWith(color: context.mutedColor),
                                ),
                                const SizedBox(height: 24),
                                EarthButton(
                                  label: 'DISBAND COMMUNITY',
                                  variant: EarthButtonVariant.danger,
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    await action(() => const EarthApi().disbandCommunity(id));
                                  },
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
                child: Text('CLOSE', style: context.controlStyle.copyWith(color: context.mutedColor)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> showTaxCharterDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String institutionId, {
  bool corporation = false,
}) async {
  final income = TextEditingController(text: '5.0');
  final sales = TextEditingController(text: '2.0');
  final corporate = TextEditingController(text: '10.0');
  final property = TextEditingController(text: '1.0');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final parsedIncome = double.tryParse(income.text.trim()) ?? 5.0;
        final parsedCorporate = double.tryParse(corporate.text.trim()) ?? 10.0;
        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            corporation ? 'Set corporation tax charter' : 'Set city tax charter',
            style: context.topicTitleStyle.copyWith(color: context.primaryColor),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Rates are entered as percentages (0–30%). Stored in exact basis points.',
                    style: context.widgetFooterStyle,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: income,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Income tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sales,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Sales tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: corporate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Corporate tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: property,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Property tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  ConsequencePreviewCard(
                    consequence: DecisionConsequence.municipalTaxAdjustment(
                      cityName: institutionId,
                      oldRatePct: 5.0,
                      newRatePct: (parsedIncome + parsedCorporate) / 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'SAVE CHARTER',
              onPressed: () async {
                final rates = [
                  double.tryParse(income.text.trim()),
                  double.tryParse(sales.text.trim()),
                  double.tryParse(corporate.text.trim()),
                  double.tryParse(property.text.trim()),
                ];
                if (rates.any((value) => value == null || value < 0 || value > 30)) {
                  return;
                }
                Navigator.pop(dialogContext);
                await action(() => corporation
                    ? const EarthApi().setCorporationTaxCharter(
                        corporationId: institutionId,
                        incomeTaxBps: (rates[0]! * 100).round(),
                        salesTaxBps: (rates[1]! * 100).round(),
                        corporateTaxBps: (rates[2]! * 100).round(),
                        propertyTaxBps: (rates[3]! * 100).round(),
                      )
                    : const EarthApi().setCityTaxCharter(
                        cityId: institutionId,
                        incomeTaxBps: (rates[0]! * 100).round(),
                        salesTaxBps: (rates[1]! * 100).round(),
                        corporateTaxBps: (rates[2]! * 100).round(),
                        propertyTaxBps: (rates[3]! * 100).round(),
                      ));
              },
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showAdmissionPolicyDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String corporationId, {
  String currentPolicy = 'open',
}) async {
  var policy = currentPolicy == 'approval' ? 'approval' : 'open';
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
          'Corporation Admission Policy',
          style: context.topicTitleStyle.copyWith(color: context.primaryColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'open',
              groupValue: policy,
              activeColor: context.primaryColor,
              onChanged: (value) => setState(() => policy = value!),
              title: Text('Open membership', style: context.widgetValueStyle),
              subtitle: Text('New members join the capital city immediately.', style: context.widgetFooterStyle),
            ),
            RadioListTile<String>(
              value: 'approval',
              groupValue: policy,
              activeColor: context.primaryColor,
              onChanged: (value) => setState(() => policy = value!),
              title: Text('Admin approval', style: context.widgetValueStyle),
              subtitle: Text('Administrators review membership requests.', style: context.widgetFooterStyle),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
          ),
          EarthButton(
            label: 'SAVE POLICY',
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().setCorporationAdmissionPolicy(
                    corporationId: corporationId,
                    policy: policy,
                  ));
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> showCorporationWithCapitalDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final corporation = TextEditingController();
  final capital = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Found a Corporation',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your corporation and its capital city are founded together. You become the first member and city resident.',
              style: context.widgetFooterStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: corporation,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Corporation name',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: capital,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Capital city name',
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
          label: 'FOUND CORPORATION',
          onPressed: () async {
            final corporationName = corporation.text.trim();
            final cityName = capital.text.trim();
            if (corporationName.length < 2 || cityName.length < 2) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().createCorporationWithCapital(
                  corporationName: corporationName,
                  cityName: cityName,
                ));
          },
        ),
      ],
    ),
  );
}

Future<void> showCityChangeDialog(
  BuildContext context,
  EarthState state,
  String currentCityId,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final corporationId = state.membership?['corporation_id']?.toString();
  final cities = (state.rankings['cities'] is List
          ? state.rankings['cities'] as List
          : const <dynamic>[])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where((row) => corporationId == null || row['corporation_id']?.toString() == corporationId)
      .toList();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Change City Jurisdiction',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: SizedBox(
        width: 520,
        child: cities.isEmpty
            ? const EarthEmptyState(
                message: 'No cities in your current corporation network are available.',
                icon: Icons.location_city_outlined,
              )
            : EarthDataList(
                children: cities.map((city) {
                  final id = city['id']?.toString() ?? '';
                  final rules = city['rules'] is Map
                      ? Map<String, dynamic>.from(city['rules'] as Map)
                      : const <String, dynamic>{};
                  final income = asDouble(rules['incomeTaxBps']);
                  final tax = income == null
                      ? 'Taxes: Default'
                      : 'Income tax: ${(income / 100).toStringAsFixed(2)}%';
                  final isCurrent = id == currentCityId;

                  return EarthDataRow(
                    title: city['name']?.toString() ?? id,
                    subtitle: '${city['residents'] ?? 0} residents · $tax',
                    leading: Icon(
                      Icons.location_city_outlined,
                      size: context.iconSize,
                      color: isCurrent ? context.primaryColor : context.mutedColor,
                    ),
                    trailing: isCurrent
                        ? const EarthBadge(label: 'CURRENT JURISDICTION')
                        : EarthButton(
                            label: 'MOVE',
                            variant: EarthButtonVariant.primary,
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await action(() => const EarthApi().joinCity(cityId: id));
                            },
                          ),
                  );
                }).toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CLOSE', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
      ],
    ),
  );
}

/// Displays comprehensive constitutional rules, tax rates, and perks of a corporation.
Future<void> showCorporationCharterDialog(
  BuildContext context,
  Map<String, dynamic> corporation,
  EarthState state, {
  bool isMember = false,
  VoidCallback? onJoin,
}) async {
  final id = corporation['id']?.toString() ?? '';
  final name = corporation['name']?.toString() ?? id;
  final capitalCity = corporation['capital_city_name']?.toString() ?? 'Capital City';
  final members = asIntOr(corporation['member_count'], 0);
  final cityCount = asIntOr(corporation['city_count'], 1);
  final treasury = asDouble(corporation['treasury']) ?? 0.0;
  final admissionPolicy = (corporation['admission_policy']?.toString() ?? 'open').toUpperCase();

  final rules = corporation['rules'] is Map
      ? Map<String, dynamic>.from(corporation['rules'] as Map)
      : const <String, dynamic>{};

  final incomeTaxBps = asIntOr(rules['incomeTaxBps'], 200);
  final salesTaxBps = asIntOr(rules['salesTaxBps'], 100);
  final corporateTaxBps = asIntOr(rules['corporateTaxBps'], 250);
  final propertyTaxBps = asIntOr(rules['propertyTaxBps'], 150);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.account_balance_outlined, color: context.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name Charter & Constitution',
              style: context.topicTitleStyle.copyWith(color: context.primaryColor),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CONSTITUTIONAL TAX SCHEDULE',
                style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
              ),
              const SizedBox(height: 8),
              EarthMetricGrid(
                metrics: [
                  EarthMetricTile(
                    label: 'INCOME TAX',
                    value: '${(incomeTaxBps / 100).toStringAsFixed(1)}%',
                    subtitle: 'Applied to member income',
                    icon: Icons.percent_outlined,
                  ),
                  EarthMetricTile(
                    label: 'MARKET SALES FEE',
                    value: '${(salesTaxBps / 100).toStringAsFixed(1)}%',
                    subtitle: 'Transaction levy',
                    icon: Icons.storefront_outlined,
                  ),
                  EarthMetricTile(
                    label: 'CORPORATE TAX',
                    value: '${(corporateTaxBps / 100).toStringAsFixed(1)}%',
                    subtitle: 'Enterprise revenue levy',
                    icon: Icons.domain,
                  ),
                  EarthMetricTile(
                    label: 'PROPERTY LEVY',
                    value: '${(propertyTaxBps / 100).toStringAsFixed(1)}%',
                    subtitle: 'Asset base tax',
                    icon: Icons.home_work_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'GOVERNANCE & ECONOMIC STANDING',
                style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
              ),
              const SizedBox(height: 8),
              EarthMetricGrid(
                metrics: [
                  EarthMetricTile(
                    label: 'CAPITAL CITY',
                    value: capitalCity,
                    subtitle: 'Administrative Seat',
                    icon: Icons.location_city_outlined,
                  ),
                  EarthMetricTile(
                    label: 'MEMBER CITIZENS',
                    value: '$members',
                    subtitle: 'Affiliated Population',
                    icon: Icons.groups_outlined,
                  ),
                  EarthMetricTile(
                    label: 'CORPORATE TREASURY',
                    value: '${treasury.toStringAsFixed(0)} C',
                    subtitle: 'Liquid Capital Reserves',
                    icon: Icons.savings_outlined,
                  ),
                  EarthMetricTile(
                    label: 'MUNICIPAL NETWORK',
                    value: '$cityCount Cities',
                    subtitle: 'Chartered Territories',
                    icon: Icons.hub_outlined,
                  ),
                  EarthMetricTile(
                    label: 'ADMISSION POLICY',
                    value: admissionPolicy,
                    subtitle: 'Membership Rule',
                    icon: Icons.shield_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'AFFILIATION BENEFITS & CONSTITUTION',
                style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBenefitRow(
                      context,
                      Icons.shield_outlined,
                      'Corporate Tax Protection',
                      'Members enjoy capped municipal tax rates ($incomeTaxBps bps income / $salesTaxBps bps sales) across all $cityCount affiliated cities.',
                    ),
                    const SizedBox(height: 10),
                    _buildBenefitRow(
                      context,
                      Icons.biotech_outlined,
                      'Shared Technology & Patents',
                      'Access proprietary corporate technology shares without paying external licensing premiums.',
                    ),
                    const SizedBox(height: 10),
                    _buildBenefitRow(
                      context,
                      Icons.how_to_vote_outlined,
                      'Shareholder Democratic Franchise',
                      'Vote on corporate leadership, municipal tax updates, and city territorial adoptions.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CLOSE', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        if (!isMember && onJoin != null)
          EarthButton(
            label: 'AFFILIATE WITH $name',
            variant: EarthButtonVariant.primary,
            onPressed: () {
              Navigator.pop(dialogContext);
              onJoin();
            },
          ),
      ],
    ),
  );
}

Widget _buildBenefitRow(BuildContext context, IconData icon, String title, String description) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: context.primaryColor),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.widgetTitleStyle.copyWith(color: context.primaryColor)),
            const SizedBox(height: 2),
            Text(description, style: context.bodyStyle.copyWith(color: context.inkColor.withValues(alpha: .85))),
          ],
        ),
      ),
    ],
  );
}
