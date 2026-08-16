import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import 'business_dialogs.dart';

class BusinessPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const BusinessPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.businessOwnership,
    required this.businessFinancials,
    required this.businessProfile,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final businessName =
        (state.business['name'] as String?)?.toUpperCase() ?? 'ENTERPRISE';
    return EarthPanel(
      key: panelKey,
      title: 'BUSINESS / $businessName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Policy: ${state.business['policy']}'),
          Text('Financial status: ${state.business['status'] ?? 'active'}',
              style: const TextStyle(color: mutedColor, fontSize: 11)),
          Text('Condition: ${state.business['condition']}%'),
          if (businessProfile['business'] is Map)
            Text(
              'Sector: ${(businessProfile['business'] as Map<String, dynamic>)['sector']} · status ${(businessProfile['business'] as Map<String, dynamic>)['status']}',
              style: const TextStyle(color: mutedColor, fontSize: 11),
            ),
          if (businessProfile['assets'] is List)
            Text(
              'Assigned machines: ${(businessProfile['assets'] as List).length}',
              style: const TextStyle(color: mutedColor, fontSize: 11),
            ),
          Text(
            'Financials: revenue ${state.business['revenue'] ?? 0} C · costs ${state.business['operating_costs'] ?? 0} C · profit ${state.business['profit'] ?? 0} C',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          if (businessFinancials['business'] is Map)
            Text(
              'Taxed revenue: ${(businessFinancials['business'] as Map<String, dynamic>)['taxed_revenue'] ?? 0} C · last assessed day ${(businessFinancials['business'] as Map<String, dynamic>)['last_game_day'] ?? 0}',
              style: const TextStyle(color: mutedColor, fontSize: 11),
            ),
          const Text(
            'Revenue is recorded when owner output clears through the canonical market; production inputs are operating costs.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          Text('Ownership: ${state.business['owned_shares'] ?? 0} shares',
              style: const TextStyle(color: mutedColor, fontSize: 11)),
          Text(
            'Registry control: ${state.business['controlling_human_id'] ?? 'undetermined'} · ${state.business['total_issued_shares'] ?? 0} issued shares',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          if (businessOwnership['holders'] is List &&
              (businessOwnership['holders'] as List).isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('OWNERSHIP REGISTRY',
                style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
            ...((businessOwnership['holders'] as List).take(5).map((raw) {
              final holder = raw as Map<String, dynamic>;
              return Text(
                '${holder['display_name']} · ${holder['percentage']}% (${holder['shares']} shares)',
                style: const TextStyle(fontSize: 11),
              );
            })),
          ],
          Text('Manager: ${state.business['manager_id'] ?? 'owner'}',
              style: const TextStyle(color: mutedColor, fontSize: 11)),
          Text(
            'Constitution v${state.business['constitution_version'] ?? 1} · shareholder ${((double.tryParse('${state.business['shareholder_vote_threshold'] ?? 0.5}') ?? 0.5) * 100).round()}% · dilution notice ${state.business['dilution_notice_days'] ?? 3}d',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed:
                busy ? null : () => showBusinessComposerDialog(context, action),
            child: const Text('REGISTER NEW BUSINESS · 250 C'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed:
                busy ? null : () => showShareTransferDialog(context, action),
            child: const Text('TRANSFER SHARES'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => showShareIssueDialog(
                    context, action, state.business['id'] as String?),
            child: const Text('ISSUE SHARES'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => showBusinessConstitutionDialog(
                    context, action, state.business),
            child: const Text('UPDATE CONSTITUTION'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => showBusinessManagerDialog(
                    context, action, state.business['id'] as String?),
            child: const Text('APPOINT MANAGER'),
          ),
          if (['distressed', 'insolvent']
              .contains('${state.business['status'] ?? ''}')) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => showBusinessLiquidationDialog(
                      context, action, state.business['id'] as String?),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('LIQUIDATE BUSINESS'),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['reliability', 'margin', 'capacity']
                .map((policy) => OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => const EarthApi().setPolicy(policy)),
                    child: Text(policy)))
                .toList(),
          ),
        ],
      ),
    );
  }
}
