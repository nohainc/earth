import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../../core/api/earth_api.dart';

class TerritoryCommonsPanel extends StatefulWidget {
  final Map<String, dynamic> data;
  final EarthApi? api;
  final VoidCallback? onRefresh;

  const TerritoryCommonsPanel({
    super.key,
    required this.data,
    this.api,
    this.onRefresh,
  });

  @override
  State<TerritoryCommonsPanel> createState() => _TerritoryCommonsPanelState();
}

class _TerritoryCommonsPanelState extends State<TerritoryCommonsPanel> {
  bool _isLoading = false;

  Future<void> _showAcquireRightDialog(
    BuildContext context,
    String territoryId, {
    required int rentPerSlot,
    required int maxTermDays,
    required String rulesVersion,
  }) async {
    int slotQuantity = 1;
    int termDays = 30;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalRent = slotQuantity * rentPerSlot;
          return AlertDialog(
            title: const Text('ACQUIRE USE RIGHT / LEASE'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Territory: $territoryId',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Slots (Private Capacity):'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: slotQuantity > 1
                            ? () => setDialogState(() => slotQuantity--)
                            : null,
                      ),
                      Text('$slotQuantity slots',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: slotQuantity < 50
                            ? () => setDialogState(() => slotQuantity++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Duration (Game Days):'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: termDays > 5
                            ? () => setDialogState(() => termDays -= 5)
                            : null,
                      ),
                      Text('$termDays days',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: termDays < maxTermDays
                            ? () => setDialogState(() => termDays =
                                termDays + 5 > maxTermDays
                                    ? maxTermDays
                                    : termDays + 5)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.5),
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Upfront charge: $rentPerSlot CR / slot'),
                        const SizedBox(height: 4),
                        Text('Total Upfront Rent: $totalRent CR',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber)),
                        const SizedBox(height: 4),
                        Text(
                            'Billing: paid once at acquisition · $rulesVersion',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: widget.api == null
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(dialogCtx).pop();
                        setState(() => _isLoading = true);
                        try {
                          await widget.api!.acquireTerritoryRight(
                            territoryId: territoryId,
                            slotQuantity: slotQuantity.toString(),
                            termDays: termDays,
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Acquired $slotQuantity slots for $termDays game days')),
                            );
                            widget.onRefresh?.call();
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text('Failed: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                child: const Text('ACQUIRE LEASE'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _releaseRight(String rightId) async {
    if (widget.api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('RELEASE USE RIGHT'),
        content: Text(
            'Are you sure you want to release right $rightId? Unused days will be forfeited.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('RELEASE')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.api!.releaseTerritoryRight(rightId: rightId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use right released successfully')),
        );
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to release: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showRelocateDialog(
      BuildContext context, String currentTerritoryId) async {
    final territories = (widget.data['territories'] is List
            ? (widget.data['territories'] as List)
            : const [])
        .whereType<Map>()
        .map((row) => {
              'id': row['id']?.toString() ?? '',
              'name': row['name']?.toString() ?? row['id']?.toString() ?? '',
            })
        .where(
            (row) => row['id']!.isNotEmpty && row['id'] != currentTerritoryId)
        .toList();
    if (territories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alternative active Territories are available.')),
      );
      return;
    }
    var target = territories.first['id']!;
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('RELOCATE PRIMARY RESIDENCY'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: $currentTerritoryId'),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDialogState) =>
                  DropdownButtonFormField<String>(
                value: target,
                decoration: const InputDecoration(
                  labelText: 'Target Territory',
                  border: OutlineInputBorder(),
                ),
                items: territories
                    .map((row) => DropdownMenuItem<String>(
                          value: row['id'],
                          child: Text(row['name']!.toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => target = value);
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Relocation takes effect at the next daily settlement boundary. Remote buildings remain under your ownership.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: widget.api == null
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final quote =
                          await widget.api!.quoteHouseMove(territoryId: target);
                      if (!context.mounted) return;
                      final targetTerritory = quote['targetTerritory'] is Map
                          ? Map<String, dynamic>.from(
                              quote['targetTerritory'] as Map)
                          : const <String, dynamic>{};
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (confirmCtx) => AlertDialog(
                          title: const Text('REVIEW RESIDENCY MOVE'),
                          content: Text(
                            '${targetTerritory['name'] ?? target}\n\n'
                            'Eligibility: ${quote['eligible'] == true ? 'Eligible' : 'Not eligible'}\n'
                            'Effective: next settlement boundary\n'
                            'Move cost: ${quote['moveCostUnits'] ?? '0'} CR\n'
                            'Remote buildings remain owned: ${quote['assetLocationRetained'] == true ? 'Yes' : 'No'}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(false),
                              child: const Text('CANCEL'),
                            ),
                            FilledButton(
                              onPressed: quote['eligible'] == true
                                  ? () => Navigator.of(confirmCtx).pop(true)
                                  : null,
                              child: const Text('CONFIRM MOVE'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      if (!dialogCtx.mounted) return;
                      Navigator.of(dialogCtx).pop();
                      setState(() => _isLoading = true);
                      await widget.api!.moveHouseResidence(territoryId: target);
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Residency relocation requested to $target')),
                        );
                        widget.onRefresh?.call();
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Relocation unavailable: $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
            child: const Text('CONFIRM MOVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final residency = widget.data['residency'] is Map
        ? Map<String, dynamic>.from(widget.data['residency'] as Map)
        : const <String, dynamic>{};
    final rights = (widget.data['rights'] as List<dynamic>?) ?? const [];
    final statement = widget.data['commons'] is Map
        ? Map<String, dynamic>.from(widget.data['commons'] as Map)
        : const <String, dynamic>{};
    final territory = residency['currentTerritoryId'] ??
        residency['territoryId'] ??
        widget.data['territoryId'];
    final rentPolicy = widget.data['rentPolicy'] is Map
        ? Map<String, dynamic>.from(widget.data['rentPolicy'] as Map)
        : const <String, dynamic>{};
    final rentPerSlot =
        int.tryParse((rentPolicy['rentPerSlotUnits'] ?? '').toString()) ?? 0;
    final maxTermDays =
        int.tryParse((rentPolicy['maxTermDays'] ?? '').toString()) ?? 365;
    final rulesVersion = rentPolicy['rulesVersion']?.toString() ?? '—';
    final policy = statement['policy'] is Map
        ? Map<String, dynamic>.from(statement['policy'] as Map)
        : const <String, dynamic>{};

    int totalSlots = 0;
    for (final r in rights) {
      if (r is Map && r['status'] == 'ACTIVE') {
        totalSlots +=
            (int.tryParse(r['slot_quantity']?.toString() ?? '0') ?? 0);
      }
    }

    return EarthSection(
      title: 'TERRITORY COMMONS & LEASES',
      showSurface: false,
      infoBulletPoints: const [
        'Territory capacity is a time-bounded use right, separate from building ownership.',
        'Rent funds the governing commons account; it is not a login reward.',
        'Commons dividends are declared by the governing authority and paid only from collected rent.',
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_isLoading) const LinearProgressIndicator(),
        EarthMetricGrid(
          metrics: [
            EarthMetricTile(
              label: 'PRIMARY RESIDENCY',
              value: territory?.toString().toUpperCase() ?? 'NOT RECORDED',
              icon: Icons.location_on_outlined,
              accentColor: context.primaryColor,
            ),
            EarthMetricTile(
              label: 'ACTIVE LEASE SLOTS',
              value: '$totalSlots SLOTS',
              icon: Icons.grid_view_outlined,
              accentColor:
                  totalSlots > 0 ? context.successColor : context.warningColor,
            ),
            EarthMetricTile(
              label: 'DIVIDEND RATE',
              value: policy.isEmpty
                  ? 'NONE'
                  : '${policy['dividend_bps'] ?? 0} BPS',
              icon: Icons.payments_outlined,
              accentColor: context.secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed:
                  territory == null || widget.api == null || rentPerSlot <= 0
                      ? null
                      : () => _showAcquireRightDialog(
                            context,
                            territory.toString(),
                            rentPerSlot: rentPerSlot,
                            maxTermDays: maxTermDays,
                            rulesVersion: rulesVersion,
                          ),
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text('ACQUIRE USE RIGHT'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: territory == null || widget.api == null
                  ? null
                  : () => _showRelocateDialog(context, territory.toString()),
              icon: const Icon(Icons.directions_walk_outlined),
              label: const Text('RELOCATE RESIDENCE'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('YOUR ACTIVE USE RIGHTS', style: context.topicTitleStyle),
        const SizedBox(height: 6),
        if (rights.isEmpty)
          Text(
              'No active private use rights. Acquire slots before starting private construction projects.',
              style: context.widgetFooterStyle)
        else
          ...rights.whereType<Map>().map((right) {
            final rightId = right['id']?.toString() ?? '';
            final status = right['status']?.toString() ?? 'ACTIVE';
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text('${right['slot_quantity'] ?? 0} private slots',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Rent: ${right['rent_per_game_day_units'] ?? '—'} CR/day · Ends: Day ${right['effective_to_game_day'] ?? 'open'}'),
                trailing: status == 'ACTIVE'
                    ? OutlinedButton(
                        onPressed: () => _releaseRight(rightId),
                        child: const Text('RELEASE'),
                      )
                    : Chip(label: Text(status)),
              ),
            );
          }),
        const SizedBox(height: 16),
        Text('COMMONS POLICY & ACCOUNTING STATUS',
            style: context.topicTitleStyle),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                policy.isEmpty
                    ? 'No active dividend policy is reported for this territory.'
                    : 'Policy: ${policy['reserve_bps'] ?? '—'} bps reserve · ${policy['dividend_bps'] ?? '—'} bps resident dividend',
                style: context.widgetFooterStyle,
              ),
              const SizedBox(height: 4),
              const Text(
                  'Figures are server-derived canonical facts. All lease revenues and dividend payments are double-entry verified against the canonical ledger.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ]),
    );
  }
}
