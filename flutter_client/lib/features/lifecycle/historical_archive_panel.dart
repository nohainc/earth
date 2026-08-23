import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';

class HistoricalArchivePanel extends StatelessWidget {
  final Map<String, dynamic> pantheon;
  final List<dynamic> events;

  const HistoricalArchivePanel({
    super.key,
    required this.pantheon,
    this.events = const [],
  });

  @override
  Widget build(BuildContext context) {
    final deceased = _list(pantheon['deceasedPantheon'] ?? pantheon['deceased']);
    final dynasties = _list(pantheon['dynasties'] ?? pantheon['dynasticHouses']);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EarthSection(
            title: 'HISTORICAL ARCHIVE',
            showSurface: false,
            infoBulletPoints: const [
              'The archive preserves people, dynasties, and world decisions after they leave the active command loop.',
              'Use it to understand what earlier generations built and which civic choices shaped the present.',
              'This is historical context, not another action queue.',
            ],
            child: EarthMetricGrid(
              metrics: [
                EarthMetricTile(
                  label: 'ARCHIVED CITIZENS',
                  value: deceased.length.toString(),
                  icon: Icons.account_box_outlined,
                  accentColor: context.primaryColor,
                ),
                EarthMetricTile(
                  label: 'RECORDED DYNASTIES',
                  value: dynasties.length.toString(),
                  icon: Icons.account_tree_outlined,
                  accentColor: context.secondaryColor,
                ),
              ],
            ),
          ),
          SizedBox(height: context.spacingSection),
          EarthSection(
            title: 'ANCESTORS & PANTHEON',
            showSurface: false,
            child: deceased.isEmpty
                ? const EarthEmptyState(
                    message: 'No citizens have entered the public archive yet.',
                    icon: Icons.account_box_outlined,
                  )
                : EarthDataList(
                    children: deceased.take(20).indexed.map((indexed) {
                      final raw = indexed.$2;
                      final isLast = indexed.$1 == deceased.take(20).length - 1;
                      final row = raw is Map
                          ? Map<String, dynamic>.from(raw)
                          : const <String, dynamic>{};
                      final name =
                          (row['display_name'] ?? row['name'] ?? 'Archived citizen').toString();
                      final subtitle =
                          'Day ${row['death_game_day'] ?? row['game_day'] ?? '—'} · ${row['dynasty_name'] ?? row['dynasty'] ?? 'Unknown house'}';
                      return EarthDataRow(
                        title: name,
                        subtitle: subtitle,
                        leading: Icon(
                          Icons.person_outline,
                          size: context.iconSize,
                          color: context.primaryColor,
                        ),
                        showDivider: !isLast,
                      );
                    }).toList(),
                  ),
          ),
          SizedBox(height: context.spacingSection),
          EarthSection(
            title: 'RECORDED DYNASTIES',
            showSurface: false,
            child: dynasties.isEmpty
                ? const EarthEmptyState(
                    message: 'No dynasties have been archived yet.',
                    icon: Icons.account_tree_outlined,
                  )
                : EarthDataList(
                    children: dynasties.take(20).indexed.map((indexed) {
                      final raw = indexed.$2;
                      final isLast = indexed.$1 == dynasties.take(20).length - 1;
                      final row = raw is Map
                          ? Map<String, dynamic>.from(raw)
                          : const <String, dynamic>{};
                      final name =
                          (row['dynasty_name'] ?? row['name'] ?? 'Dynastic house').toString();
                      final subtitle =
                          '${row['deceased_count'] ?? row['generations'] ?? row['generation'] ?? '—'} generations/records · ${row['peak_legacy'] ?? row['legacy_points'] ?? '—'} legacy';
                      return EarthDataRow(
                        title: name,
                        subtitle: subtitle,
                        leading: Icon(
                          Icons.account_tree_outlined,
                          size: context.iconSize,
                          color: context.secondaryColor,
                        ),
                        showDivider: !isLast,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _list(dynamic value) => value is List ? value : const [];
}

class HistoricalDynastiesPanel extends StatelessWidget {
  final Map<String, dynamic> pantheon;
  const HistoricalDynastiesPanel({super.key, required this.pantheon});

  @override
  Widget build(BuildContext context) {
    final rows = pantheon['dynasties'] ?? pantheon['dynasticHouses'];
    final dynasties = rows is List ? rows : const <dynamic>[];
    return EarthSection(
      title: 'DYNASTIES',
      showSurface: false,
      child: dynasties.isEmpty
          ? const EarthEmptyState(
              message: 'No historical dynasties recorded.',
              icon: Icons.account_tree_outlined,
            )
          : EarthDataList(
              children: dynasties.take(20).indexed.map((indexed) {
                final raw = indexed.$2;
                final isLast = indexed.$1 == dynasties.take(20).length - 1;
                final row = raw is Map
                    ? Map<String, dynamic>.from(raw)
                    : const <String, dynamic>{};
                final name =
                    (row['dynasty_name'] ?? row['name'] ?? 'Dynastic house').toString();
                final subtitle =
                    '${row['deceased_count'] ?? row['generations'] ?? row['generation'] ?? '—'} generations/records · ${row['peak_legacy'] ?? row['legacy_points'] ?? '—'} legacy';
                return EarthDataRow(
                  title: name,
                  subtitle: subtitle,
                  leading: Icon(
                    Icons.account_tree_outlined,
                    size: context.iconSize,
                    color: context.primaryColor,
                  ),
                  showDivider: !isLast,
                );
              }).toList(),
            ),
    );
  }
}
