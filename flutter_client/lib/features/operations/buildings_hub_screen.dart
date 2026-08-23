import 'package:flutter/material.dart';
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
  int _activeTab = 0; // 0 = Estates, 1 = Construction Planner, 2 = Global Catalog
  String _selectedCategory = 'all';
  String _plannerSelectedBlueprint = 'restaurant';

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

    final privateBuildings = buildings.where((b) => b['owner_id'] == viewerId && b['status'] != 'closed').toList();
    final publicBuildings = buildings.where((b) => b['ownership_class'] == 'public_investment' || b['ownership_type'] == 'public_investment').toList();
    final civicBuildings = buildings.where((b) => b['ownership_class'] == 'civic' || b['ownership_type'] == 'municipal').toList();

    final totalDailyPrivateYield = privateBuildings.fold<double>(
      0,
      (sum, b) => sum + asDoubleOr(b['base_revenue_crd'], 0),
    );
    final totalDailyOperatingCost = privateBuildings.fold<double>(
      0,
      (sum, b) => sum + asDoubleOr(b['daily_operating_credits'], 0),
    );

    return EarthSection(
      title: 'BUILDINGS & URBAN INFRASTRUCTURE HUB',
      showSurface: false,
      infoBulletPoints: const [
        'Core Economic Objects: Buildings own their physical footprint, daily operating expenses, maintenance buffers, condition wear, and commercial returns.',
        'Three-Layer System: Manage active District Estates, evaluate new investments in the Construction Planner, and browse the global EARTH Blueprint Catalog.',
        'Multi-Tier Upgrade Trees: Expand facilities through multi-tier upgrade trees (Tier 1 → Tier 2 → Tier 3 → Tier 4) to unlock capacity and systemic perks.',
        'Operating Policies: Switch between Balanced, High Output, Eco Reserve, and Overclock modes.',
        'Civic Dividends & Public Megaprojects: Public utilities distribute 100% of net surplus revenue to citizens via 70/30 UBI + Participation bonuses.',
      ],
      trailing: EarthButton(
        label: 'ACQUIRE & CONSTRUCT',
        icon: Icons.domain_add_outlined,
        variant: EarthButtonVariant.primary,
        onPressed: widget.busy
            ? null
            : () {
                EarthAudioEngine.instance.playClick();
                showBuildingAcquisitionDialog(
                  context,
                  widget.action,
                  catalog,
                  cityId,
                  availablePrivateSlots,
                );
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // High Level Metrics
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'ESTATES OWNED',
                value: '${privateBuildings.length} SITES (${privateBuildings.fold<int>(0, (sum, b) => sum + asIntOr(b['slot_footprint'], 1))} SLOTS)',
                icon: Icons.storefront_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'NET DAILY REVENUE',
                value: '+${formatWholeNumber(totalDailyPrivateYield - totalDailyOperatingCost)} CRD',
                icon: Icons.trending_up_outlined,
                accentColor: context.successColor,
              ),
              EarthMetricTile(
                label: 'PUBLIC SHARES OWNED',
                value: '${shares.fold<int>(0, (sum, s) => sum + asIntOr(s['shares_owned'], 0))} SHARES',
                icon: Icons.pie_chart_outline,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'ZONING CAPACITY',
                value: '$availablePrivateSlots / ${totalSlots - civicReservedSlots} FREE PLOTS',
                icon: Icons.grid_view_outlined,
                accentColor: availablePrivateSlots > 0 ? context.warningColor : context.dangerColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),

          // 3-Tab Bar: Estates / Construction Planner / Global Catalog
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMainTabChip(0, '🏛️ MY DISTRICT ESTATES (${privateBuildings.length})'),
                _buildMainTabChip(1, '📐 STRATEGIC CONSTRUCTION PLANNER'),
                _buildMainTabChip(2, '🌐 GLOBAL BLUEPRINT CATALOG (${catalog.length > 0 ? catalog.length : 8})'),
              ],
            ),
          ),
          SizedBox(height: context.spacingTopic),

          // Tab Content
          if (_activeTab == 0)
            _buildEstatesTab(
              context,
              buildings: buildings,
              privateBuildings: privateBuildings,
              publicBuildings: publicBuildings,
              civicBuildings: civicBuildings,
              shares: shares,
              dividends: dividends,
              catalog: catalog,
              totalSlots: totalSlots,
              civicReserved: civicReservedSlots,
              usedPrivate: usedPrivateSlots,
              usedCivic: usedCivicSlots,
              population: population,
              viewerId: viewerId,
            )
          else if (_activeTab == 1)
            _buildPlannerTab(
              context,
              catalog: catalog,
              availablePrivateSlots: availablePrivateSlots,
              cityId: cityId,
            )
          else
            _buildCatalogTab(
              context,
              catalog: catalog,
              publicBuildings: publicBuildings,
              shares: shares,
            ),
        ],
      ),
    );
  }

  Widget _buildMainTabChip(int tabIndex, String label) {
    final isSelected = _activeTab == tabIndex;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? context.primaryColor : context.inkColor,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            EarthAudioEngine.instance.playClick();
            setState(() => _activeTab = tabIndex);
          }
        },
      ),
    );
  }

  // ==================== TAB 1: MY DISTRICT ESTATES ====================
  Widget _buildEstatesTab(
    BuildContext context, {
    required List<Map<String, dynamic>> buildings,
    required List<Map<String, dynamic>> privateBuildings,
    required List<Map<String, dynamic>> publicBuildings,
    required List<Map<String, dynamic>> civicBuildings,
    required List<Map<String, dynamic>> shares,
    required List<Map<String, dynamic>> dividends,
    required List<dynamic> catalog,
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
    required String? viewerId,
  }) {
    final filteredBuildings = _selectedCategory == 'all'
        ? buildings.where((b) => b['status'] != 'closed').toList()
        : buildings.where((b) {
            if (b['status'] == 'closed') return false;
            final cat = b['category']?.toString() ?? '';
            final oClass = b['ownership_class']?.toString() ?? b['ownership_type']?.toString() ?? '';
            if (_selectedCategory == 'civic') return oClass == 'civic' || oClass == 'municipal' || oClass == 'public_investment';
            if (_selectedCategory == 'commercial') return cat == 'commercial';
            if (_selectedCategory == 'energy') return cat == 'energy';
            if (_selectedCategory == 'manufacturing') return cat == 'manufacturing' || cat == 'industrial';
            if (_selectedCategory == 'compute') return cat == 'compute' || cat == 'high_tech';
            if (_selectedCategory == 'food') return cat == 'food';
            if (_selectedCategory == 'medical') return cat == 'medical';
            if (_selectedCategory == 'orbital') return cat == 'orbital';
            return true;
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // District Land Zoning Visualizer
        _buildDistrictZoningVisualizer(
          context,
          totalSlots: totalSlots,
          civicReserved: civicReserved,
          usedPrivate: usedPrivate,
          usedCivic: usedCivic,
          population: population,
        ),
        SizedBox(height: context.spacingControl),

        // Sector Filter Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in [
                {'id': 'all', 'label': 'ALL DISTRICT (${buildings.where((b) => b['status'] != 'closed').length})'},
                {'id': 'commercial', 'label': '🛍️ COMMERCIAL'},
                {'id': 'energy', 'label': '⚡ ENERGY'},
                {'id': 'food', 'label': '🌾 FOOD & AGRO'},
                {'id': 'manufacturing', 'label': '🏭 MANUFACTURING'},
                {'id': 'compute', 'label': '💻 DATA & COMPUTE'},
                {'id': 'medical', 'label': '🏥 HEALTHCARE'},
                {'id': 'civic', 'label': '🏛️ CIVIC & PUBLIC'},
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(filter['label']!),
                    selected: _selectedCategory == filter['id'],
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = filter['id']!);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: context.spacingTopic),

        // Active Buildings List
        if (filteredBuildings.isEmpty)
          const EarthEmptyState(
            message: 'No active facilities in this category. Construct blueprints to expand your district footprint.',
            icon: Icons.location_city_outlined,
          )
        else
          Column(
            children: filteredBuildings
                .map((b) => _buildBuildingCard(context, b, viewerId, catalog))
                .toList(),
          ),

        SizedBox(height: context.spacingTopic),

        // Civic Dividends Widget
        _buildCivicAndShareMarketSection(context, publicBuildings, shares, dividends),
      ],
    );
  }

  // ==================== TAB 2: STRATEGIC CONSTRUCTION PLANNER ====================
  Widget _buildPlannerTab(
    BuildContext context, {
    required List<dynamic> catalog,
    required int availablePrivateSlots,
    required String cityId,
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

    final hasEnoughSlots = availablePrivateSlots >= footprint;

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
              Text('STRATEGIC CONSTRUCTION & ROI PLANNER', style: context.topicTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select and compare physical building archetypes before allocating district plots and capital. Review payback velocity, resource sensitivity, and maintenance risks.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),

          // Blueprint Selection Grid / Chips
          Text('SELECT ARCHETYPE FOR STRATEGIC FEASIBILITY ANALYSIS:', style: context.captionStyle),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: blueprints.map((b) {
                final bType = b['type']?.toString() ?? '';
                final bName = b['name']?.toString() ?? bType;
                final isSel = _plannerSelectedBlueprint == bType;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(bName),
                    selected: isSel,
                    onSelected: (val) {
                      if (val) {
                        EarthAudioEngine.instance.playClick();
                        setState(() => _plannerSelectedBlueprint = bType);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
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
                      label: '$footprint DISTRICT SLOT${footprint > 1 ? 'S' : ''}',
                      variant: EarthBadgeVariant.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Primary Purpose: $purpose', style: context.widgetFooterStyle),
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

                // Cost & Zoning Fit
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Capital Required: ${formatWholeNumber(creditCost)} CRD + $materialCost Materials',
                      style: context.bodyStyle.copyWith(fontWeight: FontWeight.bold),
                    ),
                    EarthBadge(
                      label: hasEnoughSlots ? 'ZONING FIT: SUFFICIENT' : 'ZONING FIT: INSUFFICIENT PLOTS',
                      variant: hasEnoughSlots ? EarthBadgeVariant.success : EarthBadgeVariant.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Direct Build Action
                EarthButton(
                  label: 'COMMENCE CONSTRUCTION ON PLOT',
                  icon: Icons.domain_add_outlined,
                  variant: EarthButtonVariant.primary,
                  onPressed: widget.busy || !hasEnoughSlots
                      ? null
                      : () async {
                          EarthAudioEngine.instance.playClick();
                          await widget.action(() => const EarthApi().purchaseBuilding(
                                buildingType: _plannerSelectedBlueprint,
                                name: name,
                                cityId: cityId,
                              ));
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 3: GLOBAL BLUEPRINT CATALOG & TECH TREES ====================
  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
    required List<Map<String, dynamic>> publicBuildings,
    required List<Map<String, dynamic>> shares,
  }) {
    final list = catalog.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusControl),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EARTH AUTHORITATIVE BLUEPRINT SPECIFICATIONS', style: context.topicTitleStyle),
              const SizedBox(height: 4),
              Text(
                'The global EARTH catalog defines all architectural archetypes, multi-tier engineering trees, resource flows, and civic utility rights across the planetary quadrant network.',
                style: context.widgetFooterStyle,
              ),
            ],
          ),
        ),
        SizedBox(height: context.spacingControl),

        // Catalog List
        Column(
          children: list.map((item) {
            final name = item['name']?.toString() ?? 'Blueprint';
            final type = (item['type']?.toString() ?? '').toUpperCase();
            final category = (item['category']?.toString() ?? 'commercial').toUpperCase();
            final footprint = asIntOr(item['slotFootprint'], 1);
            final creditCost = asIntOr(item['baseCreditCost'], 8500);
            final matCost = asIntOr(item['baseMaterialCost'], 120);
            final purpose = item['primaryEconomicPurpose']?.toString() ?? 'Economic Production';
            final desc = item['description']?.toString() ?? '';
            final civicBenefit = item['civicBenefit']?.toString();
            final rawTiers = item['tiers'] as List?;
            final tierCount = rawTiers != null ? rawTiers.length : 3;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(name, style: context.widgetTitleStyle),
                          const SizedBox(width: 8),
                          EarthBadge(label: '$footprint SLOT${footprint > 1 ? 'S' : ''}', variant: EarthBadgeVariant.primary),
                          const SizedBox(width: 4),
                          EarthBadge(label: category, variant: EarthBadgeVariant.neutral),
                        ],
                      ),
                      Text('Base Cost: ${formatWholeNumber(creditCost)} CRD + $matCost MAT', style: context.widgetFooterStyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(desc, style: context.bodyStyle),
                  const SizedBox(height: 6),
                  Text('Economic Purpose: $purpose · Engineering Upgrades: $tierCount Tiers', style: context.widgetFooterStyle),
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
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ==================== REUSABLE ZONING HUD ====================
  Widget _buildDistrictZoningVisualizer(
    BuildContext context, {
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
  }) {
    final freePrivate = (totalSlots - civicReserved) - usedPrivate;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.map_outlined, color: context.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text('CITY DISTRICT LAND ZONING & FOOTPRINT MAP', style: context.widgetTitleStyle),
                ],
              ),
              Text(
                'Population: $population Citizen${population == 1 ? '' : 's'} · Formula: 8 + ⌊Pop/5⌋',
                style: context.widgetFooterStyle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < usedPrivate; i++)
                _buildSlotBlock(context, label: 'PVT', color: context.primaryColor, tooltip: 'Private Commercial/Industrial Plot'),
              for (int i = 0; i < freePrivate; i++)
                _buildSlotBlock(context, label: 'FREE', color: context.successColor, tooltip: 'Available Private Construction Plot', isDashed: true),
              for (int i = 0; i < usedCivic; i++)
                _buildSlotBlock(context, label: 'CIVIC', color: context.secondaryColor, tooltip: 'Constructed Civic Megaproject'),
              for (int i = 0; i < (civicReserved - usedCivic); i++)
                _buildSlotBlock(context, label: 'RSVD', color: context.warningColor, tooltip: '30% Mandatory Civic Quota Reserve', isDashed: true),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _buildLegendItem(context, 'Private Occupied ($usedPrivate)', context.primaryColor),
              _buildLegendItem(context, 'Private Buildable ($freePrivate)', context.successColor),
              _buildLegendItem(context, 'Civic Active ($usedCivic)', context.secondaryColor),
              _buildLegendItem(context, '30% Civic Reserve (${civicReserved - usedCivic})', context.warningColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlotBlock(
    BuildContext context, {
    required String label,
    required Color color,
    required String tooltip,
    bool isDashed = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 52,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDashed ? .12 : .25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: isDashed ? .6 : 1.0),
            width: isDashed ? 1.2 : 1.6,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: context.captionStyle.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: context.widgetFooterStyle),
      ],
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
    final ownershipClass = b['ownership_class']?.toString() ?? b['ownership_type']?.toString() ?? 'private';
    final isOwner = b['owner_id']?.toString() == viewerId;
    final isPublic = ownershipClass == 'public_investment';
    final isCivic = ownershipClass == 'civic' || ownershipClass == 'municipal';

    final baseRev = asDoubleOr(b['base_revenue_crd'], 0);
    final resOutType = b['resource_output_type']?.toString();
    final resOutAmt = asDoubleOr(b['resource_output_amount'], 0);
    final opCost = asDoubleOr(b['daily_operating_credits'], 0);

    final uEnergy = asDoubleOr(b['upkeep_energy'], 0);
    final uFood = asDoubleOr(b['upkeep_food'], 0);
    final uMat = asDoubleOr(b['upkeep_materials'], 0);
    final uComp = asDoubleOr(b['upkeep_components'], 0);
    final uDat = asDoubleOr(b['upkeep_compute'], 0);

    String condStatus = '100% OPTIMAL';
    Color condColor = context.successColor;
    if (condition < 20) {
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
                    Row(
                      children: [
                        Text('$name', style: context.widgetTitleStyle),
                        const SizedBox(width: 8),
                        EarthBadge(label: '$footprint SLOT${footprint > 1 ? 'S' : ''}', variant: EarthBadgeVariant.neutral),
                        const SizedBox(width: 4),
                        EarthBadge(label: 'TIER $tier', variant: EarthBadgeVariant.primary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$type · District Blueprint · Condition: ${condition.toStringAsFixed(0)}% ($condStatus)',
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
                            : 'PRIVATE ESTATE',
                    variant: isCivic
                        ? EarthBadgeVariant.primary
                        : isPublic
                            ? EarthBadgeVariant.secondary
                            : EarthBadgeVariant.success,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: condColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${condition.toStringAsFixed(0)}% HEALTH',
                      style: context.captionStyle.copyWith(
                        color: condColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
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
                          if (baseRev > 0) _buildPill(context, '+${formatWholeNumber(baseRev)} CRD', context.successColor),
                          if (resOutAmt > 0 && resOutType != null)
                            _buildPill(context, '+${resOutAmt.toStringAsFixed(1)} ${resOutType.toUpperCase()}', context.successColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Policies & Actions
          if (isOwner) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('OPERATING POLICY:', style: context.captionStyle.copyWith(fontSize: 10)),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final p in [
                      {'id': 'balanced', 'label': 'Balanced (1.0x)'},
                      {'id': 'high_output', 'label': 'High Out (1.25x)'},
                      {'id': 'eco_reserve', 'label': 'Eco (0.75x)'},
                      {'id': 'overclock', 'label': 'Overclock (1.5x)'},
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
                                }
                              },
                      ),
                  ],
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
                          },
                  ),
                EarthButton(
                  label: 'UPGRADE TREE (TIER ${tier + 1})',
                  icon: Icons.account_tree_outlined,
                  variant: EarthButtonVariant.primary,
                  onPressed: widget.busy
                      ? null
                      : () {
                          EarthAudioEngine.instance.playClick();
                          showBuildingDetailUpgradeDialog(context, widget.action, b, catalog);
                        },
                ),
                EarthButton(
                  label: 'DEMOLISH / RECYCLE',
                  icon: Icons.delete_outline,
                  variant: EarthButtonVariant.danger,
                  onPressed: widget.busy
                      ? null
                      : () {
                          EarthAudioEngine.instance.playClick();
                          showDemolishConfirmDialog(context, widget.action, b);
                        },
                ),
              ],
            ),
          ],
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
              Text('CIVIC DIVIDENDS & PUBLIC MEGAPROJECT SHARES', style: context.topicTitleStyle),
              EarthBadge(label: '70/30 UBI + PARTICIPATION', variant: EarthBadgeVariant.secondary),
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
