import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import 'building_detail_upgrade_dialog.dart';
import 'real_estate_dialogs.dart';

class BuildingsHubScreen extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const BuildingsHubScreen({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<BuildingsHubScreen> createState() => _BuildingsHubScreenState();
}

class _BuildingsHubScreenState extends State<BuildingsHubScreen> {
  int _mainTab = 0; // 0 = PRIVATE, 1 = CIVIC (single-column mode only)
  String _selectedCategory = 'all';
  String _catalogFilter = 'all';
  String _sortMode = 'default';
  String _plannerSelectedBlueprint = 'restaurant';




  double _creditResult(Map<String, dynamic> building) {
    final outputType = building['resource_output_type']?.toString();
    final creditOutput = outputType == 'credits' || outputType == null
        ? asDoubleOr(building['resource_output_amount'], 0)
        : 0;
    return creditOutput - asDoubleOr(building['daily_operating_credits'], 0);
  }

  void _showBuildingFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final buildings = widget.state.buildings.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final shares = widget.state.investmentShares.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final dividends = widget.state.civicDividends.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final catalog = widget.state.buildingCatalog;
    final zoning = widget.state.districtZoning;
    final cityId = widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final viewerId = widget.state.human['id']?.toString();

    final totalSlots = asIntOr(zoning['totalSlots'], 10);
    final civicReservedSlots = asIntOr(zoning['civicReservedSlots'], 3);
    final usedPrivateSlots = asIntOr(zoning['usedPrivateSlots'], 0);
    final usedCivicSlots = asIntOr(zoning['usedCivicSlots'], 0);
    final availablePrivateSlots = asIntOr(zoning['availablePrivateSlots'], 7);
    final population = asIntOr(zoning['population'], 12);
    final creditsAvailable = asDouble(
      widget.state.human['credits'] ??
          widget.state.finance['balance'] ??
          widget.state.personalFinance['balance'],
    );
    final materialsAvailable = asDouble(
      widget.state.resources['materials'] ?? widget.state.resources['material'],
    );

    final privateBuildings = buildings.where((b) => b['owner_id'] == viewerId && b['status'] != 'closed').toList();
    final publicBuildings = buildings.where((b) => b['ownership_class'] == 'public_investment').toList();

    // Civic summary stats
    final lastDividend = dividends.isNotEmpty ? dividends.last : null;
    final lastUbi = lastDividend != null ? asDoubleOr(lastDividend['base_ubi_per_resident_crd'], 0) : 0.0;
    final totalMyShares = shares.fold<int>(0, (sum, s) => sum + asIntOr(s['shares_owned'], 0));

    return EarthSection(
      title: 'BUILDINGS',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Buildings are the productive assets of the economy: they use resources, provide services, and generate returns.',
        'Private buildings belong to you and generate personal income. Civic buildings belong to the city and distribute surplus to all residents.',
        'Operating policy affects output and upkeep. Automatic upkeep keeps routine maintenance out of the main decision loop.',
      ],
      trailing: null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide   = width >= 1100; // 3 columns
          final isMedium = width >=  720; // 2 columns

          final privatePanel = _buildPrivatePanel(
            context,
            privateBuildings: privateBuildings,
            catalog: catalog,
            totalSlots: totalSlots,
            civicReservedSlots: civicReservedSlots,
            usedPrivateSlots: usedPrivateSlots,
            usedCivicSlots: usedCivicSlots,
            availablePrivateSlots: availablePrivateSlots,
            population: population,
            cityId: cityId,
            creditsAvailable: creditsAvailable,
            materialsAvailable: materialsAvailable,
            viewerId: viewerId,
          );

          final civicPanel = _buildCivicPanel(
            context,
            publicBuildings: publicBuildings,
            shares: shares,
            dividends: dividends,
            usedCivicSlots: usedCivicSlots,
            civicReservedSlots: civicReservedSlots,
            totalMyShares: totalMyShares,
            lastUbi: lastUbi,
          );

          final catalogPanel = _buildCatalogPanel(context, catalog: catalog);

          // ── Wide (≥ 1100 px): 3 equal columns ──────────────────────────────
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: privatePanel),
                const SizedBox(width: 16),
                Expanded(child: civicPanel),
                const SizedBox(width: 16),
                Expanded(child: catalogPanel),
              ],
            );
          }

          // ── Medium (720–1099 px): 2 columns ─────────────────────────────────
          // Left: PRIVATE/CIVIC with their own 2-tab switcher
          // Right: CATALOG always visible
          if (isMedium) {
            final privateCivicTabBar = Container(
              margin: EdgeInsets.only(bottom: context.spacingControl),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      context,
                      title: 'PRIVATE',
                      icon: Icons.storefront_outlined,
                      isSelected: _mainTab == 0,
                      onTap: () {
                        EarthAudioEngine.instance.playClick();
                        setState(() => _mainTab = 0);
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      context,
                      title: 'CIVIC',
                      icon: Icons.account_balance_outlined,
                      isSelected: _mainTab == 1,
                      onTap: () {
                        EarthAudioEngine.instance.playClick();
                        setState(() => _mainTab = 1);
                      },
                    ),
                  ),
                ],
              ),
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      privateCivicTabBar,
                      if (_mainTab == 0) privatePanel else civicPanel,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: catalogPanel),
              ],
            );
          }

          // ── Narrow (< 720 px): 3 tabs, single column ────────────────────────
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      child: _buildTabButton(
                        context,
                        title: 'PRIVATE',
                        icon: Icons.storefront_outlined,
                        isSelected: _mainTab == 0,
                        onTap: () {
                          EarthAudioEngine.instance.playClick();
                          setState(() => _mainTab = 0);
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildTabButton(
                        context,
                        title: 'CIVIC',
                        icon: Icons.account_balance_outlined,
                        isSelected: _mainTab == 1,
                        onTap: () {
                          EarthAudioEngine.instance.playClick();
                          setState(() => _mainTab = 1);
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildTabButton(
                        context,
                        title: 'CATALOG',
                        icon: Icons.menu_book_outlined,
                        isSelected: _mainTab == 2,
                        onTap: () {
                          EarthAudioEngine.instance.playClick();
                          setState(() => _mainTab = 2);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_mainTab == 0)
                privatePanel
              else if (_mainTab == 1)
                civicPanel
              else
                catalogPanel,
            ],
          );
        },
      ),
    );
  }


  // ─── Shared tab button (matches Memorial page style) ──────────────────────
  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.primaryColor.withValues(alpha: .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: context.primaryColor.withValues(alpha: .4)) : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
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
              Text(
                subtitle != null ? '$title ($subtitle)' : title,
                maxLines: 1,
                style: context.controlStyle.copyWith(
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── PRIVATE panel ─────────────────────────────────────────────────────────
  Widget _buildPrivatePanel(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required List<dynamic> catalog,
    required int totalSlots,
    required int civicReservedSlots,
    required int usedPrivateSlots,
    required int usedCivicSlots,
    required int availablePrivateSlots,
    required int population,
    required String cityId,
    required double? creditsAvailable,
    required double? materialsAvailable,
    required String? viewerId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRIVATE BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        // Private stat header
        _buildAttributeGrid(context, [
          ('BUILDINGS OWNED', '${privateBuildings.length}', Icons.storefront_outlined, context.primaryColor),
          ('AVAILABLE TO BUILD', '$availablePrivateSlots', Icons.domain_add_outlined, availablePrivateSlots > 0 ? context.successColor : context.dangerColor),
          ('CAPACITY IN USE', '$usedPrivateSlots', Icons.pie_chart_outline, context.warningColor),
        ],
        ),
        SizedBox(height: context.spacingControl),
        _buildBuildingRecommendation(
          context,
          privateBuildings: privateBuildings,
          availablePrivateSlots: availablePrivateSlots,
        ),
        SizedBox(height: context.spacingControl),
        SizedBox(height: context.spacingTopic),
        _buildEstatesTab(
          context,
          privateBuildings: privateBuildings,
          catalog: catalog,
          totalSlots: totalSlots,
          civicReserved: civicReservedSlots,
          usedPrivate: usedPrivateSlots,
          usedCivic: usedCivicSlots,
          population: population,
          viewerId: viewerId,
        ),
      ],
    );
  }


  // ─── CIVIC panel ───────────────────────────────────────────────────────────
  Widget _buildCivicPanel(
    BuildContext context, {
    required List<Map<String, dynamic>> publicBuildings,
    required List<Map<String, dynamic>> shares,
    required List<Map<String, dynamic>> dividends,
    required int usedCivicSlots,
    required int civicReservedSlots,
    required int totalMyShares,
    required double lastUbi,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CIVIC BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        // Civic stat header
        _buildAttributeGrid(context, [
          ('CIVIC SLOTS', '$usedCivicSlots / $civicReservedSlots USED', Icons.account_balance_outlined, context.secondaryColor),
          ('MEGAPROJECTS', publicBuildings.isEmpty ? 'NONE ACTIVE' : '${publicBuildings.length} ACTIVE', Icons.apartment_outlined, context.primaryColor),
          ('YOUR SHARES', totalMyShares > 0 ? '$totalMyShares SHARES' : 'NO HOLDINGS', Icons.bar_chart_outlined, totalMyShares > 0 ? context.successColor : context.mutedColor),
          ('LAST UBI PAYOUT', lastUbi > 0 ? '+${formatWholeNumber(lastUbi)} CRD' : 'NONE YET', Icons.payments_outlined, lastUbi > 0 ? context.successColor : context.mutedColor),
        ],
        ),
        SizedBox(height: context.spacingControl),
        _buildCivicAndShareMarketSection(context, publicBuildings, shares, dividends),
      ],
    );
  }

  // ─── CATALOG panel ─────────────────────────────────────────────────────────
  Widget _buildCatalogPanel(BuildContext context, {required List<dynamic> catalog}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CATALOG', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildCatalogTab(context, catalog: catalog),
      ],
    );
  }

  Widget _buildAttributeGrid(
    BuildContext context,
    List<(String, String, IconData, Color)> attributes,
  ) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < attributes.length; i++) {
      final item = attributes[i];
      final row = _buildAttributeRow(
        context,
        label: item.$1,
        value: item.$2,
        icon: item.$3,
        accentColor: item.$4,
      );
      (i.isEven ? left : right).add(row);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 450) {
          return Column(children: [...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left)),
            const SizedBox(width: 24),
            Expanded(child: Column(children: right)),
          ],
        );
      },
    );
  }

  Widget _buildAttributeRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(label, style: context.bodyStyle.copyWith(color: context.mutedColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: context.bodyStyle.copyWith(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }



  Widget _buildBuildingRecommendation(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required int availablePrivateSlots,
  }) {
    final needsAttention = privateBuildings.where((building) {
      return building['status']?.toString() == 'under_construction' ||
          asDoubleOr(building['condition'], 100) < 80;
    }).toList();

    final String title;
    final String message;
    final IconData icon;
    final Color color;
    if (needsAttention.isNotEmpty) {
      final buildingName = needsAttention.first['name']?.toString() ?? 'A building';
      title = 'Review $buildingName';
      message = 'A building needs attention. Open Manage Building to restore performance or finish commissioning.';
      icon = Icons.warning_amber_outlined;
      color = context.warningColor;
    } else if (privateBuildings.isEmpty) {
      title = 'Create your first productive asset';
      message = 'Start with a building that matches your available Credits, Materials, and city capacity.';
      icon = Icons.domain_add_outlined;
      color = context.primaryColor;
    } else if (availablePrivateSlots > 0) {
      title = 'Capacity is available';
      message = '$availablePrivateSlots private building space${availablePrivateSlots == 1 ? '' : 's'} remain. Compare the next building in Build.';
      icon = Icons.trending_up_outlined;
      color = context.successColor;
    } else {
      title = 'Buildings are operating normally';
      message = 'Private capacity is full. Grow the city or improve infrastructure before expanding further.';
      icon = Icons.check_circle_outline;
      color = context.successColor;
    }

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.widgetTitleStyle),
                const SizedBox(height: 3),
                Text(message, style: context.widgetFooterStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: MY BUILDINGS ====================
  Widget _buildEstatesTab(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required List<dynamic> catalog,
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
    required String? viewerId,
  }) {
    final filteredBuildings = _selectedCategory == 'all'
        ? privateBuildings.where((b) => b['status'] != 'closed').toList()
        : privateBuildings.where((b) {
            if (b['status'] == 'closed') return false;
            final cat = b['category']?.toString() ?? '';
            if (_selectedCategory == 'profitable') {
              return _creditResult(b) > 0;
            }
            if (_selectedCategory == 'attention') {
              return b['status']?.toString() == 'under_construction' ||
                  asDoubleOr(b['condition'], 100) < 80;
            }
            if (_selectedCategory == 'commercial') return cat == 'commercial';
            if (_selectedCategory == 'energy') return cat == 'energy';
            if (_selectedCategory == 'manufacturing') return cat == 'manufacturing' || cat == 'industrial';
            if (_selectedCategory == 'compute') return cat == 'compute' || cat == 'high_tech';
            if (_selectedCategory == 'food') return cat == 'food';
            if (_selectedCategory == 'medical') return cat == 'medical';
            if (_selectedCategory == 'orbital') return cat == 'orbital';
            return true;
          }).toList();

    if (_sortMode == 'profit') {
      filteredBuildings.sort((a, b) => _creditResult(b).compareTo(_creditResult(a)));
    } else if (_sortMode == 'upkeep') {
      filteredBuildings.sort((a, b) => asDoubleOr(a['daily_operating_credits'], 0)
          .compareTo(asDoubleOr(b['daily_operating_credits'], 0)));
    } else if (_sortMode == 'attention') {
      filteredBuildings.sort((a, b) {
        final aScore = a['status']?.toString() == 'under_construction' ? 0 : asDoubleOr(a['condition'], 100);
        final bScore = b['status']?.toString() == 'under_construction' ? 0 : asDoubleOr(b['condition'], 100);
        return aScore.compareTo(bScore);
      });
    } else if (_sortMode == 'resource') {
      filteredBuildings.sort((a, b) => asDoubleOr(b['resource_output_amount'], 0)
          .compareTo(asDoubleOr(a['resource_output_amount'], 0)));
    } else if (_sortMode == 'capacity') {
      filteredBuildings.sort((a, b) => asIntOr(a['slot_footprint'], 1)
          .compareTo(asIntOr(b['slot_footprint'], 1)));
    } else if (_sortMode == 'newest') {
      filteredBuildings.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Buildings List
        if (filteredBuildings.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EarthEmptyState(
                message: _selectedCategory == 'attention'
                    ? 'All owned buildings are operating normally.'
                    : _selectedCategory == 'profitable'
                        ? 'No owned buildings are currently generating a positive daily credit margin.'
                        : 'No owned buildings match this category. Build one to expand your productive capacity.',
                icon: _selectedCategory == 'attention'
                    ? Icons.check_circle_outline
                    : Icons.location_city_outlined,
              ),
              if (_selectedCategory != 'attention') ...[
                const SizedBox(height: 8),
              ],
            ],
          )
        else
          Column(
            children: filteredBuildings
                .map((b) => _buildBuildingCard(context, b, viewerId, catalog))
                .toList(),
          ),

        SizedBox(height: context.spacingTopic),
        _buildRecentBuildingActivity(context),
      ],
    );
  }

  // ==================== TAB 2: BUILD ====================
  Widget _buildPlannerTab(
    BuildContext context, {
    required List<dynamic> catalog,
    required int availablePrivateSlots,
    required String cityId,
    required int population,
    required double? creditsAvailable,
    required double? materialsAvailable,
  }) {
    final blueprints = catalog.whereType<Map>().where((b) => b['ownershipClass'] != 'civic' && b['ownershipClass'] != 'public_investment').toList();
    if (blueprints.isEmpty) {
      return const EarthEmptyState(
        message: 'No blueprints available for planning.',
        icon: Icons.architecture_outlined,
      );
    }

    final currentSpec = blueprints.firstWhere(
      (b) => b['type'] == _plannerSelectedBlueprint,
      orElse: () => blueprints.first,
    );

    final name = currentSpec['name']?.toString() ?? 'Blueprint';
    final type = currentSpec['type']?.toString() ?? '';
    final category = currentSpec['category']?.toString() ?? 'commercial';
    final footprint = asIntOr(currentSpec['slotFootprint'], 1);
    final creditCost = asIntOr(currentSpec['baseCreditCost'], 8500);
    final materialCost = asIntOr(currentSpec['baseMaterialCost'], 120);
    final dailyYield = asDoubleOr(currentSpec['dailyCreditRevenue'] ?? currentSpec['dailyOutputCredits'], 600);
    final opCost = asDoubleOr(currentSpec['dailyOperatingCredits'] ?? currentSpec['dailyStaffingCredits'], 100);
    final netDailyProfit = dailyYield - opCost;
    final paybackDays = asIntOr(currentSpec['estimatedPaybackDays'], (creditCost / (netDailyProfit > 0 ? netDailyProfit : 1)).round());
    final sensitivity = currentSpec['resourceSensitivity']?.toString().toUpperCase() ?? 'MEDIUM';
    final risk = currentSpec['maintenanceRisk']?.toString().toUpperCase() ?? 'LOW';
    final purpose = currentSpec['primaryEconomicPurpose']?.toString() ?? 'Economic Output';
    final reqPop = asIntOr(currentSpec['minCityPopulation'], 0);

    final hasEnoughSlots = availablePrivateSlots >= footprint;
    final hasEnoughPop = reqPop == 0 || population >= reqPop;
    final hasEnoughCredits = creditsAvailable == null || creditsAvailable >= creditCost;
    final hasEnoughMaterials = materialsAvailable == null || materialsAvailable >= materialCost;
    final canConstruct = hasEnoughSlots && hasEnoughPop && hasEnoughCredits && hasEnoughMaterials;

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
            children: [
              Icon(Icons.architecture_outlined, color: context.primaryColor),
              const SizedBox(width: 8),
              Text('BUILD A BUILDING', style: context.topicTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a building, review its cost and expected performance, then commit the required credits, materials, and building capacity.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),

          // Building comparison cards
          Text('CHOOSE A BUILDING', style: context.captionStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: blueprints.map((b) {
              final bType = b['type']?.toString() ?? '';
              final bName = b['name']?.toString() ?? bType;
              final bSpace = asIntOr(b['slotFootprint'], 1);
              final bCost = asIntOr(b['baseCreditCost'], 8500);
              final bOutput = asDoubleOr(b['dailyCreditRevenue'] ?? b['dailyOutputCredits'], 0);
              final bUpkeep = asDoubleOr(b['dailyOperatingCredits'] ?? b['dailyStaffingCredits'], 0);
              final bResourceType = b['dailyOutputResourceType']?.toString();
              final bResourceAmount = asDoubleOr(b['dailyOutputResourceAmount'], 0);
              final cardHasCapacity = availablePrivateSlots >= bSpace;
              final cardHasCredits = creditsAvailable == null || creditsAvailable >= bCost;
              final cardHasMaterials = materialsAvailable == null || materialsAvailable >= asIntOr(b['baseMaterialCost'], 120);
              final cardCanBuild = cardHasCapacity && cardHasCredits && cardHasMaterials;
              final isSel = _plannerSelectedBlueprint == bType;
              return SizedBox(
                width: 230,
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radiusControl),
                  onTap: () {
                    EarthAudioEngine.instance.playClick();
                    setState(() => _plannerSelectedBlueprint = bType);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSel
                          ? context.primaryColor.withValues(alpha: .08)
                          : context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                        color: isSel ? context.primaryColor : context.subtleBorderColor,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bName, style: context.widgetTitleStyle),
                        const SizedBox(height: 4),
                        Text('$bSpace capacity space${bSpace > 1 ? 's' : ''} · ${formatWholeNumber(bCost)} CRD', style: context.widgetFooterStyle),
                        const SizedBox(height: 4),
                        Text(
                          bResourceAmount > 0 && bResourceType != null
                              ? 'Output: +${bResourceAmount.toStringAsFixed(1)} ${bResourceType.toUpperCase()}/day'
                              : 'Net: ${bOutput - bUpkeep >= 0 ? '+' : ''}${formatWholeNumber(bOutput - bUpkeep)} CRD/day',
                          style: context.bodyStyle.copyWith(
                            color: bResourceAmount > 0 && bResourceType != null
                                ? context.secondaryColor
                                : bOutput - bUpkeep >= 0
                                    ? context.successColor
                                    : context.dangerColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cardCanBuild
                              ? 'AVAILABLE TO BUILD'
                              : !cardHasCapacity
                                  ? 'CAPACITY UNAVAILABLE'
                                  : !cardHasCredits
                                      ? 'CREDITS REQUIRED'
                                      : 'MATERIALS REQUIRED',
                          style: context.captionStyle.copyWith(
                            color: cardCanBuild ? context.successColor : context.warningColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: context.spacingControl),

          // Deep Financial Intelligence Analysis Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$name ($type)', style: context.widgetTitleStyle),
                    EarthBadge(
                      label: '$footprint CAPACITY SPACE${footprint > 1 ? 'S' : ''}',
                      variant: EarthBadgeVariant.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Category: ${category.toUpperCase()} • Primary Purpose: $purpose', style: context.widgetFooterStyle),
                const Divider(height: 20),

                // Strategic Metric Grid
                EarthMetricGrid(
                  metrics: [
                    EarthMetricTile(
                      label: 'ESTIMATED PAYBACK',
                      value: '~ $paybackDays DAYS',
                      icon: Icons.timer_outlined,
                      accentColor: paybackDays <= 15 ? context.successColor : context.primaryColor,
                    ),
                    EarthMetricTile(
                      label: 'PROJECTED NET DAILY',
                      value: '+${formatWholeNumber(netDailyProfit)} CRD',
                      icon: Icons.trending_up,
                      accentColor: context.successColor,
                    ),
                    EarthMetricTile(
                      label: 'RESOURCE SENSITIVITY',
                      value: sensitivity,
                      icon: Icons.water_drop_outlined,
                      accentColor: sensitivity == 'LOW' ? context.successColor : context.warningColor,
                    ),
                    EarthMetricTile(
                      label: 'MAINTENANCE WEAR RISK',
                      value: risk,
                      icon: Icons.build_outlined,
                      accentColor: risk == 'LOW' ? context.successColor : context.warningColor,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Strategic Requirements Checklist Box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CONSTRUCTION PREREQUISITES CHECKLIST:', style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _buildRequirementItem(
                            context,
                            'Building Capacity (Requires $footprint space${footprint > 1 ? 's' : ''})',
                            hasEnoughSlots,
                          ),
                          _buildRequirementItem(
                            context,
                            creditsAvailable == null
                                ? 'Credits: ${formatWholeNumber(creditCost)} required'
                                : 'Credits: ${formatWholeNumber(creditCost)} required · ${formatWholeNumber(creditsAvailable)} available',
                            hasEnoughCredits,
                          ),
                          _buildRequirementItem(
                            context,
                            materialsAvailable == null
                                ? 'Materials: $materialCost required'
                                : 'Materials: $materialCost required · ${formatWholeNumber(materialsAvailable)} available',
                            hasEnoughMaterials,
                          ),
                          if (reqPop > 0)
                            _buildRequirementItem(
                              context,
                              'City Population ($population / $reqPop)',
                              hasEnoughPop,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Direct Build / Licensing Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    EarthButton(
                      label: 'START CONSTRUCTION',
                      icon: Icons.domain_add_outlined,
                      variant: EarthButtonVariant.primary,
                      onPressed: widget.busy || !canConstruct
                          ? null
                          : () async {
                              EarthAudioEngine.instance.playClick();
                              await _confirmConstruction(
                                context,
                                buildingName: name,
                                buildingType: _plannerSelectedBlueprint,
                                cityId: cityId,
                                creditCost: creditCost,
                                materialCost: materialCost,
                                capacityCost: footprint,
                                remainingCapacity: availablePrivateSlots - footprint,
                                netDailyCredits: netDailyProfit,
                              );
                            },
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

  Future<void> _confirmConstruction(
    BuildContext context, {
    required String buildingName,
    required String buildingType,
    required String cityId,
    required int creditCost,
    required int materialCost,
    required int capacityCost,
    required int remainingCapacity,
    required double netDailyCredits,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Build $buildingName', style: context.topicTitleStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review this investment before construction begins.', style: context.bodyStyle),
            const SizedBox(height: 12),
            Text('Cost', style: context.captionStyle),
            Text('${formatWholeNumber(creditCost)} Credits + $materialCost Materials', style: context.bodyStyle),
            const SizedBox(height: 8),
            Text('Capacity', style: context.captionStyle),
            Text('$capacityCost space${capacityCost > 1 ? 's' : ''} · $remainingCapacity private spaces remaining', style: context.bodyStyle),
            const SizedBox(height: 8),
            Text('Expected result', style: context.captionStyle),
            Text(
              '${netDailyCredits >= 0 ? '+' : ''}${formatWholeNumber(netDailyCredits)} Credits/day',
              style: context.bodyStyle.copyWith(
                color: netDailyCredits >= 0 ? context.successColor : context.dangerColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          EarthButton(
            label: 'CONFIRM BUILD',
            icon: Icons.domain_add_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.action(() => const EarthApi().purchaseBuilding(
            buildingType: buildingType,
            name: buildingName,
            cityId: cityId,
          ));
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('$buildingName construction started.')),
        );
      }
    }
  }

  Widget _buildRequirementItem(BuildContext context, String title, bool isMet) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.cancel,
          color: isMet ? context.successColor : context.dangerColor,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: context.bodyStyle.copyWith(
            color: isMet ? null : context.dangerColor,
            fontWeight: isMet ? FontWeight.normal : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ==================== TAB 4: BUILDING CATALOG ====================
  Widget _catalogFilterChip(
    BuildContext context, {
    required String label,
    required String filter,
  }) {
    final isSelected = _catalogFilter == filter;
    return InkWell(
      onTap: () => setState(() => _catalogFilter = filter),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.primaryColor.withValues(alpha: .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? context.primaryColor : context.subtleBorderColor),
        ),
        child: Text(label, style: context.controlStyle.copyWith(color: isSelected ? context.primaryColor : context.mutedColor)),
      ),
    );
  }

  Color _resourceColor(BuildContext context, String value) {
    return EarthResourceMeta.forCommodity(value.split(' ').last).color;
  }

  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
  }) {
    final list = catalog.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final zoning = widget.state.districtZoning;
    final availablePrivateSlots = asIntOr(zoning['availablePrivateSlots'], 0);
    final cityId = widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final creditsAvailable = asDouble(widget.state.human['credits'] ?? widget.state.finance['balance'] ?? widget.state.personalFinance['balance']);
    final materialsAvailable = asDouble(widget.state.resources['materials'] ?? widget.state.resources['material']);
    list.sort((a, b) {
      final categoryCompare = (a['category']?.toString() ?? 'commercial')
          .compareTo(b['category']?.toString() ?? 'commercial');
      if (categoryCompare != 0) return categoryCompare;
      return (a['name']?.toString() ?? 'Blueprint')
          .compareTo(b['name']?.toString() ?? 'Blueprint');
    });
    final privateCount = list.where((item) {
      final ownership = item['ownershipClass']?.toString();
      return ownership != 'civic' && ownership != 'public_investment';
    }).length;
    final civicCount = list.length - privateCount;
    final filteredList = list.where((item) {
      final ownership = item['ownershipClass']?.toString();
      if (_catalogFilter == 'private') {
        return ownership != 'civic' && ownership != 'public_investment';
      }
      if (_catalogFilter == 'civic') {
        return ownership == 'civic' || ownership == 'public_investment';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _catalogFilterChip(context, label: 'ALL (${list.length})', filter: 'all'),
            _catalogFilterChip(context, label: 'COMMON ($privateCount)', filter: 'private'),
            _catalogFilterChip(context, label: 'CIVIC ($civicCount)', filter: 'civic'),
          ],
        ),
        SizedBox(height: context.spacingControl),

        // Catalog List
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: filteredList.map<Widget>((item) {
            final name = item['name']?.toString() ?? 'Blueprint';
            final category = (item['category']?.toString() ?? 'commercial').toUpperCase();
            final footprint = asIntOr(item['slotFootprint'], 1);
            final creditCost = asIntOr(item['baseCreditCost'], 8500);
            final matCost = asIntOr(item['baseMaterialCost'], 120);
            final purpose = item['primaryEconomicPurpose']?.toString() ?? 'Economic Production';
            final desc = item['description']?.toString() ?? '';
            final civicBenefit = item['civicBenefit']?.toString();
            final rawTiers = item['tiers'] as List?;
            final tierCount = rawTiers != null ? rawTiers.length : 3;
            final outputType = item['resourceOutputType']?.toString();
            final outputAmount = asDoubleOr(item['resourceOutputAmount'], 0);
            final outputCredits = asDoubleOr(item['dailyCreditRevenue'], 0);
            final constructionDays = footprint;
            final inputs = <(IconData, String)>[];
            void addInput(String key, String label, IconData icon) {
              final amount = asDoubleOr(item[key], 0);
              if (amount > 0) inputs.add((icon, '${amount.toStringAsFixed(1)} $label'));
            }
            addInput('dailyEnergyUpkeep', 'ENERGY', Icons.bolt_rounded);
            addInput('dailyFoodUpkeep', 'FOOD', Icons.eco_outlined);
            addInput('dailyMaterialsUpkeep', 'MATERIAL', Icons.terrain_outlined);
            addInput('dailyComponentsUpkeep', 'COMPONENTS', Icons.precision_manufacturing_outlined);
            addInput('dailyComputeUpkeep', 'COMPUTE', Icons.memory_rounded);
            final maintenanceCredits = asDoubleOr(item['dailyStaffingCredits'], 0);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.widgetTitleStyle.copyWith(color: context.primaryColor)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          EarthBadge(label: '$footprint SPACE${footprint > 1 ? 'S' : ''}', variant: EarthBadgeVariant.primary),
                          EarthBadge(label: 'UPGRADES $tierCount', variant: EarthBadgeVariant.neutral),
                          EarthBadge(label: category, variant: EarthBadgeVariant.neutral),
                        ],
                      ),
                      const SizedBox(height: 6),
                  Text(desc, style: context.bodyStyle.copyWith(color: context.mutedColor)),
                  const SizedBox(height: 6),
                  Text('Economic Purpose: $purpose', style: context.widgetFooterStyle),
                  if (civicBenefit != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.secondaryColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('🏛️ Civic Benefit: $civicBenefit', style: TextStyle(color: context.secondaryColor, fontSize: 11)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 3,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('COST', style: context.captionStyle),
                      const SizedBox(width: 5),
                      Icon(Icons.account_balance_wallet_outlined, size: 14, color: EarthResourceColors.credits),
                      Text(formatWholeNumber(creditCost), style: context.widgetFooterStyle),
                      const SizedBox(width: 4),
                      Icon(EarthResourceMeta.forCommodity('material').icon, size: 14, color: EarthResourceColors.materials),
                      Text('$matCost', style: context.widgetFooterStyle),
                    ],
                  ),
                  if (inputs.isNotEmpty || outputType != null || outputCredits > 0) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 3,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (inputs.isNotEmpty) ...[
                          Text('INPUT', style: context.captionStyle),
                          const SizedBox(width: 5),
                          ...inputs.expand((input) => <Widget>[
                                Icon(input.$1, size: 14, color: _resourceColor(context, input.$2)),
                                Text(input.$2.split(' ').first, style: context.widgetFooterStyle),
                              ]),
                        ],
                      ],
                    ),
                    if (outputType != null || outputCredits > 0) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                        Text('OUTPUT', style: context.captionStyle),
                        const SizedBox(width: 5),
                        Icon(
                          outputType == null || outputType == 'credits'
                              ? Icons.account_balance_wallet_outlined
                              : EarthResourceMeta.forCommodity(outputType).icon,
                          size: 14,
                          color: EarthResourceMeta.forCommodity(outputType ?? 'credits').color,
                        ),
                        Text(
                          outputType == null || outputType == 'credits'
                              ? formatWholeNumber(outputCredits)
                              : '${outputAmount.toStringAsFixed(1)} ${outputType.toUpperCase()}',
                          style: context.widgetFooterStyle,
                        ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 4),
                  if (maintenanceCredits > 0)
                    Wrap(
                      spacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('MAINTENANCE', style: context.captionStyle),
                        const SizedBox(width: 5),
                        Icon(Icons.account_balance_wallet_outlined, size: 14, color: EarthResourceColors.credits),
                        Text(formatWholeNumber(maintenanceCredits), style: context.widgetFooterStyle),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('CONSTRUCTION', style: context.captionStyle),
                      const SizedBox(width: 5),
                      Icon(Icons.schedule_outlined, size: 14, color: context.primaryColor),
                      Text('$constructionDays ${constructionDays == 1 ? 'DAY' : 'DAYS'}', style: context.widgetFooterStyle),
                    ],
                  ),
                ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Builder(
                      builder: (context) {
                        final canBuild = !widget.busy &&
                            availablePrivateSlots >= footprint &&
                            (creditsAvailable == null || creditsAvailable >= creditCost) &&
                            (materialsAvailable == null || materialsAvailable >= matCost);
                        return IconButton(
                          tooltip: canBuild ? 'Build this building' : 'Insufficient resources or capacity',
                          icon: const Icon(Icons.domain_add_outlined),
                          color: context.primaryColor,
                          onPressed: canBuild
                              ? () => _confirmConstruction(
                                    context,
                                    buildingName: name,
                                    buildingType: item['type']?.toString() ?? '',
                                    cityId: cityId,
                                    creditCost: creditCost,
                                    materialCost: matCost,
                                    capacityCost: footprint,
                                    remainingCapacity: availablePrivateSlots - footprint,
                                    netDailyCredits: outputCredits - maintenanceCredits,
                                  )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentBuildingActivity(BuildContext context) {
    final events = widget.state.publicActivity
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((event) {
          final text = [event['title'], event['body'], event['message'], event['description']]
              .whereType<Object>()
              .join(' ')
              .toLowerCase();
          return text.contains('building') ||
              text.contains('construction') ||
              text.contains('upgrade') ||
              text.contains('repair');
        })
        .take(5)
        .toList();

    if (events.isEmpty) return const SizedBox.shrink();

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
          Text('RECENT BUILDING ACTIVITY', style: context.topicTitleStyle),
          const SizedBox(height: 8),
          ...events.map((event) {
            final title = event['title']?.toString() ?? 'Building update';
            final detail = event['body']?.toString() ??
                event['message']?.toString() ??
                event['description']?.toString() ??
                '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.domain_outlined, size: 16, color: context.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail.isEmpty ? title : '$title · $detail',
                      style: context.widgetFooterStyle,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== BUILDING CAPACITY ====================
  Widget _buildDistrictZoningVisualizer(
    BuildContext context, {
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
  }) {
    final privateCapacity = (totalSlots - civicReserved).clamp(0, totalSlots).toInt();
    final privateUsed = usedPrivate.clamp(0, privateCapacity).toInt();
    final privateFree = (privateCapacity - privateUsed).clamp(0, privateCapacity).toInt();
    final privateProgress = privateCapacity == 0 ? 1.0 : privateUsed / privateCapacity;
    final civicUsed = usedCivic.clamp(0, civicReserved).toInt();
    final civicProgress = civicReserved == 0 ? 0.0 : civicUsed / civicReserved;

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
            children: [
              Icon(Icons.domain_outlined, color: context.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text('BUILDING CAPACITY', style: context.widgetTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Population supports $privateCapacity private building spaces. $privateFree are available for expansion.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PRIVATE BUILDINGS', style: context.captionStyle),
              Text('$privateUsed / $privateCapacity used', style: context.widgetFooterStyle),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: privateProgress,
              minHeight: 10,
              backgroundColor: context.primaryColor.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(
                privateFree > 0 ? context.primaryColor : context.dangerColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CIVIC SPACE', style: context.captionStyle),
              Text('$civicUsed / $civicReserved reserved', style: context.widgetFooterStyle),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: civicProgress,
              minHeight: 8,
              backgroundColor: context.secondaryColor.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(context.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILDING CARD ====================
  Widget _buildBuildingCard(
    BuildContext context,
    Map<String, dynamic> b,
    String? viewerId,
    List<dynamic> catalog,
  ) {
    final id = b['id']?.toString() ?? '';
    final name = b['name']?.toString() ?? 'Facility';
    final type = (b['building_type']?.toString() ?? 'building').replaceAll('-', ' ').toUpperCase();
    final tier = asIntOr(b['tier'], 1);
    final condition = asDoubleOr(b['condition'], 100);
    final footprint = asIntOr(b['slot_footprint'], 1);
    final policy = b['operating_policy']?.toString() ?? 'balanced';
    final ownershipClass = b['ownership_class']?.toString() ?? 'private';
    final isOwner = b['owner_id']?.toString() == viewerId;
    final isPublic = ownershipClass == 'public_investment';
    final isCivic = ownershipClass == 'civic';

    final resOutType = b['resource_output_type']?.toString();
    final resOutAmt = asDoubleOr(b['resource_output_amount'], 0);
    final opCost = asDoubleOr(b['daily_operating_credits'], 0);
    final netCreditResult =
        (resOutType == 'credits' || resOutType == null ? resOutAmt : 0) - opCost;

    final uEnergy = asDoubleOr(b['upkeep_energy'], 0);
    final uFood = asDoubleOr(b['upkeep_food'], 0);
    final uMat = asDoubleOr(b['upkeep_materials'], 0);
    final uComp = asDoubleOr(b['upkeep_components'], 0);
    final uDat = asDoubleOr(b['upkeep_compute'], 0);

    final status = b['status']?.toString() ?? 'active';
    final isUnderConstruction = status == 'under_construction';
    final constructionProgress = asDoubleOr(b['construction_progress'], 100);

    String condStatus = '100% OPTIMAL';
    Color condColor = context.successColor;
    if (isUnderConstruction) {
      condStatus = 'UNDER CONSTRUCTION (${constructionProgress.toStringAsFixed(0)}%)';
      condColor = context.warningColor;
    } else if (condition < 20) {
      condStatus = 'OFFLINE (0% YIELD)';
      condColor = context.dangerColor;
    } else if (condition < 50) {
      condStatus = 'CRITICAL (40% YIELD)';
      condColor = context.dangerColor;
    } else if (condition < 80) {
      condStatus = 'DEGRADED (75% YIELD)';
      condColor = context.warningColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(
          color: isCivic
              ? context.secondaryColor.withValues(alpha: .4)
              : isPublic
                  ? context.primaryColor.withValues(alpha: .4)
                  : context.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(name, style: context.widgetTitleStyle),
                        EarthBadge(label: '$footprint SPACE${footprint > 1 ? 'S' : ''}', variant: EarthBadgeVariant.neutral),
                        EarthBadge(label: 'TIER $tier', variant: EarthBadgeVariant.primary),
                        if (isUnderConstruction) ...[
                          const EarthBadge(label: 'CONSTRUCTION', variant: EarthBadgeVariant.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUnderConstruction
                          ? '$type · Commissioning in progress (${constructionProgress.toStringAsFixed(0)}%)'
                          : condition < 80
                              ? '$type · Condition: ${condition.toStringAsFixed(0)}% ($condStatus)'
                              : '$type · District building',
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  EarthBadge(
                    label: isCivic
                        ? 'CIVIC UTILITY'
                        : isPublic
                            ? 'PUBLIC INVESTMENT'
                            : 'PRIVATE BUILDING',
                    variant: isCivic
                        ? EarthBadgeVariant.primary
                        : isPublic
                            ? EarthBadgeVariant.secondary
                            : EarthBadgeVariant.success,
                  ),
                  const SizedBox(height: 4),
                  if (isUnderConstruction || condition < 80) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: condColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isUnderConstruction
                            ? '${constructionProgress.toStringAsFixed(0)}% COMPLETE'
                            : '${condition.toStringAsFixed(0)}% HEALTH',
                        style: context.captionStyle.copyWith(
                          color: condColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Resource Drains & Output Flow Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.subtleBorderColor.withValues(alpha: .5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DAILY INPUT UPKEEP', style: context.captionStyle.copyWith(fontSize: 10)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (opCost > 0) _buildPill(context, '-${formatWholeNumber(opCost)} CRD', context.warningColor),
                          if (uEnergy > 0) _buildPill(context, '-${uEnergy.toStringAsFixed(1)} NRG', context.warningColor),
                          if (uFood > 0) _buildPill(context, '-${uFood.toStringAsFixed(1)} FOOD', context.warningColor),
                          if (uMat > 0) _buildPill(context, '-${uMat.toStringAsFixed(1)} MAT', context.warningColor),
                          if (uComp > 0) _buildPill(context, '-${uComp.toStringAsFixed(1)} COMP', context.warningColor),
                          if (uDat > 0) _buildPill(context, '-${uDat.toStringAsFixed(1)} DAT', context.warningColor),
                          if (opCost == 0 && uEnergy == 0 && uFood == 0 && uMat == 0 && uComp == 0 && uDat == 0)
                            _buildPill(context, 'ZERO UPKEEP', context.inkColor.withValues(alpha: .5)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_outlined, color: context.primaryColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DAILY OUTPUT YIELD', style: context.captionStyle.copyWith(fontSize: 10)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (resOutAmt > 0)
                            _buildPill(
                              context,
                              '+${resOutType == 'credits' || resOutType == null ? formatWholeNumber(resOutAmt) : resOutAmt.toStringAsFixed(1)} ${(resOutType ?? 'CRD').toUpperCase()}',
                              context.successColor,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NET DAILY RESULT', style: context.captionStyle.copyWith(fontSize: 10)),
              Text(
                netCreditResult >= 0
                    ? '+${formatWholeNumber(netCreditResult)} CRD'
                    : '${formatWholeNumber(netCreditResult)} CRD',
                style: context.widgetTitleStyle.copyWith(
                  color: netCreditResult >= 0 ? context.successColor : context.dangerColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Secondary management actions stay collapsed until needed.
          if (isOwner)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('MANAGE BUILDING', style: context.widgetTitleStyle),
              subtitle: Text('Policy, upkeep, upgrades, and demolition', style: context.widgetFooterStyle),
              children: [
            Text(
              'Higher output increases operating cost and may increase wear. Eco mode lowers resource use at the expense of output.',
              style: context.widgetFooterStyle,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('OPERATING POLICY:', style: context.captionStyle.copyWith(fontSize: 10)),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final p in [
                      {'id': 'balanced', 'label': 'Balanced · normal'},
                      {'id': 'high_output', 'label': 'High output · +25%'},
                      {'id': 'eco_reserve', 'label': 'Eco · lower upkeep'},
                      {'id': 'overclock', 'label': 'Overclock · +50%'},
                    ])
                      ChoiceChip(
                        label: Text(p['label']!, style: const TextStyle(fontSize: 10)),
                        selected: policy == p['id'],
                        visualDensity: VisualDensity.compact,
                        onSelected: widget.busy
                            ? null
                            : (selected) async {
                                if (selected && policy != p['id']) {
                                  EarthAudioEngine.instance.playClick();
                                  await widget.action(() => const EarthApi().setBuildingOperatingPolicy(
                                        buildingId: id,
                                        policy: p['id']!,
                                      ));
                                  _showBuildingFeedback('$name: ${p['label']} policy enabled.');
                                }
                              },
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('AUTO-REPAIR (<80%):', style: context.captionStyle.copyWith(fontSize: 10)),
                    const SizedBox(width: 6),
                    Text(
                      'Cost: ${isCivic ? '1 Material' : '1 Component'} / cycle',
                      style: context.captionStyle.copyWith(fontSize: 10, color: context.primaryColor),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch.adaptive(
                    value: b['auto_repair_enabled'] == true || b['auto_repair_enabled']?.toString() == 'true',
                    activeThumbColor: context.primaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: widget.busy
                        ? null
                        : (val) async {
                            EarthAudioEngine.instance.playClick();
                            await widget.action(() => const EarthApi().setBuildingAutoRepair(
                                  buildingId: id,
                                  enabled: val,
                                ));
                            _showBuildingFeedback(
                              '$name: automatic repair ${val ? 'enabled' : 'disabled'}.',
                            );
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (condition < 100)
                  EarthButton(
                    label: 'REPAIR TO 100%',
                    icon: Icons.build_outlined,
                    variant: EarthButtonVariant.primary,
                    onPressed: widget.busy
                        ? null
                        : () async {
                            EarthAudioEngine.instance.playClick();
                            await widget.action(() => const EarthApi().repairBuilding(buildingId: id));
                            _showBuildingFeedback('$name repaired to full condition.');
                          },
                  ),
                EarthButton(
                  label: 'UPGRADE TREE (TIER ${tier + 1})',
                  icon: Icons.account_tree_outlined,
                  variant: EarthButtonVariant.primary,
                  onPressed: widget.busy
                      ? null
                      : () async {
                          EarthAudioEngine.instance.playClick();
                          await showBuildingDetailUpgradeDialog(
                            context,
                            widget.action,
                            b,
                            catalog,
                          );
                          _showBuildingFeedback('$name upgrade completed.');
                        },
                  ),
                EarthButton(
                  label: 'DEMOLISH / RECYCLE',
                  icon: Icons.delete_outline,
                  variant: EarthButtonVariant.danger,
                  onPressed: widget.busy
                      ? null
                      : () async {
                          EarthAudioEngine.instance.playClick();
                          await showDemolishConfirmDialog(context, widget.action, b);
                          _showBuildingFeedback('$name was removed and its capacity was released.');
                        },
                ),
              ],
            ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPill(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        text,
        style: context.captionStyle.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildCivicAndShareMarketSection(
    BuildContext context,
    List<Map<String, dynamic>> publicBuildings,
    List<Map<String, dynamic>> shares,
    List<Map<String, dynamic>> dividends,
  ) {
    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PUBLIC PROJECTS & DIVIDENDS', style: context.topicTitleStyle),
              const EarthBadge(label: '70/30 UBI + PARTICIPATION', variant: EarthBadgeVariant.secondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Civic and municipal facilities distribute 100% of their net operating surplus to registered city residents (70% as equal Base UBI, and 30% weighted by citizen participation). Public megaprojects offer fractional investment shares providing direct daily dividend yields.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),

          if (publicBuildings.isNotEmpty) ...[
            Text('ACTIVE PUBLIC MEGAPROJECTS (CROWDFUNDED)', style: context.captionStyle),
            const SizedBox(height: 6),
            Column(
              children: publicBuildings.map((pb) {
                final bId = pb['id']?.toString() ?? '';
                final bName = pb['name']?.toString() ?? 'Megaproject';
                final totalShares = asIntOr(pb['total_shares'], 100);
                final pricePerShare = asDoubleOr(pb['price_per_share_crd'], 500);
                final myHolding = shares.firstWhere(
                  (s) => s['building_id'] == bId,
                  orElse: () => <String, dynamic>{'shares_owned': 0},
                );
                final myCount = asIntOr(myHolding['shares_owned'], 0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bName, style: context.widgetTitleStyle),
                            const SizedBox(height: 2),
                            Text(
                              'Price: ${formatWholeNumber(pricePerShare)} CRD / Share · Your Holdings: $myCount / $totalShares Shares (${((myCount / totalShares) * 100).toStringAsFixed(1)}%)',
                              style: context.widgetFooterStyle,
                            ),
                          ],
                        ),
                      ),
                      EarthButton(
                        label: 'INVEST IN SHARES',
                        icon: Icons.add_chart_outlined,
                        variant: EarthButtonVariant.secondary,
                        onPressed: widget.busy
                            ? null
                            : () {
                                EarthAudioEngine.instance.playClick();
                                showPublicShareInvestDialog(context, widget.action, pb);
                              },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: context.spacingControl),
          ],

          if (dividends.isNotEmpty) ...[
            Text('RECENT CIVIC CITIZEN DIVIDEND PAYOUTS', style: context.captionStyle),
            const SizedBox(height: 6),
            Column(
              children: dividends.map((d) {
                final day = asIntOr(d['day'], 0);
                final totalPool = asDoubleOr(d['total_surplus_crd'], 0);
                final ubiPerCitizen = asDoubleOr(d['base_ubi_per_resident_crd'], 0);
                final partBonus = asDoubleOr(d['participation_bonus_per_resident_crd'], 0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GAME DAY $day PAYOUT', style: context.widgetTitleStyle),
                      Wrap(
                        spacing: 8,
                        children: [
                          EarthBadge(label: 'TOTAL SURPLUS: +${formatWholeNumber(totalPool)} CRD', variant: EarthBadgeVariant.primary),
                          EarthBadge(label: 'BASE UBI: +${formatWholeNumber(ubiPerCitizen)} CRD', variant: EarthBadgeVariant.success),
                          if (partBonus > 0)
                            EarthBadge(label: 'BONUS: +${formatWholeNumber(partBonus)} CRD', variant: EarthBadgeVariant.secondary),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
