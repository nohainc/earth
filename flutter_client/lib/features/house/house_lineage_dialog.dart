import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import 'house_tree_dialog.dart';

void showHouseLineageDialog(
  BuildContext context, {
  required Map<String, dynamic> house,
  EarthState? state,
  EarthApi? api,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => HouseLineageDialog(
      house: house,
      state: state,
      api: api,
    ),
  );
}

// Backwards compatibility alias
void showDynastyLineageDialog(
  BuildContext context, {
  required Map<String, dynamic> dynasty,
  EarthState? state,
  EarthApi? api,
}) =>
    showHouseLineageDialog(context, house: dynasty, state: state, api: api);

typedef DynastyLineageDialog = HouseLineageDialog;

class HouseLineageDialog extends StatelessWidget {
  final Map<String, dynamic> house;
  final EarthState? state;
  final EarthApi? api;

  const HouseLineageDialog({
    super.key,
    required this.house,
    this.state,
    this.api,
  });

  @override
  Widget build(BuildContext context) {
    final name = (house['house_name'] ?? house['dynasty_name'] ?? house['name'] ?? 'House').toString();
    final founder = (house['founder_name'] ?? house['founder'] ?? 'Founder').toString();
    final heir = (house['active_heir'] ?? house['heir'] ?? '—').toString();
    final motto = house['motto']?.toString() ?? house['description']?.toString();
    final seat = house['seat']?.toString() ?? house['seat_city']?.toString() ?? house['city_name']?.toString();

    final gen = int.tryParse((house['generation'] ?? house['generations'] ?? 1).toString()) ?? 1;
    final ancestors = int.tryParse((house['deceased_count'] ?? house['ancestors_count'] ?? 0).toString()) ?? 0;
    final legacy = int.tryParse((house['total_legacy'] ?? house['peak_legacy'] ?? house['legacy'] ?? 0).toString()) ?? 0;
    final standing = int.tryParse((house['peak_standing'] ?? house['house_standing'] ?? house['dynastic_standing'] ?? house['standing'] ?? 0).toString()) ?? 0;

    final isExtinct = house['is_extinct'] == true ||
        house['status'] == 'extinct' ||
        house['status'] == 'deceased' ||
        house['status'] == 'historical' ||
        (heir.isEmpty || heir == '—');

    final foundedRaw = house['founded_game_day'] ?? house['birth_game_day'] ?? house['founded_day'] ?? 1;
    final foundedDayNum = int.tryParse(foundedRaw.toString()) ?? 1;
    final fYear = ((foundedDayNum - 1) ~/ 365) + 1;
    final fDay = ((foundedDayNum - 1) % 365) + 1;

    final currentDayNum = int.tryParse((house['current_game_day'] ?? house['game_day'] ?? 1200).toString()) ?? 1200;
    final totalDays = (currentDayNum - foundedDayNum).clamp(0, 9999999);
    final ageY = totalDays ~/ 365;

    final houseScore = house['house_score'] ??
        house['dynasty_score'] ??
        house['score'] ??
        (legacy * 50 + standing * 10 + ageY * 2 + ancestors * 20);

    // Build visual generational tree nodes
    final treeNodes = <Map<String, dynamic>>[];

    // 1. Founder Node (Gen 1)
    treeNodes.add({
      'gen': 1,
      'name': founder,
      'title': 'Progenitor & House Founder',
      'isFounder': true,
      'isLiving': gen == 1 && !isExtinct,
      'period': 'Year $fYear, Day $fDay',
      'legacy': gen == 1 ? legacy : (legacy ~/ (gen > 1 ? gen : 1)),
      'role': 'Established the ancestral seat and foundational charter.',
    });

    // 2. Intermediary Ancestors (if Gen > 2)
    if (gen > 2) {
      for (int g = 2; g < gen; g++) {
        treeNodes.add({
          'gen': g,
          'name': '$name Ancestor Gen $g',
          'title': 'House Heir & Inscribed Ancestor',
          'isFounder': false,
          'isLiving': false,
          'period': 'Passed · Inscribed in Pantheon',
          'legacy': (legacy ~/ gen),
          'role': 'Expanded institutional standing and generational wealth.',
        });
      }
    }

    // 3. Active Heir / Head of House Node (or Concluded if extinct)
    if (gen > 1 || isExtinct) {
      treeNodes.add({
        'gen': gen,
        'name': isExtinct ? 'Lineage Extinct' : heir,
        'title': isExtinct ? 'Extinct House Branch' : 'Current Head of House & Active Heir',
        'isFounder': false,
        'isLiving': !isExtinct,
        'period': isExtinct ? 'Historical Concluded' : 'Active Reign on Earth',
        'legacy': legacy,
        'role': isExtinct
            ? 'Lineage concluded with no registered living heir.'
            : 'Leading the house across planetary governance and economic syndicates.',
      });
    }

    final isMyHouse = state != null &&
        ((state!.human['house_name']?.toString() == name) ||
            (state!.human['houseName']?.toString() == name) ||
            (state!.human['dynasty_name']?.toString() == name) ||
            (state!.human['dynastyName']?.toString() == name) ||
            (state!.life['house'] is Map && state!.life['house']['house_name']?.toString() == name) ||
            (state!.life['dynasty'] is Map && state!.life['dynasty']['dynasty_name']?.toString() == name));

    return Dialog(
      backgroundColor: EarthColors.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
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
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isExtinct
                          ? Colors.grey.withValues(alpha: .15)
                          : const Color(0xffeab308).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isExtinct
                            ? Colors.grey.withValues(alpha: .3)
                            : const Color(0xffeab308).withValues(alpha: .3),
                      ),
                    ),
                    child: Icon(
                      isExtinct ? Icons.account_balance : Icons.shield_outlined,
                      color: isExtinct ? Colors.grey : const Color(0xffeab308),
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isExtinct
                                    ? Colors.redAccent.withValues(alpha: .15)
                                    : Colors.greenAccent.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isExtinct
                                      ? Colors.redAccent.withValues(alpha: .3)
                                      : Colors.greenAccent.withValues(alpha: .3),
                                ),
                              ),
                              child: Text(
                                isExtinct ? 'HISTORICAL' : 'ACTIVE LINEAGE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: isExtinct ? Colors.redAccent : Colors.greenAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Generation $gen · Founded Year $fYear, Day $fDay · $ancestors Inscribed Ancestors',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
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
                    // Founder & Seat Summary
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: EarthColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'FOUNDER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  founder,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: EarthColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ACTIVE HEIR',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  heir,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isExtinct ? Colors.white54 : cyanAccentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (seat != null && seat.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: EarthColors.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_city, size: 14, color: Colors.white54),
                            const SizedBox(width: 8),
                            const Text('Seat City: ', style: TextStyle(fontSize: 12, color: Colors.white54)),
                            Text(seat, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Top Metric Grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricChip('PRESTIGE SCORE', '$houseScore PTS', const Color(0xffeab308), Icons.emoji_events_outlined),
                        _metricChip('HOUSE LEGACY', '$legacy LP', cyanAccentColor, Icons.stars_outlined),
                        _metricChip('HOUSE STANDING', '$standing Std', Colors.tealAccent, Icons.shield_outlined),
                        _metricChip('ANCESTORS', '$ancestors Inscribed', Colors.orangeAccent, Icons.history_edu),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // House Succession Lineage Section
                    const Row(
                      children: [
                        Icon(Icons.account_tree_outlined, size: 16, color: cyanAccentColor),
                        SizedBox(width: 8),
                        Text(
                          'HOUSE SUCCESSION & LINEAGE TREE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: cyanAccentColor,
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
                      final isFounder = node['isFounder'] == true;

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
                                      color: isFounder
                                          ? const Color(0xffeab308).withValues(alpha: .2)
                                          : (isLiving
                                              ? cyanAccentColor.withValues(alpha: .2)
                                              : Colors.white10),
                                      border: Border.all(
                                        color: isFounder
                                            ? const Color(0xffeab308)
                                            : (isLiving ? cyanAccentColor : Colors.white30),
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'G${node['gen']}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isFounder
                                            ? const Color(0xffeab308)
                                            : (isLiving ? cyanAccentColor : Colors.white70),
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        color: isFounder
                                            ? const Color(0xffeab308).withValues(alpha: .3)
                                            : Colors.white12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Node Card
                            Expanded(
                              child: Container(
                                margin: EdgeInsets.only(bottom: isLast ? 0 : 16),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: EarthColors.cardSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isFounder
                                        ? const Color(0xffeab308).withValues(alpha: .3)
                                        : (isLiving
                                            ? cyanAccentColor.withValues(alpha: .3)
                                            : Colors.white12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            node['name'].toString(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isFounder
                                                  ? const Color(0xffeab308)
                                                  : (isLiving ? Colors.white : Colors.white70),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isLiving
                                                ? Colors.greenAccent.withValues(alpha: .1)
                                                : Colors.white10,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            node['period'].toString(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isLiving ? Colors.greenAccent : Colors.white54,
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
                                        color: isFounder
                                            ? const Color(0xffeab308).withValues(alpha: .8)
                                            : (isLiving ? cyanAccentColor : Colors.white54),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      node['role'].toString(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.stars_outlined, size: 12, color: cyanAccentColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${node['legacy']} Legacy Generated',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: cyanAccentColor,
                                          ),
                                        ),
                                      ],
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
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isMyHouse && api != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xffeab308),
                        side: const BorderSide(color: Color(0xffeab308)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    child: const Text('CLOSE', style: TextStyle(color: cyanAccentColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color, IconData icon) {
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
