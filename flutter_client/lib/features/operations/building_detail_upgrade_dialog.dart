import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showBuildingDetailUpgradeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> building,
  List<dynamic> catalog,
) async {
  final bId = building['id']?.toString() ?? '';
  final bName = building['name']?.toString() ?? 'Facility';
  final bType = building['building_type']?.toString() ?? 'restaurant';
  final currentTier = asIntOr(building['tier'], 1);
  final condition = asDoubleOr(building['condition'], 100);
  final footprint = asIntOr(building['slot_footprint'], 1);

  // Find catalog archetype spec and tier tree
  final match = catalog.whereType<Map>().firstWhere(
    (c) => c['type'] == bType,
    orElse: () => <String, dynamic>{},
  );

  final rawTiers = match['tiers'];
  final List<Map<String, dynamic>> tiers = (rawTiers is List && rawTiers.isNotEmpty)
      ? rawTiers.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [
          {
            'tier': 1,
            'name': '$bName (Standard)',
            'upgradeCreditCost': 0,
            'upgradeMaterialCost': 0,
            'dailyCreditRevenue': asDoubleOr(building['resource_output_amount'], 600),
            'dailyOperatingCredits': asDoubleOr(building['daily_operating_credits'], 80),
            'unlockedPerks': ['Autonomous Operations', 'Local District Footprint'],
            'description': 'Base foundational tier (EARTH Open Technology).',
          },
          {
            'tier': 2,
            'name': '$bName (Advanced Tier 2)',
            'upgradeCreditCost': 9500,
            'upgradeMaterialCost': 120,
            'upgradeComponentsCost': 20,
            'dailyCreditRevenue': asDoubleOr(building['resource_output_amount'], 600) * 1.35,
            'dailyOperatingCredits': asDoubleOr(building['daily_operating_credits'], 80) * 1.25,
            'unlockedPerks': ['Expanded Capacity (+35%)', 'Logistics Automation'],
            'requiredCityPopulation': 12,
            'description': 'Upgraded engineering tier with enhanced yield.',
          },
          {
            'tier': 3,
            'name': '$bName (Master Tier 3)',
            'upgradeCreditCost': 24000,
            'upgradeMaterialCost': 280,
            'upgradeComponentsCost': 45,
            'upgradeComputeCost': 30,
            'dailyCreditRevenue': asDoubleOr(building['resource_output_amount'], 600) * 2.10,
            'dailyOperatingCredits': asDoubleOr(building['daily_operating_credits'], 80) * 1.80,
            'unlockedPerks': ['District Franchise Contracts', 'Regional Multiplier (+15%)'],
            'requiredCityPopulation': 25,
            'description': 'Master-tier commercial installation.',
          },
        ];

  final nextTier = currentTier + 1;
  final nextTierSpec = tiers.firstWhere(
    (t) => asIntOr(t['tier'], 0) == nextTier,
    orElse: () => <String, dynamic>{},
  );
  final hasNextTier = nextTierSpec.isNotEmpty && currentTier < 4;

  final upgradeCreditCost = asIntOr(nextTierSpec['upgradeCreditCost'], 4800 * nextTier);
  final upgradeMaterialCost = asIntOr(nextTierSpec['upgradeMaterialCost'], 30 * nextTier);
  final upgradeCompCost = asIntOr(nextTierSpec['upgradeComponentsCost'], 20 * nextTier);
  final upgradeComputeCost = asIntOr(nextTierSpec['upgradeComputeCost'], 0);
  final reqPop = asIntOr(nextTierSpec['requiredCityPopulation'], 0);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.account_tree_outlined, color: context.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$bName · Multi-Tier Upgrade Tree',
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
                    Text('Active Tier: Tier $currentTier · $footprint Slot(s)', style: context.widgetTitleStyle),
                    EarthBadge(
                      label: '${condition.toStringAsFixed(0)}% HEALTH',
                      variant: condition > 75 ? EarthBadgeVariant.success : EarthBadgeVariant.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Visual Upgrade Tree Progression
              Text('MULTI-TIER UPGRADE PROGRESSION', style: context.captionStyle),
              const SizedBox(height: 8),
              Column(
                children: tiers.map((t) {
                  final tNum = asIntOr(t['tier'], 1);
                  final tName = t['name']?.toString() ?? 'Tier $tNum';
                  final tRev = asDoubleOr(t['dailyCreditRevenue'], 0);
                  final tOp = asDoubleOr(t['dailyOperatingCredits'], 0);
                  final perks = (t['unlockedPerks'] as List?)?.map((e) => e.toString()).toList() ?? [];
                  final popPrereq = asIntOr(t['requiredCityPopulation'], 0);
                  final isCompleted = tNum <= currentTier;
                  final isNext = tNum == nextTier;
                  final isLocked = tNum > nextTier;

                  Color nodeColor = isCompleted
                      ? context.successColor
                      : isNext
                          ? context.primaryColor
                          : context.inkColor.withValues(alpha: .3);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? context.successColor.withValues(alpha: .06)
                          : isNext
                              ? context.primaryColor.withValues(alpha: .08)
                              : context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                        color: nodeColor,
                        width: isNext ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isCompleted
                                      ? Icons.check_circle
                                      : isNext
                                          ? Icons.arrow_circle_up
                                          : Icons.lock_outline,
                                  color: nodeColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TIER $tNum: $tName',
                                  style: context.widgetTitleStyle.copyWith(
                                    color: isLocked ? context.inkColor.withValues(alpha: .5) : null,
                                  ),
                                ),
                              ],
                            ),
                            EarthBadge(
                              label: isCompleted
                                  ? 'ACTIVE'
                                  : isNext
                                      ? 'AVAILABLE'
                                      : 'LOCKED',
                              variant: isCompleted
                                  ? EarthBadgeVariant.success
                                  : isNext
                                      ? EarthBadgeVariant.primary
                                      : EarthBadgeVariant.neutral,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (tRev > 0 || tOp > 0)
                          Text(
                            'Yield: +${formatWholeNumber(tRev)} CRD/day · Operating Cost: -${formatWholeNumber(tOp)} CRD/day',
                            style: context.widgetFooterStyle,
                          ),
                        if (perks.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: perks.map((p) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: nodeColor.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('✦ $p', style: TextStyle(fontSize: 10, color: nodeColor)),
                            )).toList(),
                          ),
                        ],
                        if (popPrereq > 0) ...[
                          const SizedBox(height: 4),
                          Text('Requires: City Population $popPrereq+', style: context.captionStyle.copyWith(fontSize: 10)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),

              if (hasNextTier) ...[
                const SizedBox(height: 10),
                // Next Tier Cost Breakdown
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UPGRADE TO TIER $nextTier INVESTMENT', style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text('• ${formatWholeNumber(upgradeCreditCost)} Credits', style: context.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
                          if (upgradeMaterialCost > 0) Text('• $upgradeMaterialCost Materials', style: context.bodyStyle),
                          if (upgradeCompCost > 0) Text('• $upgradeCompCost Components', style: context.bodyStyle),
                          if (upgradeComputeCost > 0) Text('• $upgradeComputeCost Compute', style: context.bodyStyle),
                          if (reqPop > 0) Text('• City Pop >= $reqPop', style: context.bodyStyle),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        EarthButton(
          label: 'CLOSE',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        if (hasNextTier)
          EarthButton(
            label: 'COMMENCE TIER $nextTier UPGRADE',
            icon: Icons.arrow_upward_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              EarthAudioEngine.instance.playClick();
              Navigator.of(dialogContext).pop();
              await action(() => const EarthApi().upgradeBuilding(buildingId: bId));
            },
          ),
      ],
    ),
  );
}
