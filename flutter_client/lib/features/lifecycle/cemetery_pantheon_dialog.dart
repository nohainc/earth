import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
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
      backgroundColor: EarthColors.panelSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: EarthColors.goldMetallic, width: 1.5),
      ),
      child: Container(
        width: 840,
        height: 680,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.account_balance,
                    color: EarthColors.goldMetallic, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLANETARY PANTHEON & CEMETERY ARCHIVE',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: EarthColors.goldMetallic,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Universal civil memorial records, deceased citizens, ancestral lineages, and lifetime achievements.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: EarthColors.textMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  key: const Key('btn-open-dynasty-tree'),
                  onPressed: () =>
                      showDynastyTreeDialog(context, api: widget.api),
                  icon: const Icon(Icons.account_tree_outlined, size: 14),
                  label: const Text('DYNASTY TREE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.goldMetallic,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: EarthColors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar & Tabs
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _loadData(),
                    decoration: InputDecoration(
                      hintText: 'Search citizen name, dynasty, or successor...',
                      prefixIcon: const Icon(Icons.search,
                          color: EarthColors.textMuted),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward,
                            color: EarthColors.cyanAccent),
                        onPressed: _loadData,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: EarthColors.cardSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: EarthColors.borderSubtle),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TabBar(
              controller: _tabController,
              indicatorColor: EarthColors.goldMetallic,
              labelColor: EarthColors.goldMetallic,
              unselectedLabelColor: EarthColors.textMuted,
              tabs: const [
                Tab(text: 'ALL CEMETERY MEMORIALS'),
                Tab(text: 'PANTHEON OF HONORS'),
                Tab(text: 'DYNASTIC HOUSES'),
              ],
            ),
            const Divider(color: EarthColors.borderSubtle, height: 1),
            const SizedBox(height: 12),

            // Content Area
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: EarthErrorState(
                              message: _error!, retry: _loadData))
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
      return Center(
        child: Text(
          'No historical records match the query.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: EarthColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: profiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EarthColors.cardSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EarthColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.bookmark,
                      color: EarthColors.goldMetallic, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: EarthColors.goldMetallic.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: EarthColors.goldMetallic.withAlpha(100)),
                    ),
                    child: Text(
                      'LEGACY: $legacy',
                      style: const TextStyle(
                          color: EarthColors.goldMetallic,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '“$epitaph”',
                style: const TextStyle(
                  color: EarthColors.cyanAccent,
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
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
      return Center(
        child: Text(
          'No dynastic houses registered yet.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: EarthColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: dynasties.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final d = dynasties[idx] as Map<String, dynamic>;
        final dynastyName = d['dynasty_name']?.toString() ?? 'House of Earth';
        final count = d['deceased_count']?.toString() ?? '1';
        final peakLegacy = d['peak_legacy']?.toString() ?? '0';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EarthColors.cardSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EarthColors.borderSubtle),
          ),
          child: Row(
            children: [
              const Icon(Icons.military_tech,
                  color: EarthColors.goldMetallic, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dynastyName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deceased Ancestors Inscribed: $count  •  Peak Ancestral Legacy: $peakLegacy',
                      style: const TextStyle(
                          color: EarthColors.textMuted, fontSize: 12),
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
        Icon(icon, size: 13, color: EarthColors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: EarthColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}
