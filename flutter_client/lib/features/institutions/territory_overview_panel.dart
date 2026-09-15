import 'package:flutter/material.dart';

import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

/// Dedicated Territory overview. Membership and residency are deliberately
/// shown as separate facts, matching the V4 institutional model.
class TerritoryOverviewPanel extends StatelessWidget {
  final EarthState state;
  final Map<String, dynamic> commonsData;
  final ValueChanged<String>? onNavigate;

  const TerritoryOverviewPanel({
    super.key,
    required this.state,
    this.commonsData = const {},
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final residency = state.residency;
    final territory = state.institutions['territory'] is Map
        ? Map<String, dynamic>.from(state.institutions['territory'] as Map)
        : const <String, dynamic>{};
    final capacity = state.json['territory'] is Map
        ? Map<String, dynamic>.from(state.json['territory'] as Map)
        : const <String, dynamic>{};
    final id = (residency['territory_id'] ?? residency['territoryId'] ?? territory['id'] ?? capacity['territory_id'])?.toString();
    final name = (residency['territory_name'] ?? residency['territoryName'] ?? territory['name'] ?? id ?? 'Independent commons').toString();
    final total = _number(capacity['house_capacity'] ?? capacity['housing_capacity'] ?? territory['house_capacity']);
    final used = _number(capacity['active_house_count'] ?? capacity['residents'] ?? territory['active_house_count']);
    final slots = _number(capacity['private_slot_capacity'] ?? territory['private_slot_capacity']);
    final slotsUsed = _number(capacity['private_slots_used'] ?? territory['private_slots_used']);
    final governing = (territory['governing_organization_name'] ?? territory['corporation_name'] ?? residency['corporation_name'] ?? 'EARTH default authority').toString();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EarthPageCockpit(
        tag: 'SOCIETY',
        status: id == null ? 'INDEPENDENT COMMONS' : 'PRIMARY RESIDENCY',
        statusColor: context.primaryColor,
        infoTitle: 'TERRITORY OVERVIEW',
        infoDescription: 'Territory is a scarce physical jurisdiction. Residency, organization membership, building ownership, and use rights are separate relationships. Capacity and prices come from the server snapshot.',
        title: name.toUpperCase(),
        subtitle: 'Residency, capacity, governing authority, and local economic conditions',
        actions: [
          EarthButton(label: 'MANAGE USE RIGHTS', icon: Icons.key_outlined, onPressed: onNavigate == null ? null : () => onNavigate!('territory-commons')),
        ],
        metrics: [
          CockpitMetric(label: 'Residents', value: _display(used, total), icon: Icons.groups_outlined, color: context.primaryColor),
          CockpitMetric(label: 'Private slots', value: _display(slotsUsed, slots), icon: Icons.grid_view_outlined, color: context.secondaryColor),
        ],
      ),
      const SizedBox(height: 20),
      EarthSection(title: 'JURISDICTION & CAPACITY', showSurface: true, child: Column(children: [
        _row(context, 'PRIMARY RESIDENCY', name),
        _row(context, 'GOVERNING AUTHORITY', governing),
        _row(context, 'HOUSE CAPACITY', _display(used, total)),
        _row(context, 'PRIVATE USE CAPACITY', _display(slotsUsed, slots)),
      ])),
      const SizedBox(height: 18),
      EarthSection(title: 'WHAT YOU CAN DO HERE', showSurface: true, child: Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(onPressed: onNavigate == null ? null : () => onNavigate!('territory-commons'), icon: const Icon(Icons.key_outlined), label: const Text('Acquire or release use rights')),
        OutlinedButton.icon(onPressed: onNavigate == null ? null : () => onNavigate!('buildings'), icon: const Icon(Icons.domain_outlined), label: const Text('View productive assets')),
        OutlinedButton.icon(onPressed: onNavigate == null ? null : () => onNavigate!('communities'), icon: const Icon(Icons.forum_outlined), label: const Text('Find local communities')),
      ])),
      if (commonsData.isNotEmpty) ...[
        const SizedBox(height: 18),
        EarthSection(title: 'LOCAL COMMONS', showSurface: true, child: Text('Use-right and commons statements are available in Territories → Manage use rights.', style: context.widgetFooterStyle)),
      ],
    ]);
  }

  static num? _number(dynamic value) => value is num ? value : num.tryParse(value?.toString() ?? '');
  static String _display(num? used, num? total) => used == null ? 'UNAVAILABLE' : total == null ? used.toString() : '${used.toStringAsFixed(0)} / ${total.toStringAsFixed(0)}';
  static Widget _row(BuildContext context, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Text(label, style: context.captionStyle), const Spacer(), Flexible(child: Text(value, textAlign: TextAlign.right, style: context.bodyStyle.copyWith(fontWeight: FontWeight.w700)))]));
}
