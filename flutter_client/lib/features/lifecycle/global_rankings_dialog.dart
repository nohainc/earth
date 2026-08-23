import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

enum RankingCategory {
  citizens,
  cities,
  corporations,
  dynasties,
  technologies,
}

Future<void> showGlobalRankingsDialog(
  BuildContext context, {
  EarthApi api = const EarthApi(),
  EarthState? state,
  RankingCategory initialCategory = RankingCategory.citizens,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
        child: GlobalRankingsDialog(
          api: api,
          state: state,
          initialCategory: initialCategory,
        ),
      ),
    ),
  );
}

class GlobalRankingsDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final RankingCategory initialCategory;

  const GlobalRankingsDialog({
    super.key,
    this.api = const EarthApi(),
    this.state,
    this.initialCategory = RankingCategory.citizens,
  });

  @override
  State<GlobalRankingsDialog> createState() => _GlobalRankingsDialogState();
}

class _GlobalRankingsDialogState extends State<GlobalRankingsDialog> {
  late RankingCategory _selectedCategory;
  String _selectedMetric = 'composite';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _rankingsData;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _fetchRankings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchRankings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categoryKey = _selectedCategory.name;
      final res = await widget.api.rankings(
        category: categoryKey,
        metric: _selectedMetric,
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
      );
      if (mounted) {
        setState(() {
          _rankingsData = res;
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

  List<Map<String, dynamic>> _getCurrentEntities() {
    if (_rankingsData == null) return const [];
    switch (_selectedCategory) {
      case RankingCategory.citizens:
        final raw = _rankingsData!['citizens'] as List<dynamic>?;
        if (raw != null && raw.isNotEmpty) {
          return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        final wealth = _rankingsData!['wealth'] as List<dynamic>? ?? const [];
        return wealth.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = Map<String, dynamic>.from(entry.value as Map);
          return {
            'rank': idx + 1,
            'rankDelta': 0,
            'tierBadge': idx == 0 ? 'Sovereign' : (idx < 3 ? 'Patrician' : 'Citizen'),
            'id': item['human_id'] ?? 'H-0000',
            'displayName': item['displayName'] ?? item['human_id'] ?? 'Citizen',
            'credits': NumberFormatHelper.parseNumber(item['balance']),
            'standing': 100,
            'legacy': 0,
            'compositeScore': NumberFormatHelper.parseNumber(item['balance']),
          };
        }).toList();

      case RankingCategory.cities:
        final raw = _rankingsData!['cities'] as List<dynamic>? ?? const [];
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      case RankingCategory.corporations:
        final raw = _rankingsData!['corporations'] as List<dynamic>? ?? const [];
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      case RankingCategory.dynasties:
        final raw = _rankingsData!['dynasticHouses'] as List<dynamic>? ?? const [];
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      case RankingCategory.technologies:
        final raw = _rankingsData!['technologies'] as List<dynamic>? ?? const [];
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }

  void _showEntityInspector(Map<String, dynamic> entity) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EarthColors.panelSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: EarthColors.borderSubtle),
        ),
        title: Row(
          children: [
            Icon(
              _getCategoryIcon(_selectedCategory),
              color: EarthColors.cyanAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entity['displayName'] ?? entity['name'] ?? entity['dynasty_name'] ?? entity['id'] ?? 'Entity Profile',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _inspectorRow('Entity ID / Ticker', entity['id']?.toString() ?? '—'),
              if (entity['rank'] != null)
                _inspectorRow('Global Rank', '#${entity['rank']}'),
              if (entity['tierBadge'] != null)
                _inspectorRow('Prestige Tier', entity['tierBadge'].toString()),
              if (entity['compositeScore'] != null)
                _inspectorRow('Composite Legacy', '${entity['compositeScore']} pts'),
              if (entity['credits'] != null)
                _inspectorRow('Liquid Credits', '${entity['credits']} C'),
              if (entity['standing'] != null)
                _inspectorRow('Civic Standing', '${entity['standing']} pts'),
              if (entity['legacy'] != null)
                _inspectorRow('Legacy Score', '${entity['legacy']} pts'),
              if (entity['cityId'] != null)
                _inspectorRow('City Jurisdiction', entity['cityId'].toString()),
              if (entity['dynastyName'] != null)
                _inspectorRow('Dynastic House', entity['dynastyName'].toString()),
              if (entity['residents'] != null)
                _inspectorRow('Residents', '${entity['residents']} citizens'),
              if (entity['treasury'] != null)
                _inspectorRow('Municipal Treasury', '${entity['treasury']} C'),
              if (entity['member_count'] != null)
                _inspectorRow('Members / Employees', '${entity['member_count']}'),
              if (entity['marketCap'] != null)
                _inspectorRow('Market Cap', '${entity['marketCap']} C'),
              if (entity['peak_legacy'] != null)
                _inspectorRow('Peak Dynastic Legacy', '${entity['peak_legacy']} pts'),
              if (entity['progress'] != null)
                _inspectorRow('Research Progress', '${entity['progress']}%'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE', style: TextStyle(color: EarthColors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  Widget _inspectorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: EarthColors.textMuted, fontSize: 12)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(RankingCategory cat) {
    switch (cat) {
      case RankingCategory.citizens:
        return Icons.person;
      case RankingCategory.cities:
        return Icons.location_city;
      case RankingCategory.corporations:
        return Icons.corporate_fare;
      case RankingCategory.dynasties:
        return Icons.account_balance;
      case RankingCategory.technologies:
        return Icons.memory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entities = _getCurrentEntities();
    final top3 = entities.take(3).toList();
    final userStanding = _rankingsData?['userStanding'] as Map<String, dynamic>?;

    return Container(
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EarthColors.goldMetallic, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: EarthColors.goldMetallic.withAlpha(30),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            // 1. Header
            _buildHeader(),

            // 2. Category Navigation Bar
            _buildCategoryBar(),

            // 3. Sub-metrics & Search Row
            _buildFilterAndSearchRow(),

            // 4. Content (Podium + Table)
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: EarthColors.goldMetallic,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Error: $_error',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchRankings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: EarthColors.cyanAccent,
                                  foregroundColor: Colors.black,
                                ),
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        )
                      : entities.isEmpty
                          ? const Center(
                              child: Text(
                                'No leaderboard entries found for this filter.',
                                style: TextStyle(color: EarthColors.textMuted),
                              ),
                            )
                          : ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              children: [
                                // Top 3 Podium
                                if (top3.isNotEmpty && _searchController.text.isEmpty)
                                  _buildPodium(top3),

                                const SizedBox(height: 16),

                                // Section Heading
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'GLOBAL STANDINGS (${entities.length} TOTAL)',
                                      style: const TextStyle(
                                        color: EarthColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const Text(
                                      'TAP ROW TO INSPECT',
                                      style: TextStyle(
                                        color: EarthColors.textMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Table Rows
                                ...entities.map((item) => _buildLeaderboardRow(item)),
                              ],
                            ),
            ),

            // 5. Sticky "My Position" Footer Bar
            if (userStanding != null && _selectedCategory == RankingCategory.citizens)
              _buildStickyUserPosition(userStanding),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: EarthColors.goldMetallic, size: 24),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CIVILIZATIONAL LEADERBOARDS & RANKINGS',
                  style: TextStyle(
                    color: EarthColors.goldMetallic,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  'Planetary rankings across Sovereign Citizens, Municipalities, Corporate Syndicates & Dynasties.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: EarthColors.panelSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: RankingCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            final label = cat.name.toUpperCase();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getCategoryIcon(cat),
                      size: 14,
                      color: isSelected ? Colors.black : EarthColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(label),
                  ],
                ),
                selected: isSelected,
                selectedColor: EarthColors.goldMetallic,
                backgroundColor: EarthColors.cardSurface,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: .8,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedCategory = cat;
                      _selectedMetric = 'composite';
                    });
                    _fetchRankings();
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterAndSearchRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by name, ID, or dynasty...',
                  hintStyle: const TextStyle(color: EarthColors.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 16, color: EarthColors.textMuted),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14, color: EarthColors.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            _fetchRankings();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  filled: true,
                  fillColor: EarthColors.panelSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: EarthColors.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: EarthColors.borderSubtle),
                  ),
                ),
                onSubmitted: (_) => _fetchRankings(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _fetchRankings,
            style: IconButtonButtonBorder(
              backgroundColor: EarthColors.goldMetallic.withAlpha(40),
              foregroundColor: EarthColors.goldMetallic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CIVILIZATIONAL APEX PODIUM (TOP 3)',
            style: TextStyle(
              color: EarthColors.goldMetallic,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2nd Place (Silver)
              if (top3.length > 1)
                Expanded(child: _buildPodiumCard(top3[1], 2, const Color(0xff94a3b8), '🥈 SILVER')),

              const SizedBox(width: 8),

              // 1st Place (Gold)
              Expanded(child: _buildPodiumCard(top3[0], 1, EarthColors.goldMetallic, '🥇 GOLD')),

              const SizedBox(width: 8),

              // 3rd Place (Bronze)
              if (top3.length > 2)
                Expanded(child: _buildPodiumCard(top3[2], 3, const Color(0xffb45309), '🥉 BRONZE')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumCard(
    Map<String, dynamic> entity,
    int rank,
    Color medalColor,
    String medalLabel,
  ) {
    final title = entity['displayName'] ?? entity['name'] ?? entity['dynasty_name'] ?? entity['id'] ?? 'Leader';
    final score = entity['compositeScore'] ?? entity['treasury'] ?? entity['marketCap'] ?? entity['peak_legacy'] ?? entity['progress'] ?? '—';
    final sub = entity['dynastyName'] ?? entity['cityId'] ?? entity['id'] ?? '';

    return InkWell(
      onTap: () => _showEntityInspector(entity),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: medalColor.withAlpha(120), width: rank == 1 ? 1.5 : 1.0),
          boxShadow: [
            if (rank == 1)
              BoxShadow(
                color: EarthColors.goldMetallic.withAlpha(40),
                blurRadius: 10,
              ),
          ],
        ),
        child: Column(
          children: [
            Text(
              medalLabel,
              style: TextStyle(
                color: medalColor,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 6),
            CircleAvatar(
              radius: rank == 1 ? 18 : 15,
              backgroundColor: medalColor.withAlpha(40),
              child: Icon(
                _getCategoryIcon(_selectedCategory),
                color: medalColor,
                size: rank == 1 ? 18 : 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: medalColor.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$score pts',
                style: TextStyle(
                  color: medalColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardRow(Map<String, dynamic> entity) {
    final rank = NumberFormatHelper.parseNumber(entity['rank']);
    final rankDelta = entity['rankDelta'];
    final tierBadge = entity['tierBadge']?.toString();
    final title = entity['displayName'] ?? entity['name'] ?? entity['dynasty_name'] ?? entity['id'] ?? 'Entity';
    final sub = entity['dynastyName'] ?? entity['cityId'] ?? entity['id'] ?? '';
    final score = entity['compositeScore'] ?? entity['treasury'] ?? entity['marketCap'] ?? entity['peak_legacy'] ?? entity['progress'] ?? '—';

    return InkWell(
      onTap: () => _showEntityInspector(entity),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: EarthColors.cardSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: rank == 1
                ? EarthColors.goldMetallic.withAlpha(100)
                : EarthColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Rank Number
            SizedBox(
              width: 32,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rank == 1
                      ? EarthColors.goldMetallic
                      : (rank <= 3 ? Colors.white : EarthColors.textMuted),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),

            // Rank Delta Indicator
            _buildDeltaIndicator(rankDelta),
            const SizedBox(width: 10),

            // Entity Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tierBadge != null) ...[
                        const SizedBox(width: 6),
                        _buildTierBadge(tierBadge),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Score Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EarthColors.panelSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EarthColors.borderSubtle),
              ),
              child: Text(
                '$score',
                style: const TextStyle(
                  color: EarthColors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeltaIndicator(dynamic delta) {
    if (delta == 'NEW') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: violetColor.withAlpha(40),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(color: violetColor, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      );
    }
    final numDelta = delta is num ? delta.toInt() : 0;
    if (numDelta > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_drop_up, color: EarthColors.cyanAccent, size: 16),
          Text(
            '+$numDelta',
            style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      );
    } else if (numDelta < 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_drop_down, color: Colors.redAccent, size: 16),
          Text(
            '$numDelta',
            style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }
    return const SizedBox(
      width: 24,
      child: Center(
        child: Text('—', style: TextStyle(color: EarthColors.textMuted, fontSize: 10)),
      ),
    );
  }

  Widget _buildTierBadge(String tier) {
    Color color = EarthColors.textMuted;
    if (tier == 'Sovereign') color = EarthColors.goldMetallic;
    if (tier == 'Patrician') color = violetColor;
    if (tier == 'Pioneer') color = EarthColors.cyanAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withAlpha(100), width: .8),
      ),
      child: Text(
        tier.toUpperCase(),
        style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStickyUserPosition(Map<String, dynamic> userStanding) {
    final rank = userStanding['rank'] ?? '—';
    final total = userStanding['totalTracked'] ?? '—';
    final tier = userStanding['tierBadge'] ?? 'Citizen';
    final score = userStanding['score'] ?? '0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(top: BorderSide(color: EarthColors.goldMetallic, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, color: EarthColors.goldMetallic, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'YOUR STANDING: Rank #$rank of $total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildTierBadge(tier.toString()),
                  ],
                ),
                Text(
                  'Composite Legacy: $score pts',
                  style: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: EarthColors.goldMetallic,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            child: const Text('TOP OF TABLE'),
          ),
        ],
      ),
    );
  }
}

class IconButtonButtonBorder extends ButtonStyle {
  IconButtonButtonBorder({
    required Color backgroundColor,
    required Color foregroundColor,
  }) : super(
          backgroundColor: WidgetStateProperty.all(backgroundColor),
          foregroundColor: WidgetStateProperty.all(foregroundColor),
          padding: WidgetStateProperty.all(const EdgeInsets.all(8)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        );
}

class NumberFormatHelper {
  static int parseNumber(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? 0;
    return 0;
  }
}
