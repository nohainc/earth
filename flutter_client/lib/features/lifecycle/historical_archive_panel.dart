import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/memorial_models.dart';

import '../house/house_lineage_dialog.dart';
import 'memorial_citizen_biography_dialog.dart';

class HistoricalArchivePanel extends StatefulWidget {
  final MemorialArchivePage? archive;
  @Deprecated('Use archive for the canonical V5 Memorial model.')
  final Map<String, dynamic> pantheon;
  final EarthApi? api;
  final List<dynamic> events;

  const HistoricalArchivePanel({
    super.key,
    this.archive,
    this.pantheon = const <String, dynamic>{},
    this.api,
    this.events = const [],
  });

  @override
  State<HistoricalArchivePanel> createState() => _HistoricalArchivePanelState();
}

class _HistoricalArchivePanelState extends State<HistoricalArchivePanel> {
  int _selectedTab = 0; // 0: Archived Citizens, 1: Recorded Houses
  int _deceasedPage = 1;
  int _housePage = 1;
  static const int _pageSize = 20;
  List<MemorialCitizenSummary> _deceased = const [];
  List<MemorialHouseSummary> _houses = const [];
  int _deceasedTotal = 0;
  int _houseTotal = 0;
  String? _deceasedNextCursor;
  String? _houseNextCursor;
  String? _deceasedPageCursor;
  String? _housePageCursor;
  final List<String?> _deceasedCursorHistory = <String?>[];
  final List<String?> _houseCursorHistory = <String?>[];
  bool _archiveLoading = false;

  final _citizenSearchController = TextEditingController();
  final _houseSearchController = TextEditingController();
  String _citizenSearch = '';
  String _houseSearch = '';
  String _houseStatus = 'ALL';

  @override
  void initState() {
    super.initState();
    if (widget.archive != null) {
      _deceased = widget.archive!.citizens;
      _houses = widget.archive!.houses;
      _deceasedTotal = widget.archive!.citizenTotalCount;
      _houseTotal = widget.archive!.houseTotalCount;
      _deceasedNextCursor = widget.archive!.citizenNextCursor;
      _houseNextCursor = widget.archive!.houseNextCursor;
    } else {
      _applyPantheon(widget.pantheon);
    }
  }

  void _applyPantheon(Map<String, dynamic> data) {
    final page = MemorialArchivePage.fromJson(data);
    _deceased = page.citizens;
    _houses = page.houses;
    _deceasedTotal = int.tryParse('${data['deceasedTotalCount'] ?? _deceased.length}') ?? _deceased.length;
    _houseTotal = int.tryParse('${data['houseTotalCount'] ?? _houses.length}') ?? _houses.length;
    _deceasedNextCursor = data['deceasedNextCursor']?.toString();
    _houseNextCursor = data['houseNextCursor']?.toString();
  }

  Future<void> _loadArchivePage({required bool citizens, String? cursor, bool next = false}) async {
    final client = widget.api;
    if (client == null || _archiveLoading) return;
    setState(() => _archiveLoading = true);
    try {
      final page = await client.memorial(
        search: citizens ? _citizenSearch : _houseSearch,
        houseStatus: citizens ? null : _houseStatus,
        citizenCursor: citizens ? cursor : null,
        houseCursor: citizens ? null : cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (citizens) {
          if (next) _deceasedCursorHistory.add(_deceasedPageCursor);
          _deceasedPageCursor = cursor;
          _deceased = page.citizens;
          _deceasedTotal = page.citizenTotalCount;
          _deceasedNextCursor = page.citizenNextCursor;
        } else {
          if (next) _houseCursorHistory.add(_housePageCursor);
          _housePageCursor = cursor;
          _houses = page.houses;
          _houseTotal = page.houseTotalCount;
          _houseNextCursor = page.houseNextCursor;
        }
      });
    } finally {
      if (mounted) setState(() => _archiveLoading = false);
    }
  }

  @override
  void dispose() {
    _citizenSearchController.dispose();
    _houseSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // House continuity is the V5 default. A House is extinct only when the
    // backend explicitly records status=EXTINCT; it is not inferred from a
    // temporary lifecycle transition between Humans.
    final houses = _houses;

    final deceasedCol = _buildDeceasedSection(context, _deceased, _houses);
    final housesCol = _buildHousesSection(context, houses);

    final cockpit = EarthPageCockpit(
      status: 'MEMORIAL',
      statusColor: context.goldColor,
      infoTitle: 'MEMORIAL ARCHIVE',
      infoDescription:
          'The Memorial is a permanent record of concluded lives and recorded Houses. Only facts published by the canonical historical read model are shown.',
      title: 'MEMORIAL',
      subtitle:
          'Permanent record of concluded lives and Houses across Earth',
      metrics: [
        CockpitMetric(
          label: 'Archived Citizens',
          value: '$_deceasedTotal',
          icon: Icons.people_outline,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Recorded Houses',
          value: '$_houseTotal',
          icon: Icons.shield_outlined,
          color: context.warningColor,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cockpit,
        const SizedBox(height: 28),
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
                  isSelected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _buildNarrowTabButton(
                  context,
                  title: 'HOUSES',
                  icon: Icons.shield_outlined,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: .15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: context.primaryColor.withValues(alpha: .4))
              : null,
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
                title,
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

  Widget _buildDeceasedSection(
      BuildContext context, List<MemorialCitizenSummary> deceased, List<MemorialHouseSummary> houses) {
    final filteredDeceased = deceased;
    final currentPage = _deceasedPage;
    final pageItems = deceased;

    return EarthSection(
      title: 'MEMORIAL CITIZENS',
      showHeader: false,
      showSurface: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (deceased.isNotEmpty)
            _buildSearchBar(
              context: context,
              controller: _citizenSearchController,
              hintText: 'Search citizens by name, House, or successor...',
              onChanged: (val) => setState(() {
                _citizenSearch = val;
                _deceasedPage = 1;
                _deceasedPageCursor = null;
                _deceasedNextCursor = null;
                _deceasedCursorHistory.clear();
                unawaited(_loadArchivePage(citizens: true));
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
              final citizen = indexed.$2;
              final name = citizen.displayName;
              final gen = citizen.generation;
              final deathDayNum = citizen.deathGameDay;
              final birthDayNum = citizen.birthGameDay;

              String? bornLabel;
              if (birthDayNum != null) {
                final bYear = ((birthDayNum - 1) ~/ 365) + 1;
                final bDay = ((birthDayNum - 1) % 365) + 1;
                bornLabel = 'Born: Year $bYear, Day $bDay';
              }

              String? ageLabel;
              if (deathDayNum != null && birthDayNum != null) {
                final totalDays = (deathDayNum - birthDayNum).clamp(0, 9999999);
                final ageY = totalDays ~/ 365;
                final ageD = totalDays % 365;
                ageLabel =
                    ageD > 0 ? 'Age: $ageY yrs, $ageD days' : 'Age: $ageY yrs';
              } else if (citizen.ageYears != null) {
                ageLabel = 'Age: ${citizen.ageYears} yrs';
              }

              final houseName = citizen.houseName;
              final legNum = citizen.finalLegacy == null
                  ? null
                  : int.tryParse(citizen.finalLegacy!);
              final stdNum = citizen.finalStanding == null
                  ? null
                  : int.tryParse(citizen.finalStanding!);
              final successor = citizen.successorName;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: indexed.$1 == pageItems.length - 1
                      ? 0
                      : context.spacingControl,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  onTap: widget.api == null ? null : () => showMemorialCitizenBiographyDialog(context, humanId: citizen.humanId, api: widget.api!),
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
                                if (gen != null)
                                  Text(
                                    '· Generation $gen',
                                    style: context.widgetValueStyle.copyWith(
                                      color: context.mutedColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(width: context.spacingInline),
                        ],
                      ),
                      SizedBox(height: context.spacingInline),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          if (houseName != null && houseName.isNotEmpty)
                            _badge(context, Icons.shield_outlined,
                                'House: $houseName'),
                          if (bornLabel != null)
                            _badge(context, Icons.cake_outlined, bornLabel),
                          if (ageLabel != null)
                            _badge(context, Icons.timelapse, ageLabel),
                          if (legNum != null)
                            _badge(context, Icons.stars_outlined,
                                'Personal Legacy: $legNum LP'),
                          if (stdNum != null)
                            _badge(context, Icons.shield,
                                'Final Standing: $stdNum pts'),
                          if (successor != null &&
                              successor.isNotEmpty &&
                              successor != '—')
                            _badge(context, Icons.person_pin,
                                'Successor: $successor'),
                        ],
                      ),
                      if (citizen.epitaph?.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          '“${citizen.epitaph}”',
                          style: context.bodyStyle.copyWith(
                            color: context.mutedColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                    ),
                  ),
                ),
              );
            }),
            if (_deceasedNextCursor != null || _deceasedCursorHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PAGE $currentPage ($_deceasedTotal TOTAL)',
                    style: context.captionStyle
                        .copyWith(color: context.mutedColor),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EarthButton(
                        label: 'PREVIOUS',
                        icon: Icons.chevron_left_rounded,
                        onPressed: _deceasedCursorHistory.isNotEmpty && !_archiveLoading
                            ? () async {
                                final previous = _deceasedCursorHistory.removeLast();
                                await _loadArchivePage(citizens: true, cursor: previous);
                                if (mounted) setState(() => _deceasedPage = currentPage - 1);
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      EarthButton(
                        label: 'NEXT',
                        icon: Icons.chevron_right_rounded,
                        onPressed: _deceasedNextCursor != null && !_archiveLoading
                            ? () async {
                                await _loadArchivePage(citizens: true, cursor: _deceasedNextCursor, next: true);
                                if (mounted) setState(() => _deceasedPage = currentPage + 1);
                              }
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

  Widget _buildHousesSection(BuildContext context, List<MemorialHouseSummary> houses) {
    final filteredHouses = houses;
    final currentPage = _housePage;
    final pageItems = houses;

    return EarthSection(
      title: 'HISTORICAL HOUSES',
      showHeader: false,
      showSurface: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (houses.isNotEmpty)
            _buildSearchBar(
              context: context,
              controller: _houseSearchController,
              hintText: 'Search recorded Houses by name...',
              onChanged: (val) => setState(() {
                _houseSearch = val;
                _housePage = 1;
                _housePageCursor = null;
                _houseNextCursor = null;
                _houseCursorHistory.clear();
                unawaited(_loadArchivePage(citizens: false));
              }),
            ),
          if (houses.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: context.spacingControl),
              child: DropdownButtonFormField<String>(
                value: _houseStatus,
                decoration: InputDecoration(
                  labelText: 'HOUSE STATUS',
                  labelStyle: context.captionStyle.copyWith(color: context.mutedColor),
                  filled: true,
                  fillColor: context.surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    borderSide: BorderSide(color: context.subtleBorderColor),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All Houses')),
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended')),
                  DropdownMenuItem(value: 'EXTINCT', child: Text('Extinct')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _houseStatus = value;
                    _housePage = 1;
                    _housePageCursor = null;
                    _houseNextCursor = null;
                    _houseCursorHistory.clear();
                  });
                  unawaited(_loadArchivePage(citizens: false));
                },
              ),
            ),
          if (houses.isEmpty)
            const EarthEmptyState(
              message:
                  'No recorded Houses are available in the archive.',
              icon: Icons.shield_outlined,
            )
          else if (filteredHouses.isEmpty)
            EarthEmptyState(
              message: 'No recorded houses match "$_houseSearch".',
              icon: Icons.search_off,
            )
          else ...[
            ...pageItems.indexed.map((indexed) {
              final house = indexed.$2;
              final houseName = house.houseName;
              final gen = house.generation;
              final count = house.deceasedCount?.toString();
              final motto = house.motto;

              final foundedDayNum = house.foundedGameDay;
              final foundedLabel = foundedDayNum == null
                  ? 'Founded: UNAVAILABLE'
                  : 'Founded: ${_formatGameDay(foundedDayNum)}';
              final lifespanDays = house.lifespanDays;
              final ageLabel = lifespanDays == null
                  ? 'Lifespan: UNAVAILABLE'
                  : 'Lifespan: ${_formatDuration(lifespanDays)}';

              final isExtinct = house.isExtinct;
              final statusLabel = isExtinct ? 'Extinct' : house.status;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: indexed.$1 == pageItems.length - 1
                      ? 0
                      : context.spacingControl,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  onTap: () => showHouseLineageDialog(
                    context,
                    houseId: house.houseId,
                    houseModel: house,
                    api: widget.api,
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
                            _badge(context, Icons.cake_outlined, foundedLabel),
                            _badge(context, Icons.timelapse, ageLabel),
                            if (count != null)
                              _badge(context, Icons.account_box_outlined,
                                  'Deceased Humans: $count'),
                            if (gen != null)
                              _badge(context, Icons.account_tree_outlined,
                                  'Generation: $gen'),
                            if (motto != null && motto.isNotEmpty)
                              _badge(context, Icons.format_quote,
                                  'Motto: $motto'),
                            _badge(context, Icons.account_tree_outlined,
                                'View Lineage Tree'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_houseNextCursor != null || _houseCursorHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PAGE $currentPage ($_houseTotal TOTAL)',
                    style: context.captionStyle
                        .copyWith(color: context.mutedColor),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EarthButton(
                        label: 'PREVIOUS',
                        icon: Icons.chevron_left_rounded,
                        onPressed: _houseCursorHistory.isNotEmpty && !_archiveLoading
                            ? () async {
                                final previous = _houseCursorHistory.removeLast();
                                await _loadArchivePage(citizens: false, cursor: previous);
                                if (mounted) setState(() => _housePage = currentPage - 1);
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      EarthButton(
                        label: 'NEXT',
                        icon: Icons.chevron_right_rounded,
                        onPressed: _houseNextCursor != null && !_archiveLoading
                            ? () async {
                                await _loadArchivePage(citizens: false, cursor: _houseNextCursor, next: true);
                                if (mounted) setState(() => _housePage = currentPage + 1);
                              }
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

  String _formatGameDay(int day) {
    final year = ((day - 1) ~/ 365) + 1;
    final yearDay = ((day - 1) % 365) + 1;
    return 'Year $year, Day $yearDay';
  }

  String _formatDuration(int days) {
    final years = days ~/ 365;
    final remaining = days % 365;
    return remaining == 0 ? '$years yrs' : '$years yrs, $remaining days';
  }
}
