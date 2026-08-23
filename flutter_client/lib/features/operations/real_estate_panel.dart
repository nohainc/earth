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
    final laborPool = widget.state.municipalLabor.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final catalog = widget.state.buildingCatalog;
    final cityId = widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final viewerId = widget.state.human['id']?.toString();

    final privateBuildings = buildings.where((b) => b['ownership_type'] == 'private' && b['owner_id'] == viewerId).toList();
    final municipalBuildings = buildings.where((b) => b['ownership_type'] == 'municipal').toList();

    final totalDailyRevenue = privateBuildings.fold<double>(
      0,
      (sum, b) => sum + asDoubleOr(b['base_revenue_crd'], 0),
    );

    final activePooledCount = laborPool.where((m) => m['status'] == 'active').length;
    final totalAccumulatedWages = laborPool.fold<double>(
      0,
      (sum, m) => sum + asDoubleOr(m['accumulated_wages_crd'], 0),
    );

    final filteredBuildings = _selectedCategory == 'all'
        ? buildings
        : buildings.where((b) {
            final type = b['building_type']?.toString() ?? '';
            final ownership = b['ownership_type']?.toString() ?? '';
            if (_selectedCategory == 'municipal') return ownership == 'municipal';
            if (_selectedCategory == 'commercial') {
              return ['restaurant', 'retail-store', 'commercial-mall', 'holo-entertainment'].contains(type);
            }
            if (_selectedCategory == 'industrial') {
              return ['fabrication-plant', 'chemical-foundry', 'protein-refinery', 'quantum-fab'].contains(type);
            }
            if (_selectedCategory == 'high_tech') {
              return ['server-farm', 'corporate-lab', 'orbital-observatory'].contains(type);
            }
            return true;
          }).toList();

    return EarthSection(
      title: 'URBAN REAL ESTATE & MUNICIPAL DISTRICT',
      showSurface: false,
      infoBulletPoints: const [
        'Urban Facilities & Real Estate: Physical commercial, industrial, and high-tech structures situated in your city.',
        'Infrastructure Tiers: Upgrading physical buildings expands staff capacity slots and amplifies daily commercial returns.',
        'Resource Upkeep: Facilities consume small daily resource buffers (Energy, Food, Materials) to maintain peak operational output.',
        'Municipal Megaprojects: Public structures (Central Power Grids, Transit Hubs, Hospitals) constructed by City Referendum providing civic benefits and shared work shifts.',
        'Municipal Labor Pool: Dispatch your idle machines and service robots to public works to earn steady municipal payroll funded by the City Treasury.',
      ],
      trailing: EarthButton(
        label: 'ACQUIRE REAL ESTATE',
        icon: Icons.add_business_outlined,
        variant: EarthButtonVariant.primary,
        onPressed: widget.busy
            ? null
            : () {
                EarthAudioEngine.instance.playClick();
                showBuildingAcquisitionDialog(context, widget.action, catalog, cityId);
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'PROPERTIES OWNED',
                value: '${privateBuildings.length} PRIVATE',
                icon: Icons.store_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'DAILY FACILITY YIELD',
                value: '+${formatWholeNumber(totalDailyRevenue)} CRD',
                icon: Icons.trending_up_outlined,
                accentColor: context.successColor,
              ),
              EarthMetricTile(
                label: 'CIVIC LABOR DISPATCH',
                value: '$activePooledCount ROBOTS POOLED',
                icon: Icons.precision_manufacturing_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'MUNICIPAL PAYROLL EARNED',
                value: '${formatWholeNumber(totalAccumulatedWages)} CRD',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: context.warningColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),

          // Category filter bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in [
                  {'id': 'all', 'label': 'ALL DISTRICT (${buildings.length})'},
                  {'id': 'commercial', 'label': '🛍️ COMMERCIAL'},
                  {'id': 'industrial', 'label': '🏭 INDUSTRIAL'},
                  {'id': 'high_tech', 'label': '📡 HIGH-TECH'},
                  {'id': 'municipal', 'label': '🏛️ MUNICIPAL MEGAPROJECTS (${municipalBuildings.length})'},
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

          if (buildings.isEmpty)
            const EarthEmptyState(
              message: 'No registered buildings in this municipal district.',
              icon: Icons.location_city_outlined,
            )
          else
            Column(
              children: filteredBuildings.map((b) {
                final id = b['id']?.toString() ?? '';
                final name = b['name']?.toString() ?? 'Facility';
                final type = (b['building_type']?.toString() ?? 'building').toUpperCase();
                final tier = asIntOr(b['tier'], 1);
                final cond = asIntOr(b['condition'], 100);
                final maxSlots = asIntOr(b['max_staff_slots'], 4);
                final activeStaff = asIntOr(b['active_staff_count'], 0);
                final baseRev = asDoubleOr(b['base_revenue_crd'], 0);
                final ownership = b['ownership_type']?.toString() ?? 'private';
                final isMunicipal = ownership == 'municipal';
                final isOwner = b['owner_id']?.toString() == viewerId;

                final uEnergy = asDoubleOr(b['upkeep_energy'], 0);
                final uFood = asDoubleOr(b['upkeep_food'], 0);
                final uMat = asDoubleOr(b['upkeep_materials'], 0);
                final uComp = asDoubleOr(b['upkeep_components'], 0);
                final uDat = asDoubleOr(b['upkeep_compute'], 0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.all(context.cardPadding),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    border: Border.all(
                      color: isMunicipal
                          ? context.secondaryColor.withValues(alpha: .35)
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
                                Text('$name ($type)', style: context.widgetTitleStyle),
                                const SizedBox(height: 2),
                                Text(
                                  'Infrastructure Tier $tier · Capacity: $activeStaff / $maxSlots Staff Slots',
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
                                label: isMunicipal ? 'MUNICIPAL PUBLIC' : 'PRIVATE ESTATE',
                                variant: isMunicipal ? EarthBadgeVariant.primary : EarthBadgeVariant.success,
                              ),
                              const SizedBox(height: 4),
                              Text('$cond% COND',
                                  style: context.captionStyle.copyWith(
                                    color: cond > 75 ? context.successColor : context.warningColor,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Upkeep & Yield row
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (baseRev > 0)
                            EarthBadge(
                              label: 'YIELD: +${formatWholeNumber(baseRev)} CRD/day',
                              variant: EarthBadgeVariant.success,
                            ),
                          if (uEnergy > 0)
                            EarthBadge(label: 'UPKEEP: ${uEnergy.toStringAsFixed(1)} NRG', variant: EarthBadgeVariant.warning),
                          if (uFood > 0)
                            EarthBadge(label: 'UPKEEP: ${uFood.toStringAsFixed(1)} FOOD', variant: EarthBadgeVariant.warning),
                          if (uMat > 0)
                            EarthBadge(label: 'UPKEEP: ${uMat.toStringAsFixed(1)} MAT', variant: EarthBadgeVariant.warning),
                          if (uComp > 0)
                            EarthBadge(label: 'UPKEEP: ${uComp.toStringAsFixed(1)} COMP', variant: EarthBadgeVariant.warning),
                          if (uDat > 0)
                            EarthBadge(label: 'UPKEEP: ${uDat.toStringAsFixed(1)} DAT', variant: EarthBadgeVariant.warning),
                        ],
                      ),
                      if (isOwner) ...[
                        SizedBox(height: context.spacingControl),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            EarthButton(
                              label: 'UPGRADE TO TIER ${tier + 1}',
                              icon: Icons.arrow_upward_outlined,
                              variant: EarthButtonVariant.primary,
                              onPressed: widget.busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      showBuildingUpgradeDialog(context, widget.action, b);
                                    },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),

          SizedBox(height: context.spacingTopic),
          // Municipal Labor Pool Section
          Container(
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.primaryColor.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.primaryColor.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('MUNICIPAL SHARED LABOR POOL', style: context.topicTitleStyle),
                    EarthButton(
                      label: 'DISPATCH ROBOT TO CITY',
                      icon: Icons.send_outlined,
                      variant: EarthButtonVariant.primary,
                      onPressed: widget.busy
                          ? null
                          : () {
                              EarthAudioEngine.instance.playClick();
                              showMunicipalLaborDispatchDialog(context, widget.state, widget.action);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Your machines and service robots registered to the municipal labor pool receive automated 4-hour and 8-hour rotating shifts across city public facilities, earning direct daily payroll transfers from the City Treasury.',
                  style: context.widgetFooterStyle,
                ),
                SizedBox(height: context.spacingControl),
                if (laborPool.isEmpty)
                  const EarthEmptyState(
                    message: 'No robots currently dispatched to the Municipal Labor Pool.',
                    icon: Icons.precision_manufacturing_outlined,
                  )
                else
                  Column(
                    children: laborPool.map((item) {
                      final machineId = item['machine_id']?.toString() ?? '';
                      final machineName = item['machine_name']?.toString() ?? machineId;
                      final mType = (item['machine_type']?.toString() ?? 'rig').toUpperCase();
                      final wages = asDoubleOr(item['accumulated_wages_crd'], 0);
                      final status = item['status']?.toString() ?? 'active';
                      final isActive = status == 'active';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                  Text('$machineName ($mType)', style: context.widgetTitleStyle),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Status: ${status.toUpperCase()} · Accumulated Payroll: +${formatWholeNumber(wages)} CRD',
                                    style: context.widgetFooterStyle,
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              EarthButton(
                                label: 'WITHDRAW',
                                variant: EarthButtonVariant.danger,
                                onPressed: widget.busy
                                    ? null
                                    : () async {
                                        EarthAudioEngine.instance.playClick();
                                        await widget.action(() => const EarthApi().withdrawMunicipalLabor(machineId: machineId));
                                      },
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
