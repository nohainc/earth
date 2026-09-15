import 'package:flutter/material.dart';

import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

/// Player-facing workflow for collaborative public goods. The server remains
/// authoritative for proposal approval, matching limits, escrow, and settlement.
class PublicProjectsPanel extends StatefulWidget {
  final EarthState state;
  final Map<String, dynamic> personalFinanceData;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const PublicProjectsPanel({
    super.key,
    required this.state,
    required this.personalFinanceData,
    required this.busy,
    required this.action,
  });

  @override
  State<PublicProjectsPanel> createState() => _PublicProjectsPanelState();
}

class _PublicProjectsPanelState extends State<PublicProjectsPanel> {
  List<Map<String, dynamic>> _projects = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : const [];

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await const EarthApi().listPublicProjects();
      if (!mounted) return;
      setState(() {
        _projects = _rows(response['projects']);
        _loading = false;
        _error = response['ok'] == false ? response['error']?.toString() : null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  String? get _walletAccountId {
    final accounts = widget.personalFinanceData['accounts'];
    if (accounts is! List) return null;
    for (final raw in accounts) {
      if (raw is! Map) continue;
      final code =
          (raw['asset_code'] ?? raw['assetCode'])?.toString().toUpperCase();
      final type =
          (raw['account_type'] ?? raw['accountType'])?.toString().toUpperCase();
      if (code == 'CREDIT' && type == 'WALLET') {
        return raw['account_id']?.toString();
      }
    }
    return null;
  }

  Future<void> _contribute(Map<String, dynamic> project) async {
    final accountId = _walletAccountId;
    if (accountId == null) {
      _showMessage(
          'Your CREDIT wallet is not available in the current financial snapshot.');
      return;
    }
    final amount = await _amountDialog('CONTRIBUTE TO PROJECT');
    if (amount == null || !mounted) return;
    await widget.action(() async {
      await const EarthApi().contributeToPublicProject(
        projectId: project['id'].toString(),
        sourceAccountId: accountId,
        amountUnits: amount,
      );
      return const EarthApi().world();
    });
    if (mounted) await _load();
  }

  Future<String?> _amountDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Amount in CREDIT units'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^\d+$').hasMatch(value) && value != '0') {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _create() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => const _CreatePublicProjectDialog(),
    );
    if (result == null || !mounted) return;
    await widget.action(() async {
      await const EarthApi().createPublicProject(
        name: result['name']!,
        description: result['description']!,
        beneficiaryType: result['beneficiaryType']!,
        beneficiaryId: result['beneficiaryId']!,
        recipientAccountId: result['recipientAccountId']!,
        targetUnits: result['targetUnits']!,
        deadlineGameDay: int.parse(result['deadlineGameDay']!),
        matchingPoolAuthorizedUnits: result['matchingPoolAuthorizedUnits']!,
        proposalId: result['proposalId']!,
      );
      return const EarthApi().world();
    });
    if (mounted) await _load();
  }

  Future<void> _openProject(Map<String, dynamic> project) async {
    final id = project['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    try {
      final response = await const EarthApi().getPublicProject(id);
      final detail = response['project'] is Map
          ? Map<String, dynamic>.from(response['project'] as Map)
          : project;
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(detail['name']?.toString() ?? id),
                content: Text(
                    'Status: ${detail['status'] ?? '—'}\n\nFunding: ${detail['contribution_units'] ?? '0'} / ${detail['target_units'] ?? '—'} C\nMatching funded: ${detail['matching_pool_funded_units'] ?? '0'} C\nProjected match: ${detail['projected_match_units'] ?? '0'} C\nSupporters: ${detail['supporter_count'] ?? '0'}\n\n${detail['description'] ?? ''}'),
                actions: [
                  if ((detail['status'] ?? '').toString().toUpperCase() ==
                      'OPEN')
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _fundMatching(detail);
                        },
                        child: const Text('FUND MATCHING')),
                  if ((detail['status'] ?? '').toString().toUpperCase() !=
                      'SETTLED')
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _settle(detail);
                        },
                        child: const Text('SETTLE WHEN DUE')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('CLOSE')),
                ],
              ));
    } catch (error) {
      _showMessage('Project details unavailable: $error');
    }
  }

  Future<void> _fundMatching(Map<String, dynamic> project) async {
    final amount = await _amountDialog('FUND MATCHING POOL');
    final proposal =
        project['proposal_id']?.toString() ?? project['proposalId']?.toString();
    if (amount == null || proposal == null || proposal.isEmpty || !mounted) {
      return;
    }
    try {
      await widget.action(() => const EarthApi()
          .fundPublicProjectMatchingPool(
              projectId: project['id'].toString(),
              proposalId: proposal,
              amountUnits: amount)
          .then((_) => const EarthApi().world()));
      await _load();
    } catch (error) {
      _showMessage('Matching fund failed: $error');
    }
  }

  Future<void> _settle(Map<String, dynamic> project) async {
    try {
      await widget.action(() => const EarthApi()
          .settlePublicProject(project['id'].toString())
          .then((_) => const EarthApi().world()));
      await _load();
    } catch (error) {
      _showMessage('Settlement is not available yet: $error');
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          tag: 'COLLECTIVE CAPITAL',
          status: _loading ? 'LOADING' : '${_projects.length} ACTIVE PROJECTS',
          statusColor: context.primaryColor,
          infoTitle: 'PUBLIC PROJECTS',
          infoDescription:
              'Collaborative projects use approved proposals, capped matching funds, House contributions, escrow, and auditable settlement. Funding is never created by the client.',
          title: 'PUBLIC PROJECTS',
          subtitle:
              'Coordinate infrastructure and public goods with other Houses',
          actions: [
            EarthButton(
                label: 'CREATE PROJECT',
                icon: Icons.add_task_outlined,
                onPressed: widget.busy || _loading ? null : _create),
            EarthButton(
                label: 'REFRESH',
                icon: Icons.refresh,
                onPressed: _loading ? null : _load),
          ],
          metrics: [
            CockpitMetric(
                label: 'Active',
                value: '${_projects.length}',
                icon: Icons.construction_outlined,
                color: context.primaryColor),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null)
          EarthEmptyState(
              message: 'Project data unavailable: $_error',
              icon: Icons.sync_problem_outlined)
        else if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_projects.isEmpty)
          const EarthEmptyState(
              message: 'No public projects are currently published.',
              icon: Icons.construction_outlined)
        else
          EarthSection(
            title: 'PUBLISHED PROJECTS',
            showSurface: true,
            child: EarthDataList(
                children: _projects.map((project) {
              final target =
                  project['target_units'] ?? project['targetUnits'] ?? '—';
              final funded = project['funded_units'] ??
                  project['contributed_units'] ??
                  '0';
              final status =
                  (project['status'] ?? 'UNKNOWN').toString().toUpperCase();
              return EarthDataRow(
                title: project['name']?.toString() ??
                    project['id']?.toString() ??
                    'Public project',
                subtitle:
                    '${project['beneficiary_type'] ?? 'PUBLIC'} · $status · deadline day ${project['deadline_game_day'] ?? '—'}',
                secondarySubtitle:
                    '${project['description'] ?? 'No description published'} · funded $funded / $target C',
                leading: Icon(Icons.construction_outlined,
                    color: context.primaryColor),
                badges: [
                  EarthBadge(label: status, variant: EarthBadgeVariant.primary)
                ],
                trailing: Wrap(spacing: 4, children: [
                  TextButton(
                      onPressed: () => _openProject(project),
                      child: const Text('DETAILS')),
                  if (status == 'OPEN' && !widget.busy)
                    TextButton(
                        onPressed: () => _contribute(project),
                        child: const Text('CONTRIBUTE')),
                ]),
              );
            }).toList()),
          ),
      ],
    );
  }
}

class _CreatePublicProjectDialog extends StatefulWidget {
  const _CreatePublicProjectDialog();

  @override
  State<_CreatePublicProjectDialog> createState() =>
      _CreatePublicProjectDialogState();
}

class _CreatePublicProjectDialogState
    extends State<_CreatePublicProjectDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _beneficiaryId = TextEditingController();
  final _recipientAccountId = TextEditingController();
  final _target = TextEditingController();
  final _deadline = TextEditingController();
  final _matching = TextEditingController(text: '0');
  final _proposal = TextEditingController();
  String _beneficiaryType = 'TERRITORY';

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _beneficiaryId,
      _recipientAccountId,
      _target,
      _deadline,
      _matching,
      _proposal,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty &&
        _description.text.trim().isNotEmpty &&
        _beneficiaryId.text.trim().isNotEmpty &&
        _recipientAccountId.text.trim().isNotEmpty &&
        RegExp(r'^\d+$').hasMatch(_target.text.trim()) &&
        RegExp(r'^\d+$').hasMatch(_deadline.text.trim()) &&
        RegExp(r'^\d+$').hasMatch(_matching.text.trim()) &&
        _proposal.text.trim().isNotEmpty;
    Widget field(TextEditingController controller, String label,
            {TextInputType? type}) =>
        TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            keyboardType: type,
            decoration: InputDecoration(labelText: label));
    return AlertDialog(
      title: const Text('CREATE PUBLIC PROJECT'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(_name, 'Project name'),
          field(_description, 'Description'),
          DropdownButtonFormField<String>(
              value: _beneficiaryType,
              decoration: const InputDecoration(labelText: 'Beneficiary type'),
              items: const [
                DropdownMenuItem(value: 'TERRITORY', child: Text('Territory')),
                DropdownMenuItem(
                    value: 'ORGANIZATION', child: Text('Organization')),
                DropdownMenuItem(value: 'EARTH', child: Text('Earth')),
              ],
              onChanged: (value) =>
                  setState(() => _beneficiaryType = value ?? _beneficiaryType)),
          field(_beneficiaryId, 'Beneficiary ID'),
          field(_recipientAccountId, 'Recipient account ID'),
          field(_target, 'Target CREDIT units', type: TextInputType.number),
          field(_deadline, 'Deadline game day', type: TextInputType.number),
          field(_matching, 'Authorized matching CREDIT units',
              type: TextInputType.number),
          field(_proposal, 'Approved proposal ID'),
        ])),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: valid
                ? () => Navigator.pop(context, {
                      'name': _name.text.trim(),
                      'description': _description.text.trim(),
                      'beneficiaryType': _beneficiaryType,
                      'beneficiaryId': _beneficiaryId.text.trim(),
                      'recipientAccountId': _recipientAccountId.text.trim(),
                      'targetUnits': _target.text.trim(),
                      'deadlineGameDay': _deadline.text.trim(),
                      'matchingPoolAuthorizedUnits': _matching.text.trim(),
                      'proposalId': _proposal.text.trim(),
                    })
                : null,
            child: const Text('CREATE'))
      ],
    );
  }
}
