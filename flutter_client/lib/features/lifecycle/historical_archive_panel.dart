import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../house/house_lineage_dialog.dart';

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
  int _selectedTab = 0; // 0: Archived Citizens, 1: Recorded Houses
  int _deceasedPage = 0;
  int _housePage = 0;
  static const int _pageSize = 10;

  final _citizenSearchController = TextEditingController();
  final _houseSearchController = TextEditingController();
  String _citizenSearch = '';
  String _houseSearch = '';

  @override
  void dispose() {
    _citizenSearchController.dispose();
    _houseSearchController.dispose();
    super.dispose();
  }

  List<dynamic> _list(dynamic value) => value is List ? value : const [];

  @override
  Widget build(BuildContext context) {
    final deceased = _list(widget.pantheon['deceasedPantheon'] ?? widget.pantheon['deceased']);
    final rawHouses = _list(widget.pantheon['houses'] ?? widget.pantheon['dynasties'] ?? widget.pantheon['dynasticHouses']);
    final houses = rawHouses.where((item) {
      if (item is! Map) return false;
      final heir = item['active_heir']?.toString() ?? item['heir']?.toString();
      final isExtinct = item['is_extinct'] == true ||
          item['status'] == 'extinct' ||
          item['status'] == 'deceased' ||
          item['status'] == 'historical' ||
          (heir == null || heir.isEmpty || heir == '—');
      return isExtinct;
    }).toList();

    final deceasedCol = _buildDeceasedSection(context, deceased, rawHouses);
    final housesCol = _buildHousesSection(context, houses);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: deceasedCol),
              const SizedBox(width: 40),
              Expanded(child: housesCol),
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
                      title: 'HOUSES',
                      icon: Icons.shield_outlined,
                      count: houses.length,
                      isSelected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            _selectedTab == 0 ? deceasedCol : housesCol,
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

  Widget _buildDeceasedSection(BuildContext context, List<dynamic> deceased, List<dynamic> houses) {
    final query = _citizenSearch.trim().toLowerCase();
    final filteredDeceased = query.isEmpty
        ? deceased
        : deceased.where((item) {
            if (item is! Map) return false;
            final name = (item['display_name'] ?? item['name'] ?? '').toString().toLowerCase();
            final origHouse = (item['original_house_name'] ?? item['house_name'] ?? item['original_dynasty_name'] ?? item['dynasty_name'] ?? item['dynasty'] ?? '').toString().toLowerCase();
            final currHouse = (item['current_house_name'] ?? item['active_house_name'] ?? item['current_dynasty_name'] ?? item['active_dynasty_name'] ?? '').toString().toLowerCase();
            final city = (item['city_name'] ?? item['city'] ?? '').toString().toLowerCase();
            final succ = (item['successor_name'] ?? item['successor'] ?? '').toString().toLowerCase();
            return name.contains(query) ||
                origHouse.contains(query) ||
                currHouse.contains(query) ||
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
              hintText: 'Search citizens by name, house, city, or successor...',
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

                  final originalHouse = (row['original_house_name'] ?? row['house_name'] ?? row['original_dynasty_name'] ?? row['dynasty_name'] ?? row['dynasty'] ?? 'Unknown house').toString();
                  final houseId = (row['house_id'] ?? row['dynasty_id'])?.toString();
                  String? currentHouseFromMap;
                  if (houseId != null) {
                    for (final d in houses) {
                      if (d is Map && (d['id']?.toString() == houseId || d['house_id']?.toString() == houseId || d['dynasty_id']?.toString() == houseId)) {
                        currentHouseFromMap = (d['house_name'] ?? d['dynasty_name'])?.toString();
                        break;
                      }
                    }
                  }
                  final currentHouse = row['current_house_name'] ?? row['active_house_name'] ?? row['current_dynasty_name'] ?? row['active_dynasty_name'] ?? currentHouseFromMap;

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
                                      '· Gen $gen of ${currentHouse ?? originalHouse}',
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
                              if (currentHouse != null && currentHouse.toString().isNotEmpty && currentHouse != originalHouse)
                                _badge(context, Icons.history_edu, 'Original House: $originalHouse'),
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

  Widget _buildHousesSection(BuildContext context, List<dynamic> houses) {
    final dQuery = _houseSearch.trim().toLowerCase();
    final filteredHouses = dQuery.isEmpty
        ? houses
        : houses.where((item) {
            if (item is! Map) return false;
            final houseName = (item['house_name'] ?? item['dynasty_name'] ?? item['name'] ?? '').toString().toLowerCase();
            final heir = (item['active_heir'] ?? item['heir'] ?? '').toString().toLowerCase();
            final seat = (item['seat'] ?? item['seat_city'] ?? item['city_name'] ?? '').toString().toLowerCase();
            final founder = (item['founder_name'] ?? item['founder'] ?? '').toString().toLowerCase();
            return houseName.contains(dQuery) || heir.contains(dQuery) || seat.contains(dQuery) || founder.contains(dQuery);
          }).toList();

    final totalPages = (filteredHouses.length / _pageSize).ceil().clamp(1, 9999);
    final currentPage = _housePage.clamp(0, totalPages - 1);
    final pageItems = filteredHouses.skip(currentPage * _pageSize).take(_pageSize).toList();

    return EarthSection(
      title: 'HISTORICAL HOUSES',
      showSurface: false,
      infoDescription:
          'The House Prestige Score permanently records the generational prominence and survival of a noble house across Earth\'s history based on a 1 : 5 : 25 weighting ratio:',
      infoBulletPoints: const [
        'House Legacy (25x relative weight): Cumulative milestones and achievements earned across all generations.',
        'House Standing (5x relative weight): Accumulated civic reputation and governance trust.',
        'Ancestral Inscriptions (10x bonus): Total passed ancestors permanently recorded.',
        'House Lifespan (1x base weight): Total full years the house has existed on Earth.',
        'Relative Ratio: 1 Legacy Pt = 5 House Standing Pts = 25 Lifespan Years.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: context.spacingControl),
            child: Text(
              'Planetary registry and memorial of concluded, extinct, and inactive noble house lineages across Earth.',
              style: context.widgetFooterStyle.copyWith(color: context.mutedColor),
            ),
          ),
          if (houses.isNotEmpty)
            _buildSearchBar(
              context: context,
              controller: _houseSearchController,
              hintText: 'Search extinct houses by name, founder, or seat...',
              onChanged: (val) => setState(() {
                _houseSearch = val;
                _housePage = 0;
              }),
            ),
          if (houses.isEmpty)
            const EarthEmptyState(
              message: 'No extinct houses have been recorded in the archive yet.',
              icon: Icons.shield_outlined,
            )
          else if (filteredHouses.isEmpty)
            EarthEmptyState(
              message: 'No recorded houses match "$_houseSearch".',
              icon: Icons.search_off,
            )
          else ...[
            ...pageItems.indexed.map((indexed) {
              final raw = indexed.$2;
              final row = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : const <String, dynamic>{};
              final houseName =
                  (row['house_name'] ?? row['dynasty_name'] ?? row['name'] ?? 'House').toString();
              final gen = row['generation'] ?? row['generations'] ?? row['generation_number'] ?? row['gen'] ?? 1;
              final count = (row['deceased_count'] ?? row['ancestors_count'] ?? row['deceased'] ?? '1').toString();
              final totalLegacy = (row['total_legacy'] ?? row['house_legacy'] ?? row['dynasty_legacy'] ?? row['peak_legacy'] ?? row['legacy_points'] ?? row['legacy'] ?? '0').toString();
              final peakStanding = row['peak_standing'] ?? row['standing'] ?? row['house_standing'] ?? row['dynastic_standing'] ?? 0;
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
              final houseScore = row['house_score'] ?? row['dynasty_score'] ?? row['score'] ?? (legacyNum * 50 + standingNum * 10 + ageY * 2 + ancestorsNum * 20);

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
                  onTap: () => showHouseLineageDialog(
                    context,
                    house: Map<String, dynamic>.from(row),
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
                              Icons.shield_outlined,
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
                                    houseName,
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
                              value: '$houseScore PTS',
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
                            if (!isExtinct && heir.isNotEmpty && heir != '—')
                              _badge(context, Icons.person_pin, 'Heir: $heir')
                            else if (isExtinct)
                              _badge(context, Icons.hourglass_disabled, 'Lineage: Extinct'),
                            _badge(context, Icons.cake_outlined, foundedLabel),
                            _badge(context, Icons.timelapse, ageLabel),
                            _badge(context, Icons.account_box_outlined, 'Ancestors: $count'),
                            _badge(context, Icons.stars_outlined, 'House Legacy: $totalLegacy LP'),
                            if (standingNum > 0)
                              _badge(context, Icons.shield, 'House Standing: $standingNum pts'),
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
            if (filteredHouses.length > _pageSize) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PAGE ${currentPage + 1} OF $totalPages (${filteredHouses.length} TOTAL)',
                    style: context.captionStyle.copyWith(color: context.mutedColor),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EarthButton(
                        label: 'PREVIOUS',
                        icon: Icons.chevron_left_rounded,
                        onPressed: currentPage > 0
                            ? () => setState(() => _housePage = currentPage - 1)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      EarthButton(
                        label: 'NEXT',
                        icon: Icons.chevron_right_rounded,
                        onPressed: currentPage < totalPages - 1
                            ? () => setState(() => _housePage = currentPage + 1)
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

typedef HistoricalDynastiesPanel = HistoricalHousesPanel;

class HistoricalHousesPanel extends StatefulWidget {
  final Map<String, dynamic> pantheon;
  const HistoricalHousesPanel({super.key, required this.pantheon});

  @override
  State<HistoricalHousesPanel> createState() => _HistoricalHousesPanelState();
}

class _HistoricalHousesPanelState extends State<HistoricalHousesPanel> {
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
    final rows = widget.pantheon['houses'] ?? widget.pantheon['dynasties'] ?? widget.pantheon['dynasticHouses'];
    final houses = rows is List ? rows : const <dynamic>[];
    final totalPages = (houses.length / _pageSize).ceil().clamp(1, 9999);
    final currentPage = _page.clamp(0, totalPages - 1);
    final pageItems = houses.skip(currentPage * _pageSize).take(_pageSize).toList();

    return EarthSection(
      title: 'HISTORICAL HOUSES',
      showSurface: false,
      child: houses.isEmpty
          ? const EarthEmptyState(
              message: 'No historical houses recorded.',
              icon: Icons.shield_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...pageItems.indexed.map((indexed) {
                  final raw = indexed.$2;
                  final row = raw is Map
                      ? Map<String, dynamic>.from(raw)
                      : const <String, dynamic>{};
                  final houseName =
                      (row['house_name'] ?? row['dynasty_name'] ?? row['name'] ?? 'House').toString();
                  final gen = row['generation'] ?? row['generations'] ?? row['generation_number'] ?? row['gen'] ?? 1;
                  final count = (row['deceased_count'] ?? row['generations'] ?? row['generation'] ?? '1').toString();
                  final totalLegacy = (row['total_legacy'] ?? row['house_legacy'] ?? row['dynasty_legacy'] ?? row['peak_legacy'] ?? row['legacy_points'] ?? row['legacy'] ?? '0').toString();
                  final peakStanding = row['peak_standing'] ?? row['standing'] ?? row['house_standing'] ?? row['dynastic_standing'] ?? 0;
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
                  final houseScore = row['house_score'] ?? row['dynasty_score'] ?? row['score'] ?? (legacyNum * 50 + standingNum * 10 + ageY * 2 + ancestorsNum * 20);

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
                                Icons.shield_outlined,
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
                                      houseName,
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
                                value: '$houseScore PTS',
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
                              if (!isExtinct && heir.isNotEmpty && heir != '—')
                                _badge(context, Icons.person_pin, 'Heir: $heir')
                              else if (isExtinct)
                                _badge(context, Icons.hourglass_disabled, 'Lineage: Extinct'),
                              _badge(context, Icons.cake_outlined, foundedLabel),
                              _badge(context, Icons.timelapse, ageLabel),
                              _badge(context, Icons.account_box_outlined, 'Ancestors: $count'),
                              _badge(context, Icons.stars_outlined, 'House Legacy: $totalLegacy LP'),
                              if (standingNum > 0)
                                _badge(context, Icons.shield, 'House Standing: $standingNum pts'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (houses.length > _pageSize) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PAGE ${currentPage + 1} OF $totalPages (${houses.length} TOTAL)',
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
