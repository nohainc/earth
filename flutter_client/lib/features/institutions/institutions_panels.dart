import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'institutions_dialogs.dart';

class CorporationDirectoryPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CorporationDirectoryPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<CorporationDirectoryPanel> createState() =>
      _CorporationDirectoryPanelState();
}

class _CorporationDirectoryPanelState extends State<CorporationDirectoryPanel> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _corporations = const [];
  Map<String, dynamic>? _selected;
  bool _loading = true;

  bool get _isMember => widget.state.membership?['corporation_id'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CorporationDirectoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.membership?['corporation_id'] !=
        widget.state.membership?['corporation_id']) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isMember) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows =
          await const EarthApi().listCorporations(search: _search.text);
      if (!mounted) return;
      setState(() {
        _corporations = rows;
        _selected = rows.isEmpty
            ? null
            : (_selected == null
                ? rows.first
                : rows.firstWhere((row) => row['id'] == _selected!['id'],
                    orElse: () => rows.first));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final id = _selected?['id']?.toString();
    if (id == null) return;
    await widget
        .action(() => const EarthApi().joinCorporation(corporationId: id));
  }

  Future<void> _leave() async {
    final id = widget.state.membership?['corporation_id']?.toString();
    if (id == null) return;
    await widget
        .action(() => const EarthApi().leaveCorporation(corporationId: id));
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(
            widget.state.institutions['corporation'] as Map)
        : const <String, dynamic>{};
    return EarthPanel(
      title: 'CORPORATION / FIND YOUR NETWORK',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Independent people can compare active corporations and choose a network.\n\n• Every corporation has a capital city. Joining places you there automatically.\n\n• Open corporations accept members immediately; approval corporations create a request for their administrators.\n\n• Once affiliated, leave your current corporation before choosing another one.',
      child: _isMember ? _memberView(current) : _directoryView(),
    );
  }

  Widget _memberView(Map<String, dynamic> current) {
    final name = current['name']?.toString() ?? 'your corporation';
    final city = current['capital_city_name']?.toString() ??
        widget.state.membership?['city_id']?.toString() ??
        'capital city';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _statusCard(Icons.verified_user_outlined, 'AFFILIATED',
          'You are a member of $name. Your corporation membership places you in its capital city: $city.'),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: widget.busy ? null : _leave,
        icon: const Icon(Icons.logout, size: 15),
        label: const Text('LEAVE CORPORATION'),
      ),
      const SizedBox(height: 7),
      const Text(
          'Leaving ends the corporation-city affiliation and returns you to the independent ruleset.',
          style: TextStyle(color: mutedColor, fontSize: 10)),
    ]);
  }

  Widget _directoryView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 17),
              hintText: 'Search corporations',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18)),
      ]),
      const SizedBox(height: 12),
      if (_loading)
        const LinearProgressIndicator()
      else if (_corporations.isEmpty)
        _statusCard(Icons.search_off, 'NO MATCHES',
            'No active corporations match this search.')
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  children: _corporations.map(_corporationRow).toList())),
          if (_selected != null) ...[
            const SizedBox(width: 14),
            Expanded(child: _details(_selected!)),
          ],
        ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: widget.busy || widget.state.membership?['city_id'] == null
            ? null
            : () => showFormationComposer(context, widget.action,
                city: false,
                cityId: widget.state.membership?['city_id']?.toString()),
        icon: const Icon(Icons.add_business, size: 16),
        label: const Text('CREATE CORPORATION'),
      ),
      if (widget.state.membership?['city_id'] == null)
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Text(
              'Join a city before founding a corporation so it has a capital city.',
              style: TextStyle(color: mutedColor, fontSize: 10)),
        ),
    ]);
  }

  Widget _corporationRow(Map<String, dynamic> row) {
    final selected = _selected?['id'] == row['id'];
    return InkWell(
      onTap: () => setState(() => _selected = row),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? cyanAccentColor.withValues(alpha: .10)
              : surfaceColor.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? cyanAccentColor : Colors.white12),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_outlined,
              size: 16, color: cyanAccentColor),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    row['name']?.toString() ??
                        row['id']?.toString() ??
                        'Corporation',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                    '${row['member_count'] ?? 0} members · ${row['capital_city_name'] ?? 'capital city'}',
                    style: const TextStyle(color: mutedColor, fontSize: 9.5)),
              ])),
        ]),
      ),
    );
  }

  Widget _details(Map<String, dynamic> row) {
    final approval = row['admission_policy']?.toString() == 'approval';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: violetColor.withValues(alpha: .28))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(row['name']?.toString() ?? 'Corporation',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Capital city: ${row['capital_city_name'] ?? 'not assigned'}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        Text('Network cities: ${row['city_count'] ?? 0}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        Text('Members: ${row['member_count'] ?? 0}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 10),
        Text(approval ? 'ADMISSION: ADMIN APPROVAL' : 'ADMISSION: OPEN',
            style: TextStyle(
                color: approval ? Colors.orangeAccent : Colors.tealAccent,
                fontSize: 9,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: widget.busy ? null : _join,
            child: Text(approval ? 'REQUEST MEMBERSHIP' : 'JOIN CORPORATION')),
      ]),
    );
  }

  Widget _statusCard(IconData icon, String label, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: cyanAccentColor.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cyanAccentColor.withValues(alpha: .22))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: cyanAccentColor, size: 19),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: cyanAccentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 11, height: 1.3)),
              ])),
        ]),
      );
}

class CivicRankingsPanel extends StatelessWidget {
  final EarthState state;
  const CivicRankingsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'CIVIC / CORPORATION & CITY RANKINGS',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          'Compare institutions by the measures that shape civic life: productive membership, city services, and resilience—not treasury alone.',
      child: LayoutBuilder(builder: (context, constraints) {
        final corp = _rows(state.rankings['corporations']);
        final cities = _rows(state.rankings['cities']);
        final wide = constraints.maxWidth > 700;
        final children = [
          _rankingColumn(
              'CORPORATIONS', corp, Icons.account_balance_outlined, 'members'),
          _rankingColumn(
              'CITIES', cities, Icons.location_city_outlined, 'residents'),
        ];
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: children[0]),
                const SizedBox(width: 18),
                Expanded(child: children[1])
              ])
            : Column(children: [
                children[0],
                const SizedBox(height: 18),
                children[1]
              ]);
      }),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .take(10)
          .toList()
      : const [];

  Widget _rankingColumn(String title, List<Map<String, dynamic>> rows,
          IconData icon, String secondary) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: inkColor, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        if (rows.isEmpty)
          const Text('No ranking data available.',
              style: TextStyle(color: mutedColor, fontSize: 10)),
        ...rows.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text('#${entry.key + 1}',
                  style: const TextStyle(
                      color: cyanAccentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Icon(icon, size: 14, color: mutedColor),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      entry.value['name']?.toString() ??
                          entry.value['id']?.toString() ??
                          'Institution',
                      style: const TextStyle(fontSize: 10.5))),
              Text(
                  '${entry.value[secondary] ?? entry.value['member_count'] ?? 0}',
                  style: const TextStyle(color: mutedColor, fontSize: 9.5)),
            ]))),
      ]);
}

class CorporationOverviewPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function())? action;

  const CorporationOverviewPanel(
      {super.key, required this.state, this.busy = false, this.action});

  @override
  Widget build(BuildContext context) {
    final corporation = state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(state.institutions['corporation'] as Map)
        : const <String, dynamic>{};
    final membership = state.membership ?? const <String, dynamic>{};
    final name = (corporation['name'] ?? 'Independent').toString();
    final id = corporation['id']?.toString() ?? '—';
    final memberCount = asIntOr(corporation['member_count'], 0);
    final treasury = asDouble(corporation['treasury']);
    final sharedPatents = state.technology['corporationSharedPatents'] is List
        ? state.technology['corporationSharedPatents'] as List
        : const <dynamic>[];
    final cities = List<dynamic>.from(state.rankings['corporations'] is List
        ? state.rankings['corporations'] as List
        : const [])
      ..sort((a, b) => (asInt((b as Map)['member_count']) ?? 0)
          .compareTo(asInt((a as Map)['member_count']) ?? 0));
    final isMember = membership['corporation_id'] != null;
    final cityId = membership['city_id']?.toString();
    final canAdoptCity = state.roles.any((raw) {
      if (raw is! Map) return false;
      final role = raw['role_name'] ?? raw['name'] ?? raw['role'];
      return raw['status']?.toString() == 'active' &&
          role?.toString().toLowerCase() == 'corporation executive';
    });

    return EarthPanel(
      title: 'CORPORATION / MEMBERSHIP & DIRECTION',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Corporation membership determines which shared rules, cities, technologies, contracts, and services are available to you.\n\n• A city belongs to a corporation: moving between cities changes your local services and opportunities while preserving corporation membership.\n\n• Independent people use Earth default rules and do not participate in corporation decisions.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            isMember
                ? 'You belong to $name.'
                : 'You are currently independent.',
            style: TextStyle(
                color: isMember ? Colors.tealAccent : Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(
            isMember
                ? 'Your current city: ${cityId ?? 'not assigned'}. Corporation rules apply across every city in this network.'
                : 'Join a corporation to access shared cities, technologies, contracts, and civic influence.',
            style: const TextStyle(color: mutedColor, fontSize: 11)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _metric('CORPORATION', '$name\n$id', Icons.account_balance_outlined,
              cyanAccentColor),
          _metric(
              'MEMBERS', '$memberCount', Icons.groups_outlined, violetColor),
          _metric(
              'TREASURY',
              treasury == null
                  ? 'UNAVAILABLE'
                  : '${formatWholeNumber(treasury)} C',
              Icons.account_balance_wallet_outlined,
              Colors.amberAccent),
        ]),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cyanAccentColor.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: cyanAccentColor.withValues(alpha: .22)),
          ),
          child: Row(children: [
            const Icon(Icons.hub_outlined, size: 18, color: cyanAccentColor),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('CORPORATION RESEARCH COMMONS',
                      style: TextStyle(
                          color: cyanAccentColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5)),
                  const SizedBox(height: 3),
                  Text(
                      sharedPatents.isEmpty
                          ? 'No shared patents are visible yet.'
                          : '${sharedPatents.length} shared capabilities available to this corporation network.',
                      style: const TextStyle(color: mutedColor, fontSize: 10)),
                ])),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('CORPORATION DECISIONS',
            style: TextStyle(
                color: inkColor, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text(
            'Choose belonging · compare cities · support or challenge corporation rules · use shared technology · build a business network · move when another city offers a better future.',
            style: TextStyle(color: mutedColor, fontSize: 10.5)),
        if (isMember && id != '—') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => showTaxCharterDialog(
                    context, action ?? ((_) async {}), id,
                    corporation: true),
            icon: const Icon(Icons.gavel_outlined, size: 14),
            label: const Text('CORPORATION RULES'),
          ),
          if (canAdoptCity) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => showAdmissionPolicyDialog(
                        context,
                        action ?? ((_) async {}),
                        id,
                        currentPolicy:
                            corporation['admission_policy']?.toString() ??
                                'open',
                      ),
              icon: const Icon(Icons.how_to_reg_outlined, size: 14),
              label: Text(
                  corporation['admission_policy']?.toString() == 'approval'
                      ? 'ADMISSION: APPROVAL'
                      : 'ADMISSION: OPEN'),
            ),
          ],
        ],
        if (cities.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('CORPORATION RANKING',
              style: TextStyle(
                  color: inkColor, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...cities.take(5).toList().asMap().entries.map((entry) {
            final row = Map<String, dynamic>.from(entry.value as Map);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text('#${entry.key + 1}',
                    style:
                        const TextStyle(color: cyanAccentColor, fontSize: 10)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        row['name']?.toString() ??
                            row['id']?.toString() ??
                            'Corporation',
                        style: const TextStyle(fontSize: 10.5))),
                Text('${row['member_count'] ?? 0} members',
                    style: const TextStyle(color: mutedColor, fontSize: 10)),
              ]),
            );
          }),
        ],
        if (state.rankings['cities'] is List &&
            (state.rankings['cities'] as List).isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('CORPORATION CITY NETWORK',
              style: TextStyle(
                  color: inkColor, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...(state.rankings['cities'] as List).take(8).map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final city = row['id']?.toString() ?? 'City';
            final owner = row['corporation_id']?.toString();
            final belongsToUs = owner == id;
            final unclaimed = owner == null || owner.isEmpty;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(belongsToUs ? Icons.domain : Icons.location_city_outlined,
                    size: 14,
                    color: belongsToUs ? cyanAccentColor : mutedColor),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(
                  '${row['name'] ?? city} · ${row['residents'] ?? 0} residents',
                  style: const TextStyle(fontSize: 10.5),
                )),
                if (isMember && belongsToUs && city != cityId)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action?.call(
                            () => const EarthApi().joinCity(cityId: city)),
                    child: const Text('MOVE', style: TextStyle(fontSize: 9)),
                  )
                else if (isMember && unclaimed && canAdoptCity)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action?.call(() => const EarthApi()
                            .adoptCityForCorporation(
                                corporationId: id, cityId: city)),
                    child: const Text('ADOPT', style: TextStyle(fontSize: 9)),
                  )
                else
                  Text(owner == null ? 'UNCLAIMED' : owner,
                      style: TextStyle(
                          fontSize: 9,
                          color: belongsToUs ? cyanAccentColor : mutedColor)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .28))),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: mutedColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ])),
      ]),
    );
  }
}

class InstitutionsCapacityPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const InstitutionsCapacityPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['city'] is Map<String, dynamic>
        ? (state.institutions['city'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final cityId = city['id']?.toString() ?? 'CITY-0084';
    final cityName = (city['name']?.toString() ?? 'NEW CARTHAGE').toUpperCase();
    final residents = asIntOr(city['residents'], 100);
    final housingCap = asIntOr(city['housing_capacity'], 120);
    final energyCap = asIntOr(city['energy_capacity'], 200);

    final corp = state.institutions['corporation'] is Map<String, dynamic>
        ? (state.institutions['corporation'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final corporationId = corp['id']?.toString() ?? 'CORP-001';
    final corpName =
        (corp['name']?.toString() ?? 'CARTHAGE DYNAMICS').toUpperCase();
    final corpMembers = asIntOr(corp['member_count'], 42);
    final corpVersion = corp['constitution_version'] ?? 1;

    final isCityResident = state.membership?['city_id'] != null;
    final isCorpMember = state.membership?['corporation_id'] != null;

    final housingRatio =
        formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio =
        formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);
    final cityMembers = state.json['cityMembers'] is List
        ? List<dynamic>.from(state.json['cityMembers'] as List)
        : const <dynamic>[];
    final playerId = state.human['id']?.toString();
    final playerRank = cityMembers.indexWhere(
            (raw) => raw is Map && raw['id']?.toString() == playerId) +
        1;

    return EarthPanel(
      key: panelKey,
      title: 'INSTITUTIONS / CITY & CORP',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Municipal & Corporate Institutions: Legal entities established under the Planetary Constitution to manage collective urban infrastructure and private commercial enterprises.\n\n• Municipal Operations:\n  - Residency: Citizens affiliated with a city gain access to subsidized public services and municipal voting.\n  - Housing & Energy Capacity: Physical limits on municipal residency and industrial manufacturing.\n  - Service Pressure Ratios: Real-time telemetry monitoring municipal infrastructure load across housing, power, connectivity, and health.\n\n• Corporate Enterprises:\n  - Limited Liability Charters: Registered corporate entities providing shared commercial treasury funds and specialized manufacturing capabilities.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cyanAccentColor.withValues(alpha: .12),
                  surfaceColor.withValues(alpha: .78),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cyanAccentColor.withValues(alpha: .28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.alt_route_outlined, color: cyanAccentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('YOUR PLACE IN THE CITY',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: cyanAccentColor)),
                      const SizedBox(height: 5),
                      Text(
                        isCityResident
                            ? 'Residency gives you access to services and a civic voice. Service pressure affects living costs, staff quality of life, and the businesses you can operate.'
                            : 'Joining a city gives you services and a civic voice. Staying independent preserves flexibility but leaves you outside municipal decisions.',
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isCorpMember
                            ? 'Corporation membership gives access to shared contracts and influence, with obligations under its charter.'
                            : 'Corporation membership is optional: trade independence for shared contracts, technology access, and institutional influence.',
                        style: const TextStyle(fontSize: 10, color: mutedColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 1. CITY ADMINISTRATION COCKPIT CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cyanAccentColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_city_outlined,
                          size: 20, color: cyanAccentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'CITY: $cityName ($cityId)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isCityResident
                                          ? cyanAccentColor
                                          : mutedColor)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: (isCityResident
                                            ? cyanAccentColor
                                            : mutedColor)
                                        .withValues(alpha: .35),
                                  ),
                                ),
                                child: Text(
                                  isCityResident ? 'RESIDENT' : 'NON-RESIDENT',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color: isCityResident
                                        ? cyanAccentColor
                                        : mutedColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$residents residents · Housing cap: $housingCap · Energy cap: $energyCap',
                            style: const TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Service Pressure Gauges Box
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .03),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Service pressure: Housing $housingRatio · Energy $energyRatio · Connect $connectRatio · Health $healthRatio',
                    style: const TextStyle(
                      color: inkColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                if (isCityResident && cityMembers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('CITY STANDING',
                      style: TextStyle(
                          color: inkColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(
                    playerRank > 0
                        ? 'You rank #$playerRank among active residents by civic standing.'
                        : 'Resident standings are being established for this city.',
                    style: const TextStyle(color: mutedColor, fontSize: 10.5),
                  ),
                  const SizedBox(height: 6),
                  ...cityMembers.take(5).toList().asMap().entries.map((entry) {
                    final member =
                        Map<String, dynamic>.from(entry.value as Map);
                    final isPlayer = member['id']?.toString() == playerId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(
                            width: 24,
                            child: Text('#${entry.key + 1}',
                                style: const TextStyle(
                                    color: cyanAccentColor, fontSize: 10))),
                        Expanded(
                            child: Text(
                                member['display_name']?.toString() ??
                                    member['id']?.toString() ??
                                    'Resident',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isPlayer
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: isPlayer ? inkColor : mutedColor))),
                        Text('${member['standing'] ?? 0}',
                            style: const TextStyle(
                                color: mutedColor, fontSize: 10)),
                      ]),
                    );
                  }),
                ],

                const SizedBox(height: 12),

                // City Action Buttons Hub
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isCityResident
                            ? Colors.orangeAccent
                            : cyanAccentColor,
                        side: BorderSide(
                          color: (isCityResident
                                  ? Colors.orangeAccent
                                  : cyanAccentColor)
                              .withValues(alpha: .35),
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => isCityResident
                              ? const EarthApi().leaveCity(cityId: cityId)
                              : const EarthApi().joinCity(cityId: cityId)),
                      child: Text(
                        isCityResident ? 'LEAVE CITY' : 'JOIN CITY',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: inkColor,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .setCityBudget('maintenance', cityId: cityId)),
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 14),
                      label: const Text(
                        'PROPOSE BUDGET',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: violetColor,
                        side: BorderSide(
                            color: violetColor.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => showTaxCharterDialog(context, action, cityId),
                      icon: const Icon(Icons.receipt_long_outlined, size: 14),
                      label: const Text(
                        'TAX CHARTER',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (state.communities.isNotEmpty)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cyanAccentColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: busy
                            ? null
                            : () => showFormationComposer(
                                  context,
                                  action,
                                  city: true,
                                  communityId: (state.communities.first
                                      as Map<String, dynamic>)['id'] as String,
                                ),
                        icon: const Icon(Icons.add_business_outlined, size: 14),
                        label: const Text(
                          'FORM CITY',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. CORPORATION ENTERPRISE COCKPIT CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.domain_outlined,
                          size: 20, color: violetColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'CORPORATION: $corpName ($corporationId)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      (isCorpMember ? violetColor : mutedColor)
                                          .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: (isCorpMember
                                            ? violetColor
                                            : mutedColor)
                                        .withValues(alpha: .35),
                                  ),
                                ),
                                child: Text(
                                  isCorpMember ? 'MEMBER' : 'INDEPENDENT',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color:
                                        isCorpMember ? violetColor : mutedColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$corpMembers members · Constitution v$corpVersion · Status: ${isCorpMember ? 'MEMBER' : 'INDEPENDENT'}',
                            style: const TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Corporate Action Buttons Hub
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isCorpMember ? Colors.orangeAccent : violetColor,
                        side: BorderSide(
                          color:
                              (isCorpMember ? Colors.orangeAccent : violetColor)
                                  .withValues(alpha: .35),
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => isCorpMember
                              ? const EarthApi().leaveCorporation(
                                  corporationId: corporationId)
                              : const EarthApi().joinCorporation(
                                  corporationId: corporationId)),
                      child: Text(
                        isCorpMember ? 'LEAVE CORP' : 'JOIN CORP',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyanAccentColor,
                        side: BorderSide(
                            color: cyanAccentColor.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .spendCorporationTreasury(100,
                                  corporationId: corporationId)),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text(
                        'FUND SERVICES · 100 C',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: BorderSide(
                            color: Colors.tealAccent.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .contributeCorporation(100,
                                  corporationId: corporationId)),
                      icon: const Icon(Icons.savings_outlined, size: 14),
                      label: const Text(
                        'CONTRIBUTE · 100 C',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isCityResident)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: violetColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: busy
                            ? null
                            : () => showFormationComposer(
                                  context,
                                  action,
                                  city: false,
                                  cityId: cityId,
                                ),
                        icon:
                            const Icon(Icons.corporate_fare_outlined, size: 14),
                        label: const Text(
                          'FORM CORP',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CityImpactPanel extends StatelessWidget {
  final EarthState state;

  const CityImpactPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['city'] is Map
        ? Map<String, dynamic>.from(state.institutions['city'] as Map)
        : const <String, dynamic>{};
    final ratios = state.world['serviceRatios'] is Map
        ? Map<String, dynamic>.from(state.world['serviceRatios'] as Map)
        : const <String, dynamic>{};
    final pressure =
        asDouble(city['service_pressure'] ?? city['servicePressure']);
    final taxRate = asDouble(city['tax_rate'] ?? city['taxRate']);
    final business = state.business;
    final operatingEffect = asDouble(business['city_operating_modifier'] ??
        business['cityOperatingModifier']);
    final metrics = <(String, String, String, IconData, Color)>[
      (
        'CITY PRESSURE',
        pressure == null ? 'UNAVAILABLE' : '${pressure.toStringAsFixed(0)}%',
        pressure == null
            ? 'Pressure data unavailable'
            : pressure > 70
                ? 'Costs and services under strain'
                : 'Services within normal load',
        Icons.speed_outlined,
        pressure != null && pressure > 70
            ? Colors.orangeAccent
            : cyanAccentColor,
      ),
      (
        'BUSINESS EFFECT',
        operatingEffect == null
            ? 'UNAVAILABLE'
            : '${operatingEffect >= 0 ? '+' : ''}${operatingEffect.toStringAsFixed(1)}%',
        operatingEffect == null
            ? 'No business modifier reported'
            : 'Operating cost modifier',
        Icons.storefront_outlined,
        operatingEffect != null && operatingEffect > 0
            ? Colors.orangeAccent
            : Colors.lightGreenAccent,
      ),
      (
        'CITY TAX',
        taxRate == null ? 'UNAVAILABLE' : '${taxRate.toStringAsFixed(1)}%',
        taxRate == null ? 'Tax rate unavailable' : 'Current resident rate',
        Icons.receipt_long_outlined,
        violetColor,
      ),
    ];
    final services = [
      ('HOUSING', ratios['housing']),
      ('ENERGY', ratios['energy']),
      ('CONNECTIVITY', ratios['connectivity']),
      ('HEALTH', ratios['health']),
    ];

    return EarthPanel(
      title: 'CITY EFFECTS / LIFE & BUSINESS',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• City conditions affect your life and businesses through services, taxes, workforce quality, and operating costs.\n\n• Pressure above the city baseline can increase friction and reduce service reliability.\n\n• Values marked unavailable require current city or business data; they are not estimates.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            city['name'] == null
                ? 'No city effect is currently reported.'
                : 'Living in ${city['name']} changes your services, costs, and opportunities.',
            style: const TextStyle(
                color: inkColor, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics.map((metric) {
              return SizedBox(
                width: 180,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: metric.$5.withValues(alpha: .28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(metric.$4, size: 14, color: metric.$5),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(metric.$1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: mutedColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ]),
                      const SizedBox(height: 5),
                      Text(metric.$2,
                          style: TextStyle(
                              color: metric.$5,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(metric.$3,
                          style:
                              const TextStyle(color: mutedColor, fontSize: 9.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text('SERVICE CONDITIONS',
              style: TextStyle(
                  color: mutedColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: services.map((service) {
              final value = asDouble(service.$2);
              final color = value == null
                  ? mutedColor
                  : value < .5
                      ? Colors.redAccent
                      : value < .75
                          ? Colors.orangeAccent
                          : Colors.tealAccent;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: .28))),
                child: Text(
                    '${service.$1} · ${value == null ? 'UNAVAILABLE' : '${(value * 100).round()}%'}',
                    style: TextStyle(
                        color: color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class CommunitiesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CommunitiesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final communities = state.communities;
    return EarthPanel(
      title: 'COMMUNITIES / SHARED LIFE',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Civic Communities & Cooperatives: Grassroots voluntary associations formed by citizens for collective mutual aid, cultural affinity, and shared municipal governance.\n\n• Membership & Contributions:\n  - JOIN / LEAVE: Free association allowing citizens to participate in community governance and welfare dividends.\n  - CONTRIBUTE: Voluntary treasury contributions funding local public projects and communal resources.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${communities.length} registered communities',
                  style: const TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cyanAccentColor,
                  side:
                      BorderSide(color: cyanAccentColor.withValues(alpha: .35)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed:
                    busy ? null : () => showCommunityComposer(context, action),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('FOUND COMMUNITY',
                    style:
                        TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (communities.isEmpty)
            const Text('No communities registered yet.',
                style: TextStyle(color: mutedColor, fontSize: 11))
          else
            ...communities.take(4).map((raw) {
              final community = raw as Map<String, dynamic>;
              final id = community['id']?.toString() ?? 'COM-001';
              final name = community['name']?.toString() ?? 'Community';
              final status =
                  (community['status']?.toString() ?? 'active').toUpperCase();
              final members = asIntOr(community['member_count'], 12);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.groups_outlined,
                              size: 15, color: Colors.tealAccent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$name ($id)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cyanAccentColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: cyanAccentColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: cyanAccentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$members active members',
                      style: const TextStyle(fontSize: 10.5, color: mutedColor),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: cyanAccentColor,
                            side: BorderSide(
                                color: cyanAccentColor.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().joinCommunity(id)),
                          child: const Text('JOIN',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.orangeAccent,
                            side: BorderSide(
                                color:
                                    Colors.orangeAccent.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().leaveCommunity(id)),
                          child: const Text('LEAVE',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: violetColor,
                            side: BorderSide(
                                color: violetColor.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => showCommunityContributionDialog(
                                  context, action, id),
                          child: const Text('CONTRIBUTE',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
