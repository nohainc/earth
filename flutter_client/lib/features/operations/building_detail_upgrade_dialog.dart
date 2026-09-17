import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

Future<bool?> showBuildingDetailUpgradeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> building,
  List<dynamic> catalog,
) async {
  final bId = building['id']?.toString() ?? '';
  final bName = building['name']?.toString() ?? 'Facility';
  final bType = building['building_type']?.toString() ?? 'restaurant';
  final currentTier = asIntOr(building['tier'], 1);
  final footprint = asIntOr(building['slot_footprint'], 1);

  // Find catalog archetype spec and tier tree.
  final catalogRows = catalog
      .whereType<Map>()
      .where((c) {
        final type = c['building_type'] ?? c['type'];
        return type?.toString() == bType;
      })
      .map((c) => Map<String, dynamic>.from(c))
      .toList();
  final match = catalogRows.firstWhere(
    (c) => c['type'] == bType || c['building_type'] == bType,
    orElse: () => <String, dynamic>{},
  );

  final rawTiers = match['tiers'];
  final researchedCatalogTiers = catalogRows
      .where((row) => row['tier'] != null)
      .map((row) => <String, dynamic>{
            'tier': asIntOr(row['tier'], 1),
            'name': row['name'],
            'upgradeCreditCost': row['cost_credits'] ?? row['baseCreditCost'],
            'upgradeMaterialCost':
                row['cost_materials'] ?? row['baseMaterialCost'],
            'upgradeComponentsCost': row['cost_components'],
            'upgradeComputeCost': row['cost_compute'],
            'construction_days': row['construction_days'],
            'construction_minutes': row['construction_minutes'],
            'dailyCreditRevenue':
                row['output_credits'] ?? row['dailyCreditRevenue'],
            'dailyOperatingCredits':
                row['operating_credits'] ?? row['dailyOperatingCredits'],
            'upkeep_credits': row['upkeep_credits'] ?? row['input_credits'],
            'upkeep_energy': row['upkeep_energy'] ?? row['input_energy'],
            'upkeep_food': row['upkeep_food'] ?? row['input_food'],
            'upkeep_materials':
                row['upkeep_materials'] ?? row['input_materials'],
            'upkeep_components':
                row['upkeep_components'] ?? row['input_components'],
            'upkeep_compute': row['upkeep_compute'] ?? row['input_compute'],
            'operating_credits':
                row['operating_credits'] ?? row['dailyOperatingCredits'],
            'operating_energy': row['operating_energy'],
            'operating_food': row['operating_food'],
            'operating_materials': row['operating_materials'],
            'operating_components': row['operating_components'],
            'operating_compute': row['operating_compute'],
            'unlockedPerks': const <String>[],
            'description': row['description'],
          })
      .toList();

  final List<Map<String, dynamic>> tiers = researchedCatalogTiers.length > 1
      ? researchedCatalogTiers
      : (rawTiers is List && rawTiers.isNotEmpty)
          ? rawTiers
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : rawTiers is List
              ? rawTiers.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
              : <Map<String, dynamic>>[];

  final nextTier = currentTier + 1;
  final quote = await const EarthApi().quoteBuildingUpgrade(buildingId: bId);
  if (quote['eligible'] != true || nextTier > 5) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((quote['blockers'] as List?)?.join(', ') ?? 'Upgrade quote unavailable')),
      );
    }
    return false;
  }

  if (bType == 'private-estate-plot') {
    if (researchedCatalogTiers.length <= 1) {
      tiers.removeWhere((tier) => asIntOr(tier['tier'], 1) > currentTier);
    }
    for (final tier in tiers) {
      tier.remove('requiredCityPopulation');
    }
  }

  final currentTierSpec = tiers.firstWhere(
    (t) => asIntOr(t['tier'], 0) == currentTier,
    orElse: () => <String, dynamic>{},
  );
  final nextTierSpec = tiers.firstWhere(
    (t) => asIntOr(t['tier'], 0) == nextTier,
    orElse: () => <String, dynamic>{},
  );
  final targetCatalog = quote['targetCatalog'];
  if (targetCatalog is Map) {
    nextTierSpec.addAll(Map<String, dynamic>.from(targetCatalog));
  }
  final hasNextTier = nextTierSpec.isNotEmpty && currentTier < 5;

  final upgradeCreditCost = asIntOr(quote['creditCostUnits'], 0);
  final upgradeMaterialCost = asIntOr(nextTierSpec['cost_materials'], 0);
  final upgradeCompCost = asIntOr(nextTierSpec['cost_components'], 0);
  final upgradeComputeCost = asIntOr(nextTierSpec['upgradeComputeCost'], 0);
  final upgradeDays = (asIntOr(quote['constructionMinutes'], 0) / 1440).ceil();
  final reqPop = asIntOr(nextTierSpec['requiredCityPopulation'], 0);

  // Helper to extract resource vector from spec or building
  double getVal(Map<String, dynamic> source, List<String> keys,
      [double fallback = 0]) {
    for (final k in keys) {
      if (source.containsKey(k) && source[k] != null) {
        return asDoubleOr(source[k], fallback);
      }
    }
    return fallback;
  }

  // Current vs Next Upkeep
  final currUpkeepEnergy = getVal(
      currentTierSpec,
      ['upkeep_energy', 'input_energy'],
      asDoubleOr(building['upkeep_energy'], 0));
  final nextUpkeepEnergy = getVal(nextTierSpec, ['upkeep_energy', 'input_energy']);

  final currUpkeepFood = getVal(currentTierSpec, ['upkeep_food', 'input_food'],
      asDoubleOr(building['upkeep_food'], 0));
  final nextUpkeepFood = getVal(nextTierSpec, ['upkeep_food', 'input_food']);

  final currUpkeepMat = getVal(
      currentTierSpec,
      ['upkeep_materials', 'input_materials'],
      asDoubleOr(building['upkeep_materials'], 0));
  final nextUpkeepMat = getVal(nextTierSpec, ['upkeep_materials', 'input_materials']);

  final currUpkeepComp = getVal(
      currentTierSpec,
      ['upkeep_components', 'input_components'],
      asDoubleOr(building['upkeep_components'], 0));
  final nextUpkeepComp = getVal(nextTierSpec, ['upkeep_components', 'input_components']);

  final currUpkeepCompute = getVal(
      currentTierSpec,
      ['upkeep_compute', 'input_compute'],
      asDoubleOr(building['upkeep_compute'], 0));
  final nextUpkeepCompute = getVal(nextTierSpec, ['upkeep_compute', 'input_compute']);

  // Current vs Next Operating Costs
  final currOpCredits = getVal(
      currentTierSpec,
      ['operating_credits', 'daily_operating_credits', 'dailyOperatingCredits'],
      asDoubleOr(building['daily_operating_credits'], 0));
  final nextOpCredits = getVal(
      nextTierSpec,
      ['operating_credits', 'daily_operating_credits', 'dailyOperatingCredits'],
      0);

  final currOpEnergy =
      getVal(currentTierSpec, ['operating_energy', 'operatingCostEnergy'], 0);
  final nextOpEnergy = getVal(nextTierSpec, ['operating_energy', 'operatingCostEnergy']);

  final currOpFood =
      getVal(currentTierSpec, ['operating_food', 'operatingCostFood'], 0);
  final nextOpFood = getVal(nextTierSpec, ['operating_food', 'operatingCostFood']);

  final currOpMat = getVal(
      currentTierSpec, ['operating_materials', 'operatingCostMaterials'], 0);
  final nextOpMat = getVal(nextTierSpec, ['operating_materials', 'operatingCostMaterials']);

  final currOpComp = getVal(
      currentTierSpec, ['operating_components', 'operatingCostComponents'], 0);
  final nextOpComp = getVal(nextTierSpec, ['operating_components', 'operatingCostComponents']);

  final currOpCompute =
      getVal(currentTierSpec, ['operating_compute', 'operatingCostCompute'], 0);
  final nextOpCompute = getVal(nextTierSpec, ['operating_compute', 'operatingCostCompute']);

  if (!context.mounted) return false;
  return await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.arrow_upward_outlined, color: context.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$bName · Upgrade to Tier $nextTier',
              style: context.topicTitleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Facility Status Header
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(context.radiusControl),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'Active Tier: Tier $currentTier · $footprint Space${footprint == 1 ? '' : 's'}',
                        style: context.widgetTitleStyle),
                    const EarthBadge(
                      label: 'OPERATIONAL',
                      variant: EarthBadgeVariant.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (hasNextTier) ...[
                // UPGRADE COST LINE (with time)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(
                        color: context.primaryColor.withValues(alpha: .3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UPGRADE COST', style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined,
                                  size: 14, color: EarthResourceColors.credits),
                              const SizedBox(width: 4),
                              Text(
                                  '${formatWholeNumber(upgradeCreditCost)} CRD',
                                  style: context.bodyStyle
                                      .copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (upgradeMaterialCost > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Icon(
                                    EarthResourceMeta.forCommodity('materials')
                                        .icon,
                                    size: 14,
                                    color: EarthResourceColors.materials),
                                const SizedBox(width: 4),
                                Text('$upgradeMaterialCost Materials',
                                    style: context.widgetFooterStyle),
                              ],
                            ),
                          if (upgradeCompCost > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Icon(
                                    EarthResourceMeta.forCommodity('components')
                                        .icon,
                                    size: 14,
                                    color: EarthResourceColors.components),
                                const SizedBox(width: 4),
                                Text('$upgradeCompCost Components',
                                    style: context.widgetFooterStyle),
                              ],
                            ),
                          if (upgradeComputeCost > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Icon(
                                    EarthResourceMeta.forCommodity('compute')
                                        .icon,
                                    size: 14,
                                    color: EarthResourceColors.compute),
                                const SizedBox(width: 4),
                                Text('$upgradeComputeCost Compute',
                                    style: context.widgetFooterStyle),
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 4),
                              const Icon(Icons.timer_outlined,
                                  size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text('${upgradeDays}d',
                                  style: context.widgetFooterStyle),
                            ],
                          ),
                          if (reqPop > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                Icon(Icons.people_outline,
                                    size: 14, color: context.secondaryColor),
                                const SizedBox(width: 4),
                                Text('Pop >= $reqPop',
                                    style: context.widgetFooterStyle),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // DAILY UPKEEP CHANGES LINE
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DAILY UPKEEP CHANGES', style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (currUpkeepEnergy > 0 || nextUpkeepEnergy > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Energy',
                              icon:
                                  EarthResourceMeta.forCommodity('energy').icon,
                              color: EarthResourceColors.energy,
                              currentVal: currUpkeepEnergy,
                              nextVal: nextUpkeepEnergy,
                              unit: '/day',
                            ),
                          if (currUpkeepFood > 0 || nextUpkeepFood > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Food',
                              icon: EarthResourceMeta.forCommodity('food').icon,
                              color: EarthResourceColors.food,
                              currentVal: currUpkeepFood,
                              nextVal: nextUpkeepFood,
                              unit: '/day',
                            ),
                          if (currUpkeepMat > 0 || nextUpkeepMat > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Materials',
                              icon: EarthResourceMeta.forCommodity('materials')
                                  .icon,
                              color: EarthResourceColors.materials,
                              currentVal: currUpkeepMat,
                              nextVal: nextUpkeepMat,
                              unit: '/day',
                            ),
                          if (currUpkeepComp > 0 || nextUpkeepComp > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Components',
                              icon: EarthResourceMeta.forCommodity('components')
                                  .icon,
                              color: EarthResourceColors.components,
                              currentVal: currUpkeepComp,
                              nextVal: nextUpkeepComp,
                              unit: '/day',
                            ),
                          if (currUpkeepCompute > 0 || nextUpkeepCompute > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Compute',
                              icon: EarthResourceMeta.forCommodity('compute')
                                  .icon,
                              color: EarthResourceColors.compute,
                              currentVal: currUpkeepCompute,
                              nextVal: nextUpkeepCompute,
                              unit: '/day',
                            ),
                          if (currUpkeepEnergy == 0 &&
                              currUpkeepFood == 0 &&
                              currUpkeepMat == 0 &&
                              currUpkeepComp == 0 &&
                              currUpkeepCompute == 0)
                            Text('No daily upkeep required.',
                                style: context.widgetFooterStyle),
                        ],
                      ),
                    ],
                  ),
                ),

                // OPERATING COST CHANGES LINE
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OPERATING COST CHANGES',
                          style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (currOpCredits > 0 || nextOpCredits > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Credits',
                              icon: Icons.account_balance_wallet_outlined,
                              color: EarthResourceColors.credits,
                              currentVal: currOpCredits,
                              nextVal: nextOpCredits,
                              unit: 'CRD/day',
                              isCost: true,
                            ),
                          if (currOpEnergy > 0 || nextOpEnergy > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Energy',
                              icon:
                                  EarthResourceMeta.forCommodity('energy').icon,
                              color: EarthResourceColors.energy,
                              currentVal: currOpEnergy,
                              nextVal: nextOpEnergy,
                              unit: '/day',
                              isCost: true,
                            ),
                          if (currOpFood > 0 || nextOpFood > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Food',
                              icon: EarthResourceMeta.forCommodity('food').icon,
                              color: EarthResourceColors.food,
                              currentVal: currOpFood,
                              nextVal: nextOpFood,
                              unit: '/day',
                              isCost: true,
                            ),
                          if (currOpMat > 0 || nextOpMat > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Materials',
                              icon: EarthResourceMeta.forCommodity('materials')
                                  .icon,
                              color: EarthResourceColors.materials,
                              currentVal: currOpMat,
                              nextVal: nextOpMat,
                              unit: '/day',
                              isCost: true,
                            ),
                          if (currOpComp > 0 || nextOpComp > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Components',
                              icon: EarthResourceMeta.forCommodity('components')
                                  .icon,
                              color: EarthResourceColors.components,
                              currentVal: currOpComp,
                              nextVal: nextOpComp,
                              unit: '/day',
                              isCost: true,
                            ),
                          if (currOpCompute > 0 || nextOpCompute > 0)
                            _buildDeltaResourceItem(
                              context,
                              label: 'Compute',
                              icon: EarthResourceMeta.forCommodity('compute')
                                  .icon,
                              color: EarthResourceColors.compute,
                              currentVal: currOpCompute,
                              nextVal: nextOpCompute,
                              unit: '/day',
                              isCost: true,
                            ),
                          if (currOpCredits == 0 &&
                              currOpEnergy == 0 &&
                              currOpFood == 0 &&
                              currOpMat == 0 &&
                              currOpComp == 0 &&
                              currOpCompute == 0)
                            Text('No operating cost required.',
                                style: context.widgetFooterStyle),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text('This facility is at maximum available tier.',
                        style: context.widgetFooterStyle),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        EarthButton(
          label: 'CLOSE',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        if (hasNextTier)
          EarthButton(
            label: 'COMMENCE TIER $nextTier UPGRADE',
            icon: Icons.arrow_upward_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              EarthAudioEngine.instance.playClick();
              Navigator.of(dialogContext).pop(true);
              await action(
                  () => const EarthApi().upgradeBuilding(buildingId: bId));
            },
          ),
      ],
    ),
  );
}

Widget _buildDeltaResourceItem(
  BuildContext context, {
  required String label,
  required IconData icon,
  required Color color,
  required double currentVal,
  required double nextVal,
  required String unit,
  bool isCost = true,
}) {
  final diff = nextVal - currentVal;
  final diffSign = diff > 0 ? '+' : '';
  final isDiffNegative = diff < 0;

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        '${currentVal.toStringAsFixed(currentVal == currentVal.roundToDouble() ? 0 : 1)} → ${nextVal.toStringAsFixed(nextVal == nextVal.roundToDouble() ? 0 : 1)} $unit',
        style: context.widgetFooterStyle,
      ),
      if (diff != 0) ...[
        const SizedBox(width: 4),
        Text(
          '($diffSign${diff.toStringAsFixed(diff == diff.roundToDouble() ? 0 : 1)})',
          style: context.widgetFooterStyle.copyWith(
            color: isCost
                ? (isDiffNegative ? context.successColor : context.warningColor)
                : (diff > 0 ? context.successColor : context.warningColor),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ],
  );
}
