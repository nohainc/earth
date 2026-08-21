import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/earth_primitives.dart';

class HistoricalArchivePanel extends StatelessWidget {
  final Map<String, dynamic> pantheon;
  final List<dynamic> events;

  const HistoricalArchivePanel(
      {super.key, required this.pantheon, this.events = const []});

  @override
  Widget build(BuildContext context) {
    final deceased =
        _list(pantheon['deceasedPantheon'] ?? pantheon['deceased']);
    final dynasties =
        _list(pantheon['dynasties'] ?? pantheon['dynasticHouses']);
    final milestones = events.whereType<Map>().take(12).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EarthPanel(
        title: 'HISTORICAL ARCHIVE',
        showSurface: false,
        contentPadding: EdgeInsets.zero,
        helpAfterTitle: true,
        titleColor: mutedColor,
        infoDescription:
            '• The archive preserves people, dynasties, and world decisions after they leave the active command loop.\n\n• Use it to understand what earlier generations built and which civic choices shaped the present.\n\n• This is historical context, not another action queue.',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          _metric('ARCHIVED CITIZENS', deceased.length.toString(),
              Icons.account_box_outlined, cyanAccentColor),
          _metric('RECORDED DYNASTIES', dynasties.length.toString(),
              Icons.account_tree_outlined, violetColor),
          _metric('VISIBLE MILESTONES', milestones.length.toString(),
              Icons.public_outlined, Colors.amberAccent),
        ]),
      ),
      const SizedBox(height: 24),
      _section(
          'ANCESTORS & PANTHEON',
          Icons.account_box_outlined,
          deceased.isEmpty
              ? _empty('No citizens have entered the public archive yet.')
              : Column(children: deceased.take(12).map(_personRow).toList())),
      const SizedBox(height: 24),
      _section(
          'DYNASTIC HOUSES',
          Icons.account_tree_outlined,
          dynasties.isEmpty
              ? _empty('No dynasty records are available yet.')
              : Column(children: dynasties.take(12).map(_dynastyRow).toList())),
      const SizedBox(height: 24),
      _section(
          'WORLD MILESTONES',
          Icons.public_outlined,
          milestones.isEmpty
              ? _empty(
                  'World milestones will appear as the persistent world advances.')
              : Column(children: milestones.map(_eventRow).toList())),
    ]);
  }

  List<dynamic> _list(dynamic value) => value is List ? value : const [];

  Widget _section(String title, IconData icon, Widget child) => EarthPanel(
      title: title,
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      titleColor: mutedColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 16, color: cyanAccentColor),
          const SizedBox(width: 7),
          Text(title,
              style: const TextStyle(
                  color: inkColor, fontSize: 11, fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 10),
        child,
      ]));

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Container(
          width: 170,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: .28))),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  Text(label,
                      style: const TextStyle(color: mutedColor, fontSize: 8.5))
                ]))
          ]));

  Widget _personRow(dynamic raw) {
    final row =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return _row(
        Icons.person_outline,
        (row['display_name'] ?? row['name'] ?? 'Archived citizen').toString(),
        'Day ${row['death_game_day'] ?? row['game_day'] ?? '—'} · ${row['dynasty_name'] ?? row['dynasty'] ?? 'Unknown house'}',
        cyanAccentColor);
  }

  Widget _dynastyRow(dynamic raw) {
    final row =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return _row(
        Icons.account_tree_outlined,
        (row['dynasty_name'] ?? row['name'] ?? 'Dynastic house').toString(),
        '${row['deceased_count'] ?? row['generations'] ?? row['generation'] ?? '—'} generations/records · ${row['peak_legacy'] ?? row['legacy_points'] ?? '—'} legacy',
        violetColor);
  }

  Widget _eventRow(dynamic raw) {
    final row =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return _row(
        Icons.public_outlined,
        (row['title'] ?? row['event_type'] ?? 'World event').toString(),
        'Game day ${row['game_day'] ?? '—'}',
        Colors.amberAccent);
  }

  Widget _row(IconData icon, String title, String subtitle, Color color) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: mutedColor, fontSize: 9.5))
                ]))
          ]));

  Widget _empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text,
          style: const TextStyle(color: mutedColor, fontSize: 10.5)));
}
