import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../shared/design_system/design_system.dart';

class CorporationRolesPanel extends StatefulWidget {
  final String corporationId;
  final EarthApi api;

  const CorporationRolesPanel({
    super.key,
    required this.corporationId,
    this.api = const EarthApi(),
  });

  @override
  State<CorporationRolesPanel> createState() => _CorporationRolesPanelState();
}

class _CorporationRolesPanelState extends State<CorporationRolesPanel> {
  late Future<Map<String, dynamic>> _roles;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _roles = widget.api.getCorporationRoles(widget.corporationId);
  }

  void _reload() => setState(
      () => _roles = widget.api.getCorporationRoles(widget.corporationId));

  Future<String?> _selectMember(
      BuildContext context, List<Map<String, dynamic>> members) async {
    var selected =
        members.isEmpty ? null : members.first['humanId']?.toString();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Corporation member'),
          content: DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            items: members
                .map((member) => DropdownMenuItem<String>(
                      value: member['humanId']?.toString(),
                      child: Text(member['displayName']?.toString() ??
                          member['humanId']?.toString() ??
                          'Member'),
                    ))
                .toList(),
            onChanged: (value) => setState(() => selected = value),
            decoration: const InputDecoration(labelText: 'Member'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL')),
            ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                child: const Text('SELECT')),
          ],
        ),
      ),
    );
  }

  Future<void> _appoint(BuildContext context, String roleCode,
      List<Map<String, dynamic>> members) async {
    final target = await _selectMember(context, members);
    if (target == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.appointCorporationRole(
          corporationId: widget.corporationId,
          roleCode: roleCode,
          targetHumanId: target);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String roleCode) async {
    setState(() => _busy = true);
    try {
      await widget.api.removeCorporationRole(
          corporationId: widget.corporationId, roleCode: roleCode);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delegate(
      BuildContext context, List<Map<String, dynamic>> members) async {
    final target = await _selectMember(context, members);
    if (target == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.delegateV5CorporationLeadership(
          corporationId: widget.corporationId, targetHumanId: target);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _roles,
      builder: (context, snapshot) {
        final roles = (snapshot.data?['roles'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList() ??
            const <Map<String, dynamic>>[];
        final members = (snapshot.data?['eligibleMembers'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList() ??
            const <Map<String, dynamic>>[];
        final permissions = snapshot.data?['viewerPermissions'] is Map
            ? Map<String, dynamic>.from(
                snapshot.data!['viewerPermissions'] as Map)
            : const <String, dynamic>{};
        final canAppoint = permissions['canAppoint'] == true;
        final canRemove = permissions['canRemove'] == true;
        final canDelegate = permissions['canDelegateLeadership'] == true;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PEOPLE & ROLES',
                  style: context.topicTitleStyle
                      .copyWith(color: context.primaryColor)),
              const SizedBox(height: 5),
              Text('Corporation governance roles and current holders.',
                  style: context.widgetFooterStyle),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              if (snapshot.hasError)
                Text('Corporation role roster unavailable.',
                    style: TextStyle(color: context.warningColor)),
              for (final role in roles)
                _roleRow(context, role, members,
                    canAppoint: canAppoint,
                    canRemove: canRemove,
                    canDelegate: canDelegate),
            ],
          ),
        );
      },
    );
  }

  Widget _roleRow(BuildContext context, Map<String, dynamic> role,
      List<Map<String, dynamic>> members,
      {required bool canAppoint,
      required bool canRemove,
      required bool canDelegate}) {
    final code = role['code']?.toString() ?? 'ROLE';
    final holder = role['holderName']?.toString();
    final active = role['status'] == 'ACTIVE' && holder != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              child: Text(
                  '${role['name'] ?? code}\n${active ? holder : 'VACANT'}',
                  style: context.bodyStyle)),
          if (!active && canAppoint)
            TextButton(
                onPressed:
                    _busy ? null : () => _appoint(context, code, members),
                child: const Text('APPOINT')),
          if (active && canRemove)
            TextButton(
                onPressed: _busy ? null : () => _remove(code),
                child: const Text('REMOVE')),
          if (code == 'CORPORATION_EXECUTIVE' && canDelegate)
            TextButton(
                onPressed: _busy ? null : () => _delegate(context, members),
                child: const Text('DELEGATE')),
        ],
      ),
    );
  }
}
