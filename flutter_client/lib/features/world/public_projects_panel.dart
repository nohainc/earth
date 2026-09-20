import 'package:flutter/material.dart';

import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

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

  Future<void> _contribute(Map<String, dynamic> project) async {
    final amount = await _amountDialog('CONTRIBUTE TO PROJECT');
    if (amount == null || !mounted) return;
    await widget.action(() async {
      await const EarthApi().contributeToPublicProject(
        projectId: project['id'].toString(),
        amountCredit: amount,
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
          decoration: const InputDecoration(labelText: 'Amount (CREDIT)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value) &&
                  value != '0' &&
                  value != '0.0' &&
                  value != '0.00') {
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

  Future<void> _openProject(Map<String, dynamic> project) async {
    final id = project['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    try {
      final response = await const EarthApi().getPublicProject(id);
      final detail = response['project'] is Map
          ? Map<String, dynamic>.from(response['project'] as Map)
          : project;
      final capabilities = detail['capabilities'] is Map
          ? Map<String, dynamic>.from(detail['capabilities'] as Map)
          : const <String, dynamic>{};
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(detail['name']?.toString() ?? id),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '${detail['beneficiary_type'] ?? 'PUBLIC'} · ${detail['status'] ?? '—'}'),
                      const SizedBox(height: 16),
                      Text(detail['description']?.toString() ??
                          'No description published.'),
                      const SizedBox(height: 16),
                      Text(
                          'COMMUNITY FUNDING\n${formatCreditUnits(detail['contribution_units'])} / ${formatCreditUnits(detail['target_units'])}'),
                      Text(
                          'EARTH MATCHING\n${formatCreditUnits(detail['matched_units'] ?? detail['matching_pool_funded_units'])}'),
                      Text(
                          'PROJECTED MATCH\n${formatCreditUnits(detail['projected_match_units'])}'),
                      Text('SUPPORTERS\n${detail['supporter_count'] ?? '0'}'),
                      Text(
                          'DEADLINE\nDay ${detail['deadline_game_day'] ?? '—'}'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('CLOSE')),
                ],
              ));
    } catch (error) {
      _showMessage(
          'Project details are temporarily unavailable. Please retry.');
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final statusCounts = <String, int>{};
    for (final project in _projects) {
      final status = '${project['status'] ?? 'UNKNOWN'}'.toUpperCase();
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }
    final activeCount = (statusCounts['OPEN'] ?? 0) +
        (statusCounts['FUNDED'] ?? 0) +
        (statusCounts['EXECUTING'] ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          EarthEmptyState(
              message: 'Project data is unavailable. Please retry.',
              icon: Icons.sync_problem_outlined,
              action: TextButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY')))
        else if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_projects.isEmpty)
          const EarthEmptyState(
              message: 'No public projects are currently published.',
              icon: Icons.construction_outlined)
        else
          EarthSection(
            title:
                'PUBLIC PROJECTS · $activeCount ACTIVE · ${statusCounts['SETTLED'] ?? 0} COMPLETED',
            showSurface: true,
            trailing: IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh projects',
            ),
            child: EarthDataList(
                children: _projects.map((project) {
              final target = project['target_units'];
              final funded = project['contribution_units'];
              final status =
                  (project['status'] ?? 'UNKNOWN').toString().toUpperCase();
              final capabilities = project['capabilities'] is Map
                  ? Map<String, dynamic>.from(project['capabilities'] as Map)
                  : const <String, dynamic>{};
              return EarthDataRow(
                title: project['name']?.toString() ??
                    project['id']?.toString() ??
                    'Public project',
                subtitle:
                    '${project['beneficiary_type'] ?? 'PUBLIC'} · $status · deadline day ${project['deadline_game_day'] ?? '—'}',
                secondarySubtitle:
                    '${project['description'] ?? 'No description published'} · funded ${formatCreditUnits(funded)} / ${formatCreditUnits(target)}',
                leading: Icon(Icons.construction_outlined,
                    color: context.primaryColor),
                badges: [
                  EarthBadge(label: status, variant: EarthBadgeVariant.primary)
                ],
                trailing: Wrap(spacing: 4, children: [
                  TextButton(
                      onPressed: () => _openProject(project),
                      child: const Text('DETAILS')),
                  if (capabilities['canContribute'] == true && !widget.busy)
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
