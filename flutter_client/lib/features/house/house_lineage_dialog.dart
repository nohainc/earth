import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/memorial_models.dart';
import '../../shared/design_system/design_system.dart';
import 'house_tree_dialog.dart';

void showHouseLineageDialog(
  BuildContext context, {
  required String houseId,
  MemorialHouseSummary? houseModel,
  EarthState? state,
  EarthApi? api,
}) {
  final client = api ?? const EarthApi();
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => HouseLineageDialog(
      houseId: houseId,
      houseModel: houseModel,
      state: state,
      api: client,
      lineageFuture: client.memorialHouseLineage(houseId),
    ),
  );
}

class HouseLineageDialog extends StatelessWidget {
  final String houseId;
  final MemorialHouseSummary? houseModel;
  final EarthState? state;
  final EarthApi? api;
  final Future<HouseLineage>? lineageFuture;

  const HouseLineageDialog({
    super.key,
    required this.houseId,
    this.houseModel,
    this.state,
    this.api,
    this.lineageFuture,
  });

  @override
  Widget build(BuildContext context) {
    if (lineageFuture != null) {
      return FutureBuilder<HouseLineage>(
        future: lineageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Dialog(
              child: SizedBox(
                width: 320,
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return AlertDialog(
              title: const Text('Lineage unavailable'),
              content: Text('The canonical lineage for House $houseId could not be loaded.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CLOSE')),
              ],
            );
          }
          return _buildContent(context, snapshot.data!.house);
        },
      );
    }
    return _buildContent(context, null);
  }

  Widget _buildContent(BuildContext context, MemorialHouseDetail? detail) {
    final summary = detail ?? houseModel;
    final name = summary?.houseName ?? 'House';
    final gen = summary?.generation;
    final recordedHumans = summary?.deceasedCount;
    final isExtinct = summary?.isExtinct == true;

    final foundedDayNum = summary?.foundedGameDay;
    final foundedLabel = foundedDayNum == null
        ? 'Founded: UNAVAILABLE'
        : 'Founded: ${_formatGameDay(foundedDayNum)}';
    final lifespanDays = summary?.lifespanDays;

    final members = detail?.members ?? const <MemorialCitizenSummary>[];
    final successions = detail?.successions ?? const <MemorialSuccession>[];
    final treeNodes = <Map<String, dynamic>>[];
    for (final member in members) {
      MemorialSuccession? incoming;
      MemorialSuccession? outgoing;
      for (final edge in successions) {
        if (edge.successorHumanId == member.humanId) incoming = edge;
        if (edge.predecessorHumanId == member.humanId) outgoing = edge;
      }
      final period = member.birthGameDay == null
          ? 'Historical dates unavailable'
          : 'Day ${member.birthGameDay}${member.deathGameDay == null ? ' – present' : ' – Day ${member.deathGameDay}'}';
      final relationship = member.status == 'ACTIVE'
          ? 'Current House representative.'
          : outgoing?.successorHumanId != null
              ? 'Predecessor in the recorded succession chain.'
              : incoming?.predecessorHumanId != null
                  ? 'Successor in the recorded succession chain.'
                  : 'Recorded House member.';
      treeNodes.add({
        'gen': member.generation ?? '—',
        'name': member.displayName,
        'title': member.status == 'ACTIVE' ? 'Current House representative' : 'Historical House member',
        'isLiving': member.status == 'ACTIVE',
        'period': period,
        'role': relationship,
      });
    }

    final isMyHouse = state != null &&
        state!.human['house_name']?.toString() == name;

    final accent = isExtinct ? context.mutedColor : context.primaryColor;
    final historicalText = context.mutedColor;

    return Dialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.subtleBorderColor),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.subtleBorderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isExtinct
                          ? context.mutedColor.withValues(alpha: .15)
                          : context.primarySubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isExtinct
                            ? context.mutedColor.withValues(alpha: .3)
                            : context.primaryColor.withValues(alpha: .3),
                      ),
                    ),
                    child: Icon(
                      isExtinct ? Icons.account_balance : Icons.shield_outlined,
                      color: accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: context.widgetValueStyle.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.inkColor,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accent.withValues(alpha: .3),
                                ),
                              ),
                              child: Text(
                                isExtinct ? 'HISTORICAL' : 'ACTIVE LINEAGE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Generation ${gen ?? '—'} · $foundedLabel · ${recordedHumans ?? '—'} Recorded Humans',
                          style: context.bodyStyle.copyWith(
                            fontSize: 12,
                            color: historicalText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: context.mutedColor, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Metric Grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricChip(context, 'RECORDED HUMANS',
                            '${recordedHumans ?? '—'}', context.secondaryColor, Icons.history_edu),
                        _metricChip(context, 'ARCHIVE SPAN',
                            lifespanDays == null ? 'UNAVAILABLE' : _formatDuration(int.tryParse(lifespanDays.toString()) ?? 0),
                            context.primaryColor, Icons.timelapse),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Canonical House Lineage
                    Row(
                      children: [
                        Icon(Icons.account_tree_outlined,
                            size: 16, color: context.primaryColor),
                        SizedBox(width: 8),
                        Text(
                          'HOUSE LINEAGE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: context.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tree Nodes Rendering
                    ...treeNodes.indexed.map((indexed) {
                      final idx = indexed.$1;
                      final node = indexed.$2;
                      final isLast = idx == treeNodes.length - 1;
                      final isLiving = node['isLiving'] == true;
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Generation Timeline Column
                            SizedBox(
                              width: 48,
                              child: Column(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (isLiving ? context.primaryColor : context.mutedColor).withValues(alpha: .2),
                                      border: Border.all(
                                        color: isLiving ? context.primaryColor : context.mutedColor,
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'G${node['gen']}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isLiving ? context.primaryColor : context.mutedColor,
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        color: context.subtleBorderColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Node Card
                            Expanded(
                              child: Container(
                                margin:
                                    EdgeInsets.only(bottom: isLast ? 0 : 16),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: context.cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: (isLiving ? context.primaryColor : context.mutedColor).withValues(alpha: .3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            node['name'].toString(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isLiving ? context.inkColor : context.mutedColor,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (isLiving ? context.primaryColor : context.mutedColor).withValues(alpha: .1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            node['period'].toString(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isLiving ? context.primaryColor : context.mutedColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      node['title'].toString(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: isLiving ? context.primaryColor : context.mutedColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      node['role'].toString(),
                                      style: context.bodyStyle.copyWith(
                                        fontSize: 12,
                                        color: context.mutedColor,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.subtleBorderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isMyHouse && api != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.primaryColor,
                        side: BorderSide(color: context.primaryColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('MANAGE MY HOUSE'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        showHouseTreeDialog(context, api: api!, state: state);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('CLOSE',
                        style: context.controlStyle.copyWith(color: context.primaryColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(BuildContext context, String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
              Text(
                value,
                style: context.widgetValueStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.inkColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatGameDay(int day) {
    final year = ((day - 1) ~/ 365) + 1;
    final yearDay = ((day - 1) % 365) + 1;
    return 'Year $year, Day $yearDay';
  }

  static String _formatDuration(int days) {
    final years = days ~/ 365;
    final remaining = days % 365;
    return remaining == 0 ? '$years yrs' : '$years yrs, $remaining days';
  }
}
