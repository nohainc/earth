import 'package:flutter/material.dart';

import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';
import 'organization_people_roles_panel.dart';

/// V4 organization directory. Organizations are a generic institution; a
/// corporation is only one available archetype.
class OrganizationDirectoryPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const OrganizationDirectoryPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<OrganizationDirectoryPanel> createState() =>
      _OrganizationDirectoryPanelState();
}

class _OrganizationDirectoryPanelState
    extends State<OrganizationDirectoryPanel> {
  List<Map<String, dynamic>> _organizations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await const EarthApi().listOrganizations();
      final raw = response['organizations'];
      if (!mounted) return;
      setState(() {
        _organizations = raw is List
            ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : const [];
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

  Future<void> _join(String id) async {
    await widget.action(() async {
      await const EarthApi().joinOrganization(organizationId: id);
      return const EarthApi().world();
    });
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => const _CreateOrganizationDialog(),
    );
    if (result == null || !mounted) return;
    await widget.action(() async {
      await const EarthApi().createOrganization(
        name: result['name']!,
        archetype: result['archetype']!,
        joinPolicy: result['joinPolicy']!,
      );
      return const EarthApi().world();
    });
    if (mounted) await _load();
  }

  Future<void> _openOrganization(Map<String, dynamic> organization) async {
    final id = organization['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(organization['name']?.toString() ?? id),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${organization['archetype'] ?? 'ORGANIZATION'} · ${organization['join_policy'] ?? 'OPEN'}',
                  style: context.captionStyle,
                ),
                const SizedBox(height: 12),
                Text(
                  _capabilities(organization['capabilities']),
                  style: context.widgetFooterStyle,
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: Future.wait([
                    const EarthApi().getOrganizationFinance(organizationId: id),
                    const EarthApi().getOrganizationCharter(organizationId: id),
                    const EarthApi()
                        .getOrganizationVotingMethod(organizationId: id),
                    const EarthApi().organizationFinancialRisk(id),
                  ]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.hasError) {
                      return Text('Organization details are unavailable.',
                          style: TextStyle(color: context.warningColor));
                    }
                    final finance = snapshot.data![0];
                    final charter = snapshot.data![1];
                    final voting = snapshot.data![2];
                    final risk = snapshot.data![3];
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('TREASURY & GOVERNANCE',
                              style: context.topicTitleStyle
                                  .copyWith(color: context.primaryColor)),
                          const SizedBox(height: 8),
                          Text(
                              'Treasury: ${formatCreditUnits(finance['treasury_units'] ?? finance['treasury'])} · Budget: ${formatCreditUnits(finance['budget_authorized_units'] ?? finance['budget'])}',
                              style: context.bodyStyle),
                          Text(
                              'Charter version: ${charter['version'] ?? charter['charter']?['version'] ?? '—'} · Voting: ${voting['voting_method'] ?? voting['votingMethod'] ?? '—'}',
                              style: context.bodyStyle),
                          Text(
                              'Financial status: ${risk['status'] ?? risk['resolution']?['status'] ?? '—'} · Risk: ${risk['risk_level'] ?? risk['riskLevel'] ?? '—'}',
                              style: context.bodyStyle),
                          if (risk['cases'] is List &&
                              (risk['cases'] as List).isNotEmpty)
                            Text(
                                'Resolution cases: ${(risk['cases'] as List).length}',
                                style: context.bodyStyle),
                          const SizedBox(height: 14),
                          OrganizationPeopleRolesPanel(organizationId: id),
                        ]);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (organization['is_member'] == true)
            TextButton(
                onPressed: () => _openResolution(id),
                child: const Text('RESOLUTION')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Future<void> _openResolution(String organizationId) async {
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) {
          final proposal = TextEditingController();
          final successor = TextEditingController();
          String type = 'RESTRUCTURE';
          return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                    title: const Text('ORGANIZATION RESOLUTION'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          value: type,
                          decoration: const InputDecoration(
                              labelText: 'Resolution type'),
                          items: const [
                            DropdownMenuItem(
                                value: 'RESTRUCTURE',
                                child: Text('Restructure')),
                            DropdownMenuItem(
                                value: 'MERGER',
                                child: Text('Merge into successor')),
                            DropdownMenuItem(
                                value: 'SPLIT',
                                child: Text('Split to successor')),
                            DropdownMenuItem(
                                value: 'DISSOLUTION', child: Text('Dissolve')),
                          ],
                          onChanged: (value) =>
                              setState(() => type = value ?? type)),
                      TextField(
                          controller: proposal,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'Passed organization proposal ID')),
                      if (type != 'DISSOLUTION')
                        TextField(
                            controller: successor,
                            decoration: const InputDecoration(
                                labelText: 'Successor organization ID')),
                      const SizedBox(height: 8),
                      const Text(
                          'A passed organization proposal is required. Asset and membership continuity is settled by the server.',
                          style: TextStyle(fontSize: 11)),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('CANCEL')),
                      FilledButton(
                          onPressed: () {
                            if (proposal.text.trim().isNotEmpty &&
                                (type == 'DISSOLUTION' ||
                                    successor.text.trim().isNotEmpty)) {
                              Navigator.pop(dialogContext, {
                                'type': type,
                                'proposal': proposal.text.trim(),
                                'successor': successor.text.trim(),
                              });
                            }
                          },
                          child: const Text('SUBMIT')),
                    ],
                  ));
        });
    if (result == null || !mounted) return;
    try {
      await const EarthApi().createOrganizationResolution(
          organizationId: organizationId,
          caseType: result['type']!,
          proposalId: result['proposal']!,
          successorOrganizationId: result['successor']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Resolution case scheduled for settlement.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resolution unavailable: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _organizations
        .where((organization) => organization['is_member'] == true)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          tag: 'SOCIETY',
          status: _loading
              ? 'LOADING'
              : '${_organizations.length} ACTIVE ORGANIZATIONS',
          statusColor: context.primaryColor,
          infoTitle: 'ORGANIZATION DIRECTORY',
          infoDescription:
              'Organizations are generic V4 institutions. Archetypes include communities, corporations, cooperatives, public bodies, research organizations, and banks. Membership does not determine territorial residency.',
          title: 'ORGANIZATIONS',
          subtitle:
              'Find institutions, inspect their purpose, and manage House memberships',
          actions: [
            EarthButton(
              label: 'CREATE ORGANIZATION',
              icon: Icons.add_business_outlined,
              onPressed: widget.busy || _loading ? null : _create,
            ),
          ],
          metrics: [
            CockpitMetric(
              label: 'Available',
              value: '${_organizations.length}',
              icon: Icons.account_balance_outlined,
              color: context.primaryColor,
            ),
            CockpitMetric(
              label: 'Your memberships',
              value: '$memberCount',
              icon: Icons.how_to_reg_outlined,
              color: context.successColor,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null) _message(context, _error!),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_organizations.isEmpty)
          EarthSection(
            title: 'NO ACTIVE ORGANIZATIONS',
            showSurface: true,
            child: Text(
              'No organizations are currently available in the world snapshot.',
              style: context.widgetFooterStyle,
            ),
          )
        else
          EarthSection(
            title: 'ACTIVE ORGANIZATIONS',
            showSurface: true,
            child: EarthDataList(
              children: _organizations.map((organization) {
                final id = organization['id']?.toString() ?? '';
                final name = organization['name']?.toString() ?? id;
                final archetype =
                    organization['archetype']?.toString() ?? 'ORGANIZATION';
                final members = organization['member_count']?.toString() ?? '0';
                final isMember = organization['is_member'] == true;
                final joinPolicy =
                    organization['join_policy']?.toString() ?? 'OPEN';
                return EarthDataRow(
                  title: name,
                  subtitle: '$archetype · $members Houses · $joinPolicy',
                  secondarySubtitle:
                      _capabilities(organization['capabilities']),
                  leading: Icon(Icons.account_balance_outlined,
                      color: isMember
                          ? context.successColor
                          : context.primaryColor),
                  badges: [
                    EarthBadge(
                      label: isMember ? 'MEMBER' : archetype,
                      variant: isMember
                          ? EarthBadgeVariant.success
                          : EarthBadgeVariant.primary,
                    ),
                  ],
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Open organization',
                        onPressed: () => _openOrganization(organization),
                        icon: const Icon(Icons.open_in_new, size: 16)),
                    if (!isMember && !widget.busy)
                      TextButton(
                        onPressed: () => _join(id),
                        child: Text(joinPolicy == 'OPEN' ? 'JOIN' : 'REQUEST',
                            style: context.controlStyle
                                .copyWith(color: context.primaryColor)),
                      ),
                  ]),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  String _capabilities(dynamic value) {
    if (value is! List || value.isEmpty) return 'Capabilities not published';
    return value.map((item) => item.toString()).join(' · ');
  }

  Widget _message(BuildContext context, String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.errorColor.withValues(alpha: .1),
          border: Border.all(color: context.errorColor.withValues(alpha: .4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: context.widgetFooterStyle),
      );
}

class _CreateOrganizationDialog extends StatefulWidget {
  const _CreateOrganizationDialog();

  @override
  State<_CreateOrganizationDialog> createState() =>
      _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<_CreateOrganizationDialog> {
  final _name = TextEditingController();
  String _archetype = 'COOPERATIVE';
  String _joinPolicy = 'OPEN';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CREATE ORGANIZATION'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Organization name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _archetype,
              decoration: const InputDecoration(labelText: 'Archetype'),
              items: const [
                DropdownMenuItem(
                    value: 'COOPERATIVE', child: Text('Cooperative')),
                DropdownMenuItem(
                    value: 'ENTERPRISE', child: Text('Enterprise')),
                DropdownMenuItem(
                    value: 'RESEARCH', child: Text('Research organization')),
                DropdownMenuItem(value: 'COMMUNITY', child: Text('Community')),
              ],
              onChanged: (value) =>
                  setState(() => _archetype = value ?? _archetype),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _joinPolicy,
              decoration: const InputDecoration(labelText: 'Admission'),
              items: const [
                DropdownMenuItem(value: 'OPEN', child: Text('Open membership')),
                DropdownMenuItem(
                    value: 'REQUEST', child: Text('Request approval')),
              ],
              onChanged: (value) =>
                  setState(() => _joinPolicy = value ?? _joinPolicy),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'name': _name.text.trim(),
                    'archetype': _archetype,
                    'joinPolicy': _joinPolicy,
                  }),
          child: const Text('CREATE'),
        ),
      ],
    );
  }
}
