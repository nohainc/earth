import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import 'real_estate_dialogs.dart';

class RealEstateDistrictPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const RealEstateDistrictPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<RealEstateDistrictPanel> createState() => _RealEstateDistrictPanelState();
}

class _RealEstateDistrictPanelState extends State<RealEstateDistrictPanel> {
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    final buildings = widget.state.buildings.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final shares = widget.state.investmentShares.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final dividends = widget.state.civicDividends.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final catalog = widget.state.buildingCatalog;
    final zoning = widget.state.districtZoning;
    final cityId = widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final viewerId = widget.state.human['id']?.toString();

    // Calculate zoning and slot numbers
    final totalSlots = asIntOr(zoning['totalSlots'], 10);
    final civicReservedSlots = asIntOr(zoning['civicReservedSlots'], 3);
    final usedPrivateSlots = asIntOr(zoning['usedPrivateSlots'], 0);
    final usedCivicSlots = asIntOr(zoning['usedCivicSlots'], 0);
    final availablePrivateSlots = asIntOr(zoning['availablePrivateSlots'], 7);
    final population = asIntOr(zoning['population'], 12);

    final privateBuildings = buildings.where((b) => b['owner_id'] == viewerId && b['status'] != 'closed').toList();
    final publicBuildings = buildings.where((b) => b['ownership_class'] == 'public_investment' || b['ownership_type'] == 'public_investment').toList();
    final civicBuildings = buildings.where((b) => b['ownership_class'] == 'civic' || b['ownership_type'] == 'municipal').toList();

    // Total daily private yields & upkeep
    final totalDailyPrivateYield = privateBuildings.fold<double>(
      0,
      (sum, b) => sum + asDoubleOr(b['base_revenue_crd'], 0),
    );
    final totalDailyOperatingCost = privateBuildings.fold<double>(
      0,
      (sum, b) => sum + asDoubleOr(b['daily_operating_credits'], 0),
    );

    final mySharesCount = shares.fold<int>(0, (sum, s) => sum + asIntOr(s['shares_owned'], 0));
    final myTotalInvested = shares.fold<double>(0, (sum, s) => sum + asDoubleOr(s['invested_credits'], 0));

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
            return true;
          }).toList();

    return EarthSection(
      title: 'URBAN DISTRICT & REAL ESTATE INFRASTRUCTURE',
      showSurface: false,
      infoBulletPoints: const [
        'Self-Contained Real Estate: Every building is an autonomous economic unit managing its own footprint, upkeep, condition, and yields.',
        'Dynamic District Zoning: Total buildable slots scale with city population (8 + floor(Pop/5)) with a 30% civic development reserve.',
        'Operating Policies: Switch buildings between Balanced, High Output, Eco Reserve, and Overclock modes.',
        'Condition & Wear: Facilities degrade daily; degraded condition cuts output efficiency by up to 60%. Use Components to repair.',
        'Civic Dividends & Public Shares: Invest in civic megaprojects for pro-rata dividend yields, and earn 70/30 UBI from civic surpluses.',
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
                label: 'PRIVATE ESTATES',
                value: '${privateBuildings.length} SITES (${privateBuildings.fold<int>(0, (sum, b) => sum + asIntOr(b['slot_footprint'], 1))} SLOTS)',
                icon: Icons.storefront_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'NET DAILY PRIVATE YIELD',
                value: '+${formatWholeNumber(totalDailyPrivateYield - totalDailyOperatingCost)} CRD',
                icon: Icons.trending_up_outlined,
                accentColor: context.successColor,
              ),
              EarthMetricTile(
                label: 'PUBLIC MEGAPROJECT SHARES',
                value: '$mySharesCount SHARES (${formatWholeNumber(myTotalInvested)} CRD)',
                icon: Icons.pie_chart_outline,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'DISTRICT ZONING CAPACITY',
                value: '$availablePrivateSlots / ${totalSlots - civicReservedSlots} FREE PLOTS',
                icon: Icons.grid_view_outlined,
                accentColor: availablePrivateSlots > 0 ? context.warningColor : context.dangerColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),

          // Visual District Zoning Grid HUD
          _buildDistrictZoningVisualizer(
            context,
            totalSlots: totalSlots,
            civicReserved: civicReservedSlots,
            usedPrivate: usedPrivateSlots,
            usedCivic: usedCivicSlots,
            population: population,
          ),
          SizedBox(height: context.spacingControl),

          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in [
                  {'id': 'all', 'label': 'ALL BUILDINGS (${buildings.where((b) => b['status'] != 'closed').length})'},
                  {'id': 'commercial', 'label': '🛍️ COMMERCIAL'},
                  {'id': 'energy', 'label': '⚡ ENERGY & UTILITIES'},
                  {'id': 'food', 'label': '🌾 FOOD & AGRO'},
                  {'id': 'manufacturing', 'label': '🏭 MANUFACTURING'},
                  {'id': 'compute', 'label': '💻 DATA & COMPUTE'},
                  {'id': 'civic', 'label': '🏛️ CIVIC & PUBLIC (${civicBuildings.length + publicBuildings.length})'},
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(filter['label']!),
                      selected: _selectedCategory == filter['id'],
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = filter['id']!;
                          });
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: context.spacingTopic),

          // Buildings Cards List
          if (filteredBuildings.isEmpty)
            const EarthEmptyState(
              message: 'No active facilities in this category. Construct blueprints to expand your district footprint.',
              icon: Icons.location_city_outlined,
            )
          else
            Column(
              children: filteredBuildings.map((b) => _buildBuildingCard(context, b, viewerId)).toList(),
            ),

          SizedBox(height: context.spacingTopic),

          // Public Crowdfunding & Civic Dividends Section
          _buildCivicAndShareMarketSection(context, publicBuildings, shares, dividends),
        ],
      ),
    );
  }

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
          // Slot Block Strip
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Used Private Slots
              for (int i = 0; i < usedPrivate; i++)
                _buildSlotBlock(
                  context,
                  label: 'PVT',
                  color: context.primaryColor,
                  tooltip: 'Private Commercial/Industrial Plot',
                ),
              // Available Private Slots
              for (int i = 0; i < freePrivate; i++)
                _buildSlotBlock(
                  context,
                  label: 'FREE',
                  color: context.successColor,
                  tooltip: 'Available Private Construction Plot',
                  isDashed: true,
                ),
              // Used Civic Slots
              for (int i = 0; i < usedCivic; i++)
                _buildSlotBlock(
                  context,
                  label: 'CIVIC',
                  color: context.secondaryColor,
                  tooltip: 'Constructed Civic / Public Megaproject',
                ),
              // Reserved Civic Slots
              for (int i = 0; i < (civicReserved - usedCivic); i++)
                _buildSlotBlock(
                  context,
                  label: 'RSVD',
                  color: context.warningColor,
                  tooltip: '30% Mandatory Civic Quota Reserve',
                  isDashed: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Legend Row
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

  Widget _buildBuildingCard(BuildContext context, Map<String, dynamic> b, String? viewerId) {
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

    // Condition Efficiency Status
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
          // Header Row
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
                        EarthBadge(
                          label: '$footprint SLOT${footprint > 1 ? 'S' : ''}',
                          variant: EarthBadgeVariant.neutral,
                        ),
                        const SizedBox(width: 4),
                        EarthBadge(
                          label: 'TIER $tier',
                          variant: EarthBadgeVariant.primary,
                        ),
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

          // Resource Drains & Output Flow HUD
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.subtleBorderColor.withValues(alpha: .5)),
            ),
            child: Row(
              children: [
                // Input Drains Column
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
                          if (opCost > 0)
                            _buildPill(context, '-${formatWholeNumber(opCost)} CRD', context.warningColor),
                          if (uEnergy > 0)
                            _buildPill(context, '-${uEnergy.toStringAsFixed(1)} NRG', context.warningColor),
                          if (uFood > 0)
                            _buildPill(context, '-${uFood.toStringAsFixed(1)} FOOD', context.warningColor),
                          if (uMat > 0)
                            _buildPill(context, '-${uMat.toStringAsFixed(1)} MAT', context.warningColor),
                          if (uComp > 0)
                            _buildPill(context, '-${uComp.toStringAsFixed(1)} COMP', context.warningColor),
                          if (uDat > 0)
                            _buildPill(context, '-${uDat.toStringAsFixed(1)} DAT', context.warningColor),
                          if (opCost == 0 && uEnergy == 0 && uFood == 0 && uMat == 0 && uComp == 0 && uDat == 0)
                            _buildPill(context, 'ZERO UPKEEP', context.inkColor.withValues(alpha: .5)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_outlined, color: context.primaryColor, size: 18),
                const SizedBox(width: 12),
                // Output Yield Column
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
                          if (baseRev > 0)
                            _buildPill(context, '+${formatWholeNumber(baseRev)} CRD', context.successColor),
                          if (resOutAmt > 0 && resOutType != null)
                            _buildPill(
                              context,
                              '+${resOutAmt.toStringAsFixed(1)} ${resOutType.toUpperCase()}',
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

          // Operating Policy & Controls
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

            // Action Buttons
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
                  label: 'UPGRADE (TIER ${tier + 1})',
                  icon: Icons.arrow_upward_outlined,
                  variant: EarthButtonVariant.primary,
                  onPressed: widget.busy
                      ? null
                      : () {
                          EarthAudioEngine.instance.playClick();
                          showBuildingUpgradeDialog(context, widget.action, b);
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
              EarthBadge(
                label: '70/30 UBI + PARTICIPATION',
                variant: EarthBadgeVariant.secondary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Civic and municipal facilities distribute 100% of their net operating surplus to registered city residents (70% as equal Base UBI, and 30% weighted by citizen participation). Public megaprojects offer fractional investment shares providing direct daily dividend yields.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),

          // Public Megaprojects Share Offerings
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

          // Recent Dividend Payouts
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
                          EarthBadge(
                            label: 'TOTAL SURPLUS: +${formatWholeNumber(totalPool)} CRD',
                            variant: EarthBadgeVariant.primary,
                          ),
                          EarthBadge(
                            label: 'BASE UBI: +${formatWholeNumber(ubiPerCitizen)} CRD',
                            variant: EarthBadgeVariant.success,
                          ),
                          if (partBonus > 0)
                            EarthBadge(
                              label: 'BONUS: +${formatWholeNumber(partBonus)} CRD',
                              variant: EarthBadgeVariant.secondary,
                            ),
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
