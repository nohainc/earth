import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../dynasty/dynasty_lineage_dialog.dart';

class HistoricalArchivePanel extends StatefulWidget {
  final Map<String, dynamic> pantheon;
  final List<dynamic> events;

  const HistoricalArchivePanel({
    super.key,
    required this.pantheon,
    this.events = const [],
  });

  @override
  State<HistoricalArchivePanel> createState() => _HistoricalArchivePanelState();
}

class _HistoricalArchivePanelState extends State<HistoricalArchivePanel> {
  int _selectedTab = 0; // 0: Archived Citizens, 1: Recorded Dynasties
  int _deceasedPage = 0;
  int _dynastyPage = 0;
  static const int _pageSize = 10;

  final _citizenSearchController = TextEditingController();
  final _dynastySearchController = TextEditingController();
  String _citizenSearch = '';
  String _dynastySearch = '';

  @override
  void dispose() {
    _citizenSearchController.dispose();
    _dynastySearchController.dispose();
    super.dispose();
  }

  List<dynamic> _list(dynamic value) => value is List ? value : const [];

  @override
  Widget build(BuildContext context) {
    final deceased = _list(widget.pantheon['deceasedPantheon'] ?? widget.pantheon['deceased']);
    final rawDynasties = _list(widget.pantheon['dynasties'] ?? widget.pantheon['dynasticHouses']);
    final dynasties = rawDynasties.where((item) {
      if (item is! Map) return false;
      final heir = item['active_heir']?.toString() ?? item['heir']?.toString();
      final isExtinct = item['is_extinct'] == true ||
          item['status'] == 'extinct' ||
          item['status'] == 'deceased' ||
          item['status'] == 'historical' ||
          (heir == null || heir.isEmpty || heir == '—');
      return isExtinct;
    }).toList();

    final deceasedCol = _buildDeceasedSection(context, deceased, rawDynasties);
    final dynastiesCol = _buildDynastiesSection(context, dynasties);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 800;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: deceasedCol),
              SizedBox(width: context.spacingTopic),
              Expanded(child: dynastiesCol),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: EdgeInsets.only(bottom: context.spacingControl),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'CITIZENS',
                      icon: Icons.account_box_outlined,
                      count: deceased.length,
                      isSelected: _selectedTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                  ),
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'DYNASTIES',
                      icon: Icons.account_tree_outlined,
                      count: dynasties.length,
                      isSelected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            _selectedTab == 0 ? deceasedCol : dynastiesCol,
          ],
        );
      },
    );
  }

  Widget _buildSearchBar({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 36,
      margin: EdgeInsets.only(bottom: context.spacingControl),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: context.bodyStyle,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: context.captionStyle.copyWith(color: context.mutedColor),
          prefixIcon: Icon(Icons.search, size: 16, color: context.mutedColor),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 14, color: context.mutedColor),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          filled: true,
          fillColor: context.surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.radiusCard),
            borderSide: BorderSide(color: context.subtleBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.radiusCard),
            borderSide: BorderSide(color: context.subtleBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.radiusCard),
            borderSide: BorderSide(color: context.primaryColor),
          ),
        ),
      ),
    );
  }

  Widget _buildNarrowTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.primaryColor.withValues(alpha: .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: context.primaryColor.withValues(alpha: .4)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? context.primaryColor : context.mutedColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$title ($count)',
                overflow: TextOverflow.ellipsis,
                style: context.controlStyle.copyWith(
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: context.iconSize - 2, color: context.mutedColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.widgetFooterStyle.copyWith(
            color: context.mutedColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDeceasedSection(BuildContext context, List<dynamic> deceased, List<dynamic> dynasties) {
    final query = _citizenSearch.trim().toLowerCase();
    final filteredDeceased = query.isEmpty
        ? deceased
        : deceased.where((item) {
            if (item is! Map) return false;
            final name = (item['display_name'] ?? item['name'] ?? '').toString().toLowerCase();
            final origDynasty = (item['original_dynasty_name'] ?? item['dynasty_name'] ?? item['dynasty'] ?? '').toString().toLowerCase();
            final currDynasty = (item['current_dynasty_name'] ?? item['active_dynasty_name'] ?? '').toString().toLowerCase();
            final city = (item['city_name'] ?? item['city'] ?? '').toString().toLowerCase();
            final succ = (item['successor_name'] ?? item['successor'] ?? '').toString().toLowerCase();
            return name.contains(query) ||
                origDynasty.contains(query) ||
                currDynasty.contains(query) ||
                city.contains(query) ||
                succ.contains(query);
          }).toList();

    final totalPages = (filteredDeceased.length / _pageSize).ceil().clamp(1, 9999);
    final currentPage = _deceasedPage.clamp(0, totalPages - 1);
    final pageItems = filteredDeceased.skip(currentPage * _pageSize).take(_pageSize).toList();

    return EarthSection(
      title: 'MEMORIAL CITIZENS',
      showSurface: false,
      infoDescription:
          'The Composite Score permanently records the historical impact of a deceased citizen across their lifetime on Earth based on a 1 : 5 : 25 weighting ratio:',
      infoBulletPoints: const [
        'Personal Legacy (25x relative weight): Historical milestones & lifetime achievements.',
        'Civic Standing (5x relative weight): Political influence & civic reputation at passing.',
        'Lifespan Age (1x base weight): Total full years lived on Earth.',
        'Relative Ratio: 1 Legacy Pt = 5 Civic Standing Pts = 25 Age Years.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: context.spacingControl),
            child: Text(
              'Historical registry of deceased citizens who have completed their life cycle on Earth.',
              style: context.widgetFooterStyle.copyWith(color: context.mutedColor),
            ),
          ),
          if (deceased.isNotEmpty)
            _buildSearchBar(
              context: context,
              controller: _citizenSearchController,
              hintText: 'Search citizens by name, dynasty, city, or successor...',
              onChanged: (val) => setState(() {
                _citizenSearch = val;
                _deceasedPage = 0;
              }),
            ),
          if (deceased.isEmpty)
            const EarthEmptyState(
              message: 'No citizens have entered the public archive yet.',
              icon: Icons.account_box_outlined,
            )
          else if (filteredDeceased.isEmpty)
            EarthEmptyState(
              message: 'No archived citizens match "$_citizenSearch".',
              icon: Icons.search_off,
            )
          else ...[
                ...pageItems.indexed.map((indexed) {
                  final raw = indexed.$2;
                  final row = raw is Map
                      ? Map<String, dynamic>.from(raw)
                      : const <String, dynamic>{};
                  final name =
                      (row['display_name'] ?? row['name'] ?? 'Archived citizen').toString();
                  final gen = row['generation'] ?? row['gen'] ?? row['generation_number'] ?? 1;
                  final day = (row['death_game_day'] ?? row['game_day'] ?? '—').toString();
                  final deathDayNum = int.tryParse(day);
                  final birthDayRaw = row['birth_game_day'] ?? row['birth_day'] ?? row['birthDay'] ?? row['born_day'];
                  final int? birthDayNum = birthDayRaw != null
                      ? int.tryParse(birthDayRaw.toString())
                      : (deathDayNum != null && (row['age_years'] != null || row['age'] != null)
                          ? (deathDayNum - (int.parse((row['age_years'] ?? row['age']).toString()) * 365)).clamp(1, 9999999)
                          : null);

                  String? bornLabel;
                  if (birthDayNum != null) {
                    final bYear = ((birthDayNum - 1) ~/ 365) + 1;
                    final bDay = ((birthDayNum - 1) % 365) + 1;
                    bornLabel = 'Born: Year $bYear, Day $bDay';
                  }

                  String? ageLabel;
                  int ageYearsNum = 0;
                  if (deathDayNum != null && birthDayNum != null) {
                    final totalDays = (deathDayNum - birthDayNum).clamp(0, 9999999);
                    final ageY = totalDays ~/ 365;
                    final ageD = totalDays % 365;
                    ageYearsNum = ageY;
                    ageLabel = ageD > 0 ? 'Age: $ageY yrs, $ageD days' : 'Age: $ageY yrs';
                  } else if (row['age_years'] != null || row['age'] != null) {
                    final ageY = int.tryParse(row['age_years']?.toString() ?? row['age']?.toString() ?? '0') ?? 0;
                    ageYearsNum = ageY;
                    ageLabel = 'Age: $ageY yrs';
                  }

                  final originalDynasty = (row['original_dynasty_name'] ?? row['dynasty_name'] ?? row['dynasty'] ?? 'Unknown dynasty').toString();
                  final dynastyId = row['dynasty_id']?.toString();
                  String? currentDynastyFromMap;
                  if (dynastyId != null) {
                    for (final d in dynasties) {
                      if (d is Map && (d['id']?.toString() == dynastyId || d['dynasty_id']?.toString() == dynastyId)) {
                        currentDynastyFromMap = d['dynasty_name']?.toString();
                        break;
                      }
                    }
                  }
                  final currentDynasty = row['current_dynasty_name']?.toString() ?? row['active_dynasty_name']?.toString() ?? currentDynastyFromMap;

                  final legacy = (row['final_legacy'] ?? row['legacy_points'] ?? row['legacy'] ?? 0).toString();
                  final legNum = int.tryParse(legacy) ?? 0;
                  final standing = row['final_standing']?.toString() ?? row['standing']?.toString();
                  final stdNum = int.tryParse(standing ?? '0') ?? 0;
                  final compositeScore = row['composite_legacy_score'] ?? (stdNum * 10 + legNum * 50 + ageYearsNum * 2);

                  final city = row['city_name']?.toString() ?? row['city']?.toString();
                  final estate = row['lifetime_wealth'] ?? row['estate_credits'];
                  final cause = row['cause_of_death']?.toString() ?? row['cause']?.toString();
                  final successor = row['successor_name']?.toString() ?? row['successor']?.toString();
                  final epitaph = row['epitaph']?.toString();

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: indexed.$1 == pageItems.length - 1 ? 0 : context.spacingControl,
                    ),
                    child: Container(
                      padding: EdgeInsets.all(context.cardPadding),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(context.radiusCard),
                        border: Border.all(color: context.subtleBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bookmark,
                                color: context.primaryColor,
                                size: context.iconSize,
                              ),
                              SizedBox(width: context.spacingInline),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      name,
                                      style: context.widgetValueStyle,
                                    ),
                                    Text(
                                      '· Gen $gen of ${currentDynasty ?? originalDynasty}',
                                      style: context.widgetValueStyle.copyWith(
                                        color: context.mutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: context.spacingInline),
                              EarthStatusPill(
                                label: 'SCORE',
                                value: '$compositeScore PTS',
                                color: context.primaryColor,
                              ),
                            ],
                          ),
                          if (epitaph != null && epitaph.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '“$epitaph”',
                              style: context.widgetFooterStyle.copyWith(
                                color: context.primaryColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          SizedBox(height: context.spacingInline),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              if (currentDynasty != null && currentDynasty.isNotEmpty && currentDynasty != originalDynasty)
                                _badge(context, Icons.history_edu, 'Original Dynasty: $originalDynasty'),
                              if (bornLabel != null) _badge(context, Icons.cake_outlined, bornLabel),
                              if (ageLabel != null) _badge(context, Icons.timelapse, ageLabel),
                              _badge(context, Icons.stars_outlined, 'Personal Legacy: $legNum LP'),
                              if (stdNum > 0) _badge(context, Icons.shield, 'Final Standing: $stdNum pts'),
                              if (city != null && city.isNotEmpty && city != '—')
                                _badge(context, Icons.location_city, 'City: $city'),
                              if (estate != null && estate != 0 && estate != '0')
                                _badge(context, Icons.account_balance_wallet_outlined, 'Estate: $estate C'),
                              if (cause != null && cause.isNotEmpty && cause != '—')
                                _badge(context, Icons.favorite_border, 'Cause: $cause'),
                              if (successor != null && successor.isNotEmpty && successor != '—')
                                _badge(context, Icons.person_pin, 'Successor: $successor'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (filteredDeceased.length > _pageSize) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PAGE ${currentPage + 1} OF $totalPages (${filteredDeceased.length} TOTAL)',
                        style: context.captionStyle.copyWith(color: context.mutedColor),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EarthButton(
                            label: 'PREVIOUS',
                            icon: Icons.chevron_left_rounded,
                            onPressed: currentPage > 0
                                ? () => setState(() => _deceasedPage = currentPage - 1)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          EarthButton(
                            label: 'NEXT',
                            icon: Icons.chevron_right_rounded,
                            onPressed: currentPage < totalPages - 1
                                ? () => setState(() => _deceasedPage = currentPage + 1)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
    );
  }

  Widget _buildDynastiesSection(BuildContext context, List<dynamic> dynasties) {
    final dQuery = _dynastySearch.trim().toLowerCase();
    final filteredDynasties = dQuery.isEmpty
        ? dynasties
        : dynasties.where((item) {
            if (item is! Map) return false;
            final dynastyName = (item['dynasty_name'] ?? item['name'] ?? '').toString().toLowerCase();
            final heir = (item['active_heir'] ?? item['heir'] ?? '').toString().toLowerCase();
            final seat = (item['seat'] ?? item['seat_city'] ?? item['city_name'] ?? '').toString().toLowerCase();
            final founder = (item['founder_name'] ?? item['founder'] ?? '').toString().toLowerCase();
            return dynastyName.contains(dQuery) || heir.contains(dQuery) || seat.contains(dQuery) || founder.contains(dQuery);
          }).toList();

    final totalPages = (filteredDynasties.length / _pageSize).ceil().clamp(1, 9999);
    final currentPage = _dynastyPage.clamp(0, totalPages - 1);
    final pageItems = filteredDynasties.skip(currentPage * _pageSize).take(_pageSize).toList();

    return EarthSection(
      title: 'HISTORICAL DYNASTIES',
      showSurface: false,
      infoDescription:
          'The Dynastic Prestige Score permanently records the generational prominence and survival of a family house across Earth\'s history based on a 1 : 5 : 25 weighting ratio:',
      infoBulletPoints: const [
        'Dynastic Legacy (25x relative weight): Cumulative milestones and achievements earned across all generations.',
        'Dynastic Standing (5x relative weight): Accumulated civic reputation and governance trust.',
        'Ancestral Inscriptions (10x bonus): Total passed ancestors permanently recorded.',
        'Dynastic Lifespan (1x base weight): Total full years the dynasty has existed on Earth.',
        'Relative Ratio: 1 Legacy Pt = 5 Dynastic Standing Pts = 25 Lifespan Years.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: context.spacingControl),
            child: Text(
              'Planetary registry and memorial of concluded, extinct, and inactive dynastic lineages across Earth.',
              style: context.widgetFooterStyle.copyWith(color: context.mutedColor),
            ),
          ),
          if (dynasties.isNotEmpty)
            _buildSearchBar(
              context: context,
              controller: _dynastySearchController,
              hintText: 'Search extinct dynasties by name, founder, or seat...',
              onChanged: (val) => setState(() {
                _dynastySearch = val;
                _dynastyPage = 0;
              }),
            ),
          if (dynasties.isEmpty)
            const EarthEmptyState(
              message: 'No extinct dynasties have been recorded in the archive yet.',
              icon: Icons.account_tree_outlined,
            )
          else if (filteredDynasties.isEmpty)
            EarthEmptyState(
              message: 'No recorded dynasties match "$_dynastySearch".',
              icon: Icons.search_off,
            )
          else ...[
            ...pageItems.indexed.map((indexed) {
              final raw = indexed.$2;
              final row = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : const <String, dynamic>{};
              final dynastyName =
                  (row['dynasty_name'] ?? row['name'] ?? 'Dynasty').toString();
              final gen = row['generation'] ?? row['generations'] ?? row['generation_number'] ?? row['gen'] ?? 1;
              final count = (row['deceased_count'] ?? row['ancestors_count'] ?? row['deceased'] ?? '1').toString();
              final totalLegacy = (row['total_legacy'] ?? row['dynasty_legacy'] ?? row['peak_legacy'] ?? row['legacy_points'] ?? row['legacy'] ?? '0').toString();
              final peakStanding = row['peak_standing'] ?? row['standing'] ?? row['dynastic_standing'] ?? 0;
              final founder = row['founder_name']?.toString() ?? row['founder']?.toString() ?? row['progenitor_name']?.toString();
              final heir = row['active_heir']?.toString() ?? row['heir']?.toString();
              final motto = row['motto']?.toString() ?? row['description']?.toString() ?? row['epitaph']?.toString();
              final seat = row['seat']?.toString() ?? row['seat_city']?.toString() ?? row['city_name']?.toString();
              final vault = row['trust_credits'] ?? row['vault'] ?? row['estate_credits'];

              final foundedRaw = row['founded_game_day'] ?? row['birth_game_day'] ?? row['founded_day'] ?? row['start_day'] ?? 1;
              final foundedDayNum = int.tryParse(foundedRaw.toString()) ?? 1;
              final fYear = ((foundedDayNum - 1) ~/ 365) + 1;
              final fDay = ((foundedDayNum - 1) % 365) + 1;
              final foundedLabel = 'Founded: Year $fYear, Day $fDay';

              final currentDayRaw = row['current_game_day'] ?? row['game_day'] ?? widget.pantheon['game_day'] ?? 1200;
              final currentDayNum = int.tryParse(currentDayRaw.toString()) ?? 1200;
              final totalDays = (currentDayNum - foundedDayNum).clamp(0, 9999999);
              final ageY = totalDays ~/ 365;
              final ageD = totalDays % 365;
              final ageLabel = ageD > 0 ? 'Age: $ageY yrs, $ageD days' : 'Age: $ageY yrs';

              final legacyNum = int.tryParse(totalLegacy) ?? 0;
              final standingNum = int.tryParse(peakStanding.toString()) ?? 0;
              final genNum = int.tryParse(gen.toString()) ?? 1;
              final ancestorsNum = int.tryParse(count) ?? 1;
              final dynastyScore = row['dynasty_score'] ?? row['score'] ?? (legacyNum * 50 + standingNum * 10 + ageY * 2 + ancestorsNum * 20);

              final isExtinct = row['is_extinct'] == true || row['status'] == 'extinct' || row['status'] == 'deceased' || (heir == null || heir.isEmpty || heir == '—');
              final statusLabel = !isExtinct
                  ? 'Active (Gen $gen)'
                  : 'Extinct (Gen $gen)';

              return Padding(
                padding: EdgeInsets.only(
                  bottom: indexed.$1 == pageItems.length - 1 ? 0 : context.spacingControl,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  onTap: () => showDynastyLineageDialog(
                    context,
                    dynasty: Map<String, dynamic>.from(row),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(context.cardPadding),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusCard),
                      border: Border.all(color: context.subtleBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.military_tech,
                              color: context.primaryColor,
                              size: context.iconSize,
                            ),
                            SizedBox(width: context.spacingInline),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    dynastyName,
                                    style: context.widgetValueStyle,
                                  ),
                                  Text(
                                    '· $statusLabel',
                                    style: context.widgetValueStyle.copyWith(
                                      color: context.mutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: context.spacingInline),
                            EarthStatusPill(
                              label: 'SCORE',
                              value: '$dynastyScore PTS',
                              color: context.primaryColor,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.account_tree_outlined,
                              size: 16,
                              color: context.primaryColor,
                            ),
                          ],
                        ),
                        if (motto != null && motto.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '“$motto”',
                            style: context.widgetFooterStyle.copyWith(
                              color: context.primaryColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        SizedBox(height: context.spacingInline),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            if (founder != null && founder.isNotEmpty && founder != '—')
                              _badge(context, Icons.history, 'Founder: $founder'),
                            if (!isExtinct && heir != null && heir.isNotEmpty && heir != '—')
                              _badge(context, Icons.person_pin, 'Heir: $heir')
                            else if (isExtinct)
                              _badge(context, Icons.hourglass_disabled, 'Lineage: Extinct'),
                            _badge(context, Icons.cake_outlined, foundedLabel),
                            _badge(context, Icons.timelapse, ageLabel),
                            _badge(context, Icons.account_box_outlined, 'Ancestors: $count'),
                            _badge(context, Icons.stars_outlined, 'Dynastic Legacy: $totalLegacy LP'),
                            if (standingNum > 0)
                              _badge(context, Icons.shield, 'Dynastic Standing: $standingNum pts'),
                            if (seat != null && seat.isNotEmpty && seat != '—')
                              _badge(context, Icons.location_city, 'Seat: $seat'),
                            if (vault != null && vault != 0 && vault != '0')
                              _badge(context, Icons.account_balance_wallet_outlined, 'Vault: $vault C'),
                            _badge(context, Icons.account_tree_outlined, 'View Lineage Tree'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (filteredDynasties.length > _pageSize) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PAGE ${currentPage + 1} OF $totalPages (${filteredDynasties.length} TOTAL)',
                    style: context.captionStyle.copyWith(color: context.mutedColor),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EarthButton(
                        label: 'PREVIOUS',
                        icon: Icons.chevron_left_rounded,
                        onPressed: currentPage > 0
                            ? () => setState(() => _dynastyPage = currentPage - 1)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      EarthButton(
                        label: 'NEXT',
                        icon: Icons.chevron_right_rounded,
                        onPressed: currentPage < totalPages - 1
                            ? () => setState(() => _dynastyPage = currentPage + 1)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class HistoricalDynastiesPanel extends StatefulWidget {
  final Map<String, dynamic> pantheon;
  const HistoricalDynastiesPanel({super.key, required this.pantheon});

  @override
  State<HistoricalDynastiesPanel> createState() => _HistoricalDynastiesPanelState();
}

class _HistoricalDynastiesPanelState extends State<HistoricalDynastiesPanel> {
  int _page = 0;
  static const int _pageSize = 10;

  Widget _badge(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: context.iconSize - 2, color: context.mutedColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.widgetFooterStyle.copyWith(
            color: context.mutedColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.pantheon['dynasties'] ?? widget.pantheon['dynasticHouses'];
    final dynasties = rows is List ? rows : const <dynamic>[];
    final totalPages = (dynasties.length / _pageSize).ceil().clamp(1, 9999);
    final currentPage = _page.clamp(0, totalPages - 1);
    final pageItems = dynasties.skip(currentPage * _pageSize).take(_pageSize).toList();

    return EarthSection(
      title: 'DYNASTIES',
      showSurface: false,
      child: dynasties.isEmpty
          ? const EarthEmptyState(
              message: 'No historical dynasties recorded.',
              icon: Icons.account_tree_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...pageItems.indexed.map((indexed) {
                  final raw = indexed.$2;
                  final row = raw is Map
                      ? Map<String, dynamic>.from(raw)
                      : const <String, dynamic>{};
                  final dynastyName =
                      (row['dynasty_name'] ?? row['name'] ?? 'Dynasty').toString();
                  final gen = row['generation'] ?? row['generations'] ?? row['generation_number'] ?? row['gen'] ?? 1;
                  final count = (row['deceased_count'] ?? row['generations'] ?? row['generation'] ?? '1').toString();
                  final totalLegacy = (row['total_legacy'] ?? row['dynasty_legacy'] ?? row['peak_legacy'] ?? row['legacy_points'] ?? row['legacy'] ?? '0').toString();
                  final peakStanding = row['peak_standing'] ?? row['standing'] ?? row['dynastic_standing'] ?? 0;
                  final founder = row['founder_name']?.toString() ?? row['founder']?.toString() ?? row['progenitor_name']?.toString();
                  final heir = row['active_heir']?.toString() ?? row['heir']?.toString();

                  final foundedRaw = row['founded_game_day'] ?? row['birth_game_day'] ?? row['founded_day'] ?? row['start_day'] ?? 1;
                  final foundedDayNum = int.tryParse(foundedRaw.toString()) ?? 1;
                  final fYear = ((foundedDayNum - 1) ~/ 365) + 1;
                  final fDay = ((foundedDayNum - 1) % 365) + 1;
                  final foundedLabel = 'Founded: Year $fYear, Day $fDay';

                  final currentDayRaw = row['current_game_day'] ?? row['game_day'] ?? widget.pantheon['game_day'] ?? 1200;
                  final currentDayNum = int.tryParse(currentDayRaw.toString()) ?? 1200;
                  final totalDays = (currentDayNum - foundedDayNum).clamp(0, 9999999);
                  final ageY = totalDays ~/ 365;
                  final ageD = totalDays % 365;
                  final ageLabel = ageD > 0 ? 'Age: $ageY yrs, $ageD days' : 'Age: $ageY yrs';

                  final legacyNum = int.tryParse(totalLegacy) ?? 0;
                  final standingNum = int.tryParse(peakStanding.toString()) ?? 0;
                  final genNum = int.tryParse(gen.toString()) ?? 1;
                  final ancestorsNum = int.tryParse(count) ?? 1;
                  final dynastyScore = row['dynasty_score'] ?? row['score'] ?? (legacyNum * 50 + standingNum * 10 + ageY * 2 + ancestorsNum * 20);

                  final isExtinct = row['is_extinct'] == true || row['status'] == 'extinct' || row['status'] == 'deceased' || (heir == null || heir.isEmpty || heir == '—');
                  final statusLabel = !isExtinct
                      ? 'Active (Gen $gen)'
                      : 'Extinct (Gen $gen)';

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: indexed.$1 == pageItems.length - 1 ? 0 : context.spacingControl,
                    ),
                    child: Container(
                      padding: EdgeInsets.all(context.cardPadding),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(context.radiusCard),
                        border: Border.all(color: context.subtleBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.military_tech,
                                color: context.primaryColor,
                                size: context.iconSize,
                              ),
                              SizedBox(width: context.spacingInline),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      dynastyName,
                                      style: context.widgetValueStyle,
                                    ),
                                    Text(
                                      '· $statusLabel',
                                      style: context.widgetValueStyle.copyWith(
                                        color: context.mutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: context.spacingInline),
                              EarthStatusPill(
                                label: 'SCORE',
                                value: '$dynastyScore PTS',
                                color: context.primaryColor,
                              ),
                            ],
                          ),
                          SizedBox(height: context.spacingInline),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              if (founder != null && founder.isNotEmpty && founder != '—')
                                _badge(context, Icons.history, 'Founder: $founder'),
                              if (!isExtinct && heir != null && heir.isNotEmpty && heir != '—')
                                _badge(context, Icons.person_pin, 'Heir: $heir')
                              else if (isExtinct)
                                _badge(context, Icons.hourglass_disabled, 'Lineage: Extinct'),
                              _badge(context, Icons.cake_outlined, foundedLabel),
                              _badge(context, Icons.timelapse, ageLabel),
                              _badge(context, Icons.account_box_outlined, 'Ancestors: $count'),
                              _badge(context, Icons.stars_outlined, 'Dynastic Legacy: $totalLegacy LP'),
                              if (standingNum > 0)
                                _badge(context, Icons.shield, 'Dynastic Standing: $standingNum pts'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (dynasties.length > _pageSize) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PAGE ${currentPage + 1} OF $totalPages (${dynasties.length} TOTAL)',
                        style: context.captionStyle.copyWith(color: context.mutedColor),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EarthButton(
                            label: 'PREVIOUS',
                            icon: Icons.chevron_left_rounded,
                            onPressed: currentPage > 0
                                ? () => setState(() => _page = currentPage - 1)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          EarthButton(
                            label: 'NEXT',
                            icon: Icons.chevron_right_rounded,
                            onPressed: currentPage < totalPages - 1
                                ? () => setState(() => _page = currentPage + 1)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
