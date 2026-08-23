import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../dynasty/dynasty_tree_dialog.dart';

void showCemeteryPantheonDialog(BuildContext context, {EarthApi? api}) {
  showDialog(
    context: context,
    builder: (ctx) => CemeteryPantheonDialog(api: api ?? const EarthApi()),
  );
}

class CemeteryPantheonDialog extends StatefulWidget {
  final EarthApi api;
  const CemeteryPantheonDialog({super.key, required this.api});

  @override
  State<CemeteryPantheonDialog> createState() => _CemeteryPantheonDialogState();
}

class _CemeteryPantheonDialogState extends State<CemeteryPantheonDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<dynamic> _cemeteryProfiles = [];
  List<dynamic> _pantheonLeaders = [];
  List<dynamic> _dynasticHouses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final search = _searchController.text.trim();
      final cemResult = await widget.api.cemetery(
        search: search.isNotEmpty ? search : null,
      );
      final panResult = await widget.api.pantheon();

      if (mounted) {
        setState(() {
          _cemeteryProfiles =
              (cemResult['cemetery'] as List<dynamic>?) ?? const [];
          _pantheonLeaders =
              (panResult['deceasedPantheon'] as List<dynamic>?) ?? const [];
          _dynasticHouses =
              (panResult['dynasticHouses'] as List<dynamic>?) ?? const [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.panelColor,
      insetPadding: EdgeInsets.symmetric(
        horizontal: context.spacingTopic,
        vertical: context.spacingPage,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      child: Container(
        width: 840,
        height: 680,
        padding: EdgeInsets.all(context.spacingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  color: context.primaryColor,
                  size: context.iconSize + 4,
                ),
                SizedBox(width: context.spacingTitleOffset),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLANETARY PANTHEON & CEMETERY ARCHIVE',
                        style: context.pageTitleStyle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Universal civil memorial records, deceased citizens, ancestral lineages, and lifetime achievements.',
                        style: context.widgetFooterStyle,
                      ),
                    ],
                  ),
                ),
                EarthButton(
                  buttonKey: const Key('btn-open-dynasty-tree'),
                  label: 'DYNASTY TREE',
                  icon: Icons.account_tree_outlined,
                  onPressed: () => showDynastyTreeDialog(context, api: widget.api),
                ),
                SizedBox(width: context.spacingInline),
                IconButton(
                  icon: Icon(Icons.close, color: context.mutedColor, size: context.iconSize),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: context.spacingTopic),

            // Search Bar & Tabs
            EarthSearchInput(
              controller: _searchController,
              hintText: 'Search citizen name, dynasty, or successor...',
              onChanged: (_) => _loadData(),
              onClear: _loadData,
            ),
            SizedBox(height: context.spacingTitleOffset),

            TabBar(
              controller: _tabController,
              indicatorColor: context.primaryColor,
              labelColor: context.primaryColor,
              unselectedLabelColor: context.mutedColor,
              labelStyle: context.controlStyle,
              unselectedLabelStyle: context.controlStyle.copyWith(fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'ALL CEMETERY MEMORIALS'),
                Tab(text: 'PANTHEON OF HONORS'),
                Tab(text: 'DYNASTIC HOUSES'),
              ],
            ),
            Divider(color: context.subtleBorderColor, height: 1),
            SizedBox(height: context.spacingTitleOffset),

            // Content Area
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: context.primaryColor))
                  : _error != null
                      ? Center(child: EarthErrorState(message: _error!, retry: _loadData))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildCemeteryList(_cemeteryProfiles),
                            _buildCemeteryList(_pantheonLeaders),
                            _buildDynastyList(_dynasticHouses),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCemeteryList(List<dynamic> profiles) {
    if (profiles.isEmpty) {
      return const EarthEmptyState(
        message: 'No historical records match the query.',
        icon: Icons.inbox_outlined,
      );
    }

    return ListView.separated(
      itemCount: profiles.length,
      separatorBuilder: (_, __) => SizedBox(height: context.spacingControl),
      itemBuilder: (ctx, idx) {
        final p = profiles[idx] as Map<String, dynamic>;
        final name = p['display_name']?.toString() ?? 'Citizen Inscription';
        final humanId = p['human_id']?.toString() ?? 'H-0000';
        final day = p['death_game_day']?.toString() ?? '1';
        final legacy = p['final_legacy']?.toString() ?? '0';
        final standing = p['final_standing']?.toString() ?? '0';
        final successor = p['successor_name']?.toString() ?? 'Public Trust';
        final cause = p['cause_of_death']?.toString() ?? 'Natural Aging';
        final epitaph = p['epitaph']?.toString() ??
            'Pioneered civilization across the frontier of Earth.';
        final dynasty = p['dynasty_name']?.toString() ?? 'Founding Dynasty';

        return Container(
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
                  Icon(Icons.bookmark,
                      color: context.primaryColor,
                      size: context.iconSize),
                  SizedBox(width: context.spacingInline),
                  Expanded(
                    child: Text(
                      name,
                      style: context.widgetValueStyle,
                    ),
                  ),
                  EarthStatusPill(
                    label: 'LEGACY',
                    value: '$legacy LP',
                    color: context.primaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '“$epitaph”',
                style: context.widgetFooterStyle.copyWith(
                  color: context.primaryColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: context.spacingInline),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _badge(Icons.badge, 'ID: $humanId'),
                  _badge(Icons.groups, 'Dynasty: $dynasty'),
                  _badge(Icons.shield, 'Standing: $standing'),
                  _badge(Icons.event, 'Entered Archive: Day $day'),
                  _badge(Icons.favorite_border, 'Cause: $cause'),
                  _badge(Icons.person_pin, 'Successor: $successor'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDynastyList(List<dynamic> dynasties) {
    if (dynasties.isEmpty) {
      return const EarthEmptyState(
        message: 'No dynastic houses registered yet.',
        icon: Icons.account_tree_outlined,
      );
    }

    return ListView.separated(
      itemCount: dynasties.length,
      separatorBuilder: (_, __) => SizedBox(height: context.spacingControl),
      itemBuilder: (ctx, idx) {
        final d = dynasties[idx] as Map<String, dynamic>;
        final dynastyName = d['dynasty_name']?.toString() ?? 'House of Earth';
        final count = d['deceased_count']?.toString() ?? '1';
        final peakLegacy = d['peak_legacy']?.toString() ?? '0';

        return Container(
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.military_tech,
                  color: context.primaryColor,
                  size: context.iconSize),
              SizedBox(width: context.spacingTitleOffset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dynastyName,
                      style: context.widgetValueStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deceased Ancestors Inscribed: $count  •  Peak Ancestral Legacy: $peakLegacy',
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _badge(IconData icon, String label) {
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
}
