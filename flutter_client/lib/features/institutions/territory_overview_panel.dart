import 'package:flutter/material.dart';

import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

/// Read-only physical capacity-container overview for the V5 world model.
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
    final id = (residency['territory_id'] ??
            residency['territoryId'] ??
            territory['id'] ??
            capacity['territory_id'])
        ?.toString();
    final name = (residency['territory_name'] ??
            residency['territoryName'] ??
            territory['name'] ??
            'No active residency')
        .toString();
    final total = _number(capacity['house_capacity'] ??
        capacity['housing_capacity'] ??
        territory['house_capacity']);
    final used = _number(capacity['active_house_count'] ??
        capacity['residents'] ??
        territory['active_house_count']);
    final slots = _number(capacity['private_slot_capacity'] ??
        territory['private_slot_capacity']);
    final slotsUsed = _number(
        capacity['private_slots_used'] ?? territory['private_slots_used']);
    final governing = (territory['governing_organization_name'] ??
            territory['corporation_name'] ??
            residency['corporation_name'])
        ?.toString();
    final availableTerritories = state.territories
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => (row['status'] ?? 'ACTIVE').toString() != 'INACTIVE')
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EarthPageCockpit(
        tag: 'SOCIETY',
        status: id == null ? 'NO RESIDENCY CONTEXT' : 'RESIDENCY CONTEXT',
        statusColor: context.primaryColor,
        infoTitle: 'PHYSICAL CAPACITY CONTAINERS',
        infoDescription:
            'Territory records are standardized physical capacity containers. Residency, Corporation affiliation, building ownership, and capacity use are separate relationships. Values come from the server snapshot.',
        title: name.toUpperCase(),
        subtitle: 'Physical capacity, residency, and Corporation context',
        actions: const [],
        metrics: [
          CockpitMetric(
              label: 'Residents',
              value: _display(used, total),
              icon: Icons.groups_outlined,
              color: context.primaryColor),
          CockpitMetric(
              label: 'Private slots',
              value: _display(slotsUsed, slots),
              icon: Icons.grid_view_outlined,
              color: context.secondaryColor),
        ],
      ),
      const SizedBox(height: 20),
      EarthSection(
          title: 'RESIDENCY & CAPACITY CONTEXT',
          showSurface: true,
          child: Column(children: [
            _row(context, 'RESIDENCY CONTEXT', name),
            _row(context, 'CORPORATION CONTEXT', governing ?? 'NOT REPORTED'),
            _row(context, 'HOUSE CAPACITY', _display(used, total)),
            _row(context, 'PRIVATE USE CAPACITY', _display(slotsUsed, slots)),
          ])),
      const SizedBox(height: 18),
      EarthSection(
        title: 'ACTIVE CAPACITY CONTAINERS',
        showSurface: true,
        child: availableTerritories.isEmpty
            ? Text('Territory directory is not available in this snapshot.',
                style: context.widgetFooterStyle)
            : Column(
                children: availableTerritories.map((row) {
                  final territoryId = row['id']?.toString();
                  final territoryName = row['name']?.toString().trim();
                  final isCurrent = territoryId != null && territoryId == id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        isCurrent ? Icons.location_on : Icons.public_outlined),
                    title: Text((territoryName == null || territoryName.isEmpty)
                        ? 'Unnamed territory'
                        : territoryName),
                    subtitle: Text(
                        '${row['territory_type'] ?? 'Territory'} · ${row['status'] ?? 'ACTIVE'}\n'
                        'Homes ${_capacity(row['active_house_count'], row['house_capacity'])} · '
                        'Private slots ${_capacity(row['private_slots_used'], row['private_slot_capacity'])}'),
                    trailing:
                        isCurrent ? const Chip(label: Text('CURRENT')) : null,
                  );
                }).toList(),
              ),
      ),
      const SizedBox(height: 18),
      EarthSection(
          title: 'V5 CAPACITY MODEL',
          showSurface: true,
          child: Text(
              'Buildings consume House or Corporation pooled capacity. The number of physical containers is derived from occupied capacity and does not create a political or placement choice.',
              style: context.widgetFooterStyle)),
      if (commonsData.isNotEmpty) ...[
        const SizedBox(height: 18),
        EarthSection(
            title: 'LOCAL COMMONS',
            showSurface: true,
            child: Text(
                'Commons and use-right records are retained as historical/read-only context; they are not a V5 building-placement control.',
                style: context.widgetFooterStyle)),
      ],
    ]);
  }

  static num? _number(dynamic value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '');
  static String _display(num? used, num? total) => used == null
      ? 'UNAVAILABLE'
      : total == null
          ? used.toString()
          : '${used.toStringAsFixed(0)} / ${total.toStringAsFixed(0)}';
  static String _capacity(dynamic used, dynamic total) => _display(
        _number(used),
        _number(total),
      );
  static Widget _row(BuildContext context, String label, String value) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Text(label, style: context.captionStyle),
            const Spacer(),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: context.bodyStyle
                        .copyWith(fontWeight: FontWeight.w700)))
          ]));
}
