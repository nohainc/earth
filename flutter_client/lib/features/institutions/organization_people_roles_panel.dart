import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../shared/design_system/design_system.dart';

class OrganizationPeopleRolesPanel extends StatefulWidget {
  final String organizationId;

  const OrganizationPeopleRolesPanel({super.key, required this.organizationId});

  @override
  State<OrganizationPeopleRolesPanel> createState() => _OrganizationPeopleRolesPanelState();
}

class _OrganizationPeopleRolesPanelState extends State<OrganizationPeopleRolesPanel> {
  final _api = const EarthApi();
  late Future<Map<String, dynamic>> _authority;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authority = _api.getOrganizationAuthority(organizationId: widget.organizationId);
  }

  void _reload() => setState(() => _authority = _api.getOrganizationAuthority(organizationId: widget.organizationId));

  Future<void> _appoint(BuildContext context, String officeCode) async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Appoint office holder'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Active Human ID')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')), ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('APPOINT'))],
      ),
    );
    controller.dispose();
    if (target == null || target.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.appointOrganizationOffice(organizationId: widget.organizationId, officeCode: officeCode, targetHumanId: target);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resign(String officeCode) async {
    setState(() => _busy = true);
    try {
      await _api.resignOrganizationOffice(organizationId: widget.organizationId, officeCode: officeCode);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _authority,
      builder: (context, snapshot) {
        final offices = (snapshot.data?['offices'] as List<dynamic>?) ?? const [];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.surfaceColor.withValues(alpha: .75), borderRadius: BorderRadius.circular(context.radiusCard), border: Border.all(color: context.subtleBorderColor)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PEOPLE & ROLES', style: context.topicTitleStyle.copyWith(color: context.primaryColor)),
            const SizedBox(height: 5),
            Text('Membership is separate from ownership and temporary Human office authority.', style: context.widgetFooterStyle),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
            if (snapshot.hasError) Text('Role roster unavailable.', style: TextStyle(color: context.warningColor)),
            for (final raw in offices.whereType<Map>()) _officeRow(context, Map<String, dynamic>.from(raw)),
          ]),
        );
      },
    );
  }

  Widget _officeRow(BuildContext context, Map<String, dynamic> office) {
    final code = office['office_code']?.toString() ?? 'OFFICE';
    final holder = office['principal_name']?.toString();
    final principalId = office['principal_id']?.toString();
    final active = office['status'] == 'ACTIVE' && office['effective_to_game_day'] == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text('${office['name'] ?? code}\n${active && holder != null ? '$holder ($principalId)' : 'VACANT'}', style: context.bodyStyle)),
        if (active && principalId == null) const SizedBox.shrink(),
        TextButton(onPressed: _busy ? null : () => _appoint(context, code), child: const Text('APPOINT')),
        if (active && principalId != null) TextButton(onPressed: _busy ? null : () => _resign(code), child: const Text('RESIGN')),
      ]),
    );
  }
}
