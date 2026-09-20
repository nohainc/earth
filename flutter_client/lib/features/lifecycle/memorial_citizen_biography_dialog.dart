import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/memorial_models.dart';
import '../../shared/design_system/design_system.dart';

Future<void> showMemorialCitizenBiographyDialog(
  BuildContext context, {
  required String humanId,
  required EarthApi api,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _MemorialCitizenBiographyDialog(humanId: humanId, api: api),
  );
}

class _MemorialCitizenBiographyDialog extends StatelessWidget {
  final String humanId;
  final EarthApi api;

  const _MemorialCitizenBiographyDialog({required this.humanId, required this.api});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CITIZEN BIOGRAPHY'),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<MemorialCitizenDetail>(
          future: api.memorialCitizenBiography(humanId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Text('This archival biography is unavailable.');
            }
            return _BiographyContent(citizen: snapshot.data!);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CLOSE'))],
    );
  }
}

class _BiographyContent extends StatelessWidget {
  final MemorialCitizenDetail citizen;
  const _BiographyContent({required this.citizen});

  String _day(int? day) {
    if (day == null) return 'UNAVAILABLE';
    final year = ((day - 1) ~/ 365) + 1;
    final withinYear = ((day - 1) % 365) + 1;
    return 'Year $year, Day $withinYear';
  }

  String _label(String value) => value.replaceAll('_', ' ').toLowerCase().split(' ').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    final summary = citizen.lifetimeSummary;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(citizen.displayName, style: context.widgetTitleStyle),
        const SizedBox(height: 4),
        Text('${citizen.houseName ?? 'House unavailable'}${citizen.generation == null ? '' : ' · Generation ${citizen.generation}'}', style: context.bodyStyle.copyWith(color: context.mutedColor)),
        const SizedBox(height: 16),
        _section(context, 'LIFE', [
          'Born  ${_day(citizen.birthGameDay)}',
          'Died  ${_day(citizen.deathGameDay)}',
          'Age  ${citizen.ageYears == null ? 'UNAVAILABLE' : '${citizen.ageYears} years'}',
          'Final standing  ${citizen.finalStanding ?? 'UNAVAILABLE'}',
          'Personal legacy  ${citizen.finalLegacy ?? 'UNAVAILABLE'}',
          if (citizen.successorName != null) 'Successor  ${citizen.successorName}',
          if (citizen.causeOfDeathCode != null) 'Cause  ${_label(citizen.causeOfDeathCode!)}',
          if (citizen.corporationName != null) 'Corporation at death  ${citizen.corporationName}',
        ]),
        if (citizen.epitaph?.isNotEmpty == true) _section(context, 'TESTAMENT', ['“${citizen.epitaph}”']),
        if (citizen.offices.isNotEmpty) _section(context, 'RECORDED OFFICES', citizen.offices.map((office) => '${office.roleName}${office.institutionName == null ? '' : ' · ${office.institutionName}'}').toList()),
        _section(context, 'LIFETIME SUMMARY', [
          'Governance events  ${summary.governanceEventCount}',
          'Research events  ${summary.researchEventCount}',
          'Building events  ${summary.buildingEventCount}',
          'Initiative events  ${summary.initiativeEventCount}',
        ]),
        if (citizen.achievements.isNotEmpty) _section(context, 'RECORDED ACHIEVEMENTS', citizen.achievements.map((event) => '${event.title} · ${_day(event.gameDay)}').toList()),
      ]),
    );
  }

  Widget _section(BuildContext context, String title, List<String> lines) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: context.captionStyle.copyWith(color: context.mutedColor, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(line, style: context.bodyStyle))),
    ]),
  );
}
