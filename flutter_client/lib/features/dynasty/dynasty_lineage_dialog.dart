import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import 'dynasty_tree_dialog.dart';

void showDynastyLineageDialog(
  BuildContext context, {
  required Map<String, dynamic> dynasty,
  EarthState? state,
  EarthApi? api,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => DynastyLineageDialog(
      dynasty: dynasty,
      state: state,
      api: api,
    ),
  );
}

class DynastyLineageDialog extends StatelessWidget {
  final Map<String, dynamic> dynasty;
  final EarthState? state;
  final EarthApi? api;

  const DynastyLineageDialog({
    super.key,
    required this.dynasty,
    this.state,
    this.api,
  });

  @override
  Widget build(BuildContext context) {
    final name = (dynasty['dynasty_name'] ?? dynasty['name'] ?? 'Dynasty').toString();
    final founder = (dynasty['founder_name'] ?? dynasty['founder'] ?? 'Founder').toString();
    final heir = (dynasty['active_heir'] ?? dynasty['heir'] ?? '—').toString();
    final motto = dynasty['motto']?.toString() ?? dynasty['description']?.toString();
    final seat = dynasty['seat']?.toString() ?? dynasty['seat_city']?.toString() ?? dynasty['city_name']?.toString();

    final gen = int.tryParse((dynasty['generation'] ?? dynasty['generations'] ?? 1).toString()) ?? 1;
    final ancestors = int.tryParse((dynasty['deceased_count'] ?? dynasty['ancestors_count'] ?? 0).toString()) ?? 0;
    final legacy = int.tryParse((dynasty['total_legacy'] ?? dynasty['peak_legacy'] ?? dynasty['legacy'] ?? 0).toString()) ?? 0;
    final standing = int.tryParse((dynasty['peak_standing'] ?? dynasty['dynastic_standing'] ?? dynasty['standing'] ?? 0).toString()) ?? 0;

    final isExtinct = dynasty['is_extinct'] == true ||
        dynasty['status'] == 'extinct' ||
        dynasty['status'] == 'deceased' ||
        dynasty['status'] == 'historical' ||
        (heir.isEmpty || heir == '—');

    final foundedRaw = dynasty['founded_game_day'] ?? dynasty['birth_game_day'] ?? dynasty['founded_day'] ?? 1;
    final foundedDayNum = int.tryParse(foundedRaw.toString()) ?? 1;
    final fYear = ((foundedDayNum - 1) ~/ 365) + 1;
    final fDay = ((foundedDayNum - 1) % 365) + 1;

    final currentDayNum = int.tryParse((dynasty['current_game_day'] ?? dynasty['game_day'] ?? 1200).toString()) ?? 1200;
    final totalDays = (currentDayNum - foundedDayNum).clamp(0, 9999999);
    final ageY = totalDays ~/ 365;

    final dynastyScore = dynasty['dynasty_score'] ??
        dynasty['score'] ??
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
      'role': 'Established the dynastic seat and foundational charter.',
    });

    // 2. Intermediary Ancestors (if Gen > 2)
    if (gen > 2) {
      for (int g = 2; g < gen; g++) {
        treeNodes.add({
          'gen': g,
          'name': '$name Ancestor Gen $g',
          'title': 'Dynastic Heir & Inscribed Ancestor',
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
        'title': isExtinct ? 'Extinct Dynastic Branch' : 'Current Dynastic Head & Active Heir',
        'isFounder': false,
        'isLiving': !isExtinct,
        'period': isExtinct ? 'Historical Concluded' : 'Active Reign on Earth',
        'legacy': legacy,
        'role': isExtinct
            ? 'Lineage concluded with no registered living heir.'
            : 'Leading the house across planetary governance and economic syndicates.',
      });
    }

    final isMyDynasty = state != null &&
        ((state!.human['dynasty_name']?.toString() == name) ||
            (state!.human['dynastyName']?.toString() == name) ||
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isExtinct ? Colors.white24 : const Color(0xffeab308)).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isExtinct ? Colors.white24 : const Color(0xffeab308)).withValues(alpha: .4),
                      ),
                    ),
                    child: Icon(
                      isExtinct ? Icons.hourglass_disabled : Icons.military_tech,
                      color: isExtinct ? Colors.white70 : const Color(0xffeab308),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            EarthStatusPill(
                              label: isExtinct ? 'EXTINCT' : 'GEN $gen',
                              value: isExtinct ? 'HISTORICAL' : 'ACTIVE',
                              color: isExtinct ? Colors.white60 : const Color(0xffeab308),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Founded: Year $fYear, Day $fDay · Lifespan: $ageY years${seat != null && seat.isNotEmpty && seat != '—' ? ' · Seat: $seat' : ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (motto != null && motto.isNotEmpty && motto != '—') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.format_quote, size: 16, color: Color(0xffeab308)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '“$motto”',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Top Metric Grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricChip('PRESTIGE SCORE', '$dynastyScore PTS', const Color(0xffeab308), Icons.emoji_events_outlined),
                        _metricChip('DYNASTIC LEGACY', '$legacy LP', cyanAccentColor, Icons.stars_outlined),
                        _metricChip('DYNASTIC STANDING', '$standing Std', Colors.tealAccent, Icons.shield_outlined),
                        _metricChip('ANCESTORS', '$ancestors Inscribed', Colors.orangeAccent, Icons.history_edu),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Dynastic Succession Lineage Section
                    Row(
                      children: [
                        const Icon(Icons.account_tree_outlined, size: 16, color: cyanAccentColor),
                        const SizedBox(width: 8),
                        const Text(
                          'DYNASTIC SUCCESSION & LINEAGE TREE',
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

                      final nodeColor = isFounder
                          ? const Color(0xffeab308)
                          : (isLiving ? cyanAccentColor : Colors.white60);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left visual timeline track
                          SizedBox(
                            width: 32,
                            child: Column(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: nodeColor.withValues(alpha: .15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: nodeColor, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'G${node['gen']}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: nodeColor,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!isLast)
                                  Container(
                                    width: 2,
                                    height: 52,
                                    color: Colors.white12,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Node details card
                          Expanded(
                            child: Container(
                              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: nodeColor.withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: nodeColor.withValues(alpha: .25)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          node['name'].toString(),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: isLiving ? Colors.white : Colors.white70,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: nodeColor.withValues(alpha: .15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          node['period'].toString(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: nodeColor,
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
                                      fontWeight: FontWeight.w600,
                                      color: nodeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    node['role'].toString(),
                                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                  if (isMyDynasty && api != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xffeab308),
                        side: const BorderSide(color: Color(0xffeab308)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('MANAGE MY DYNASTY'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        showDynastyTreeDialog(context, api: api!, state: state);
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
