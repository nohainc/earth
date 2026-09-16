import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showBuildingAcquisitionDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  List<dynamic> buildingCatalog,
  String territoryId,
  int availablePrivateSlots,
) async {
  final catalog = buildingCatalog
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();

  final privateBlueprints =
      catalog.where((b) => b['ownershipClass'] != 'civic').toList();
  if (privateBlueprints.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.panelColor,
        title: const Text('Construction Catalog Unavailable'),
        content: const Text(
            'No authoritative private building blueprints are available for this Territory right now.'),
        actions: [
          EarthButton(
            label: 'CLOSE',
            variant: EarthButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    return;
  }
  String selectedType =
      privateBlueprints.first['type']?.toString() ?? 'restaurant';
  final nameCtrl = TextEditingController(
      text: privateBlueprints.first['name']?.toString() ?? 'Facility');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final currentSpec = privateBlueprints.firstWhere(
          (b) => b['type'] == selectedType,
          orElse: () => privateBlueprints.first,
        );
        final creditCost = asIntOr(currentSpec['baseCreditCost'], 8500);
        final materialCost = asIntOr(currentSpec['baseMaterialCost'], 120);
        final footprint = asIntOr(currentSpec['slotFootprint'], 1);
        final opCost = asDoubleOr(currentSpec['dailyOperatingCredits'], 0);
        final baseRev = asDoubleOr(currentSpec['dailyOutputCredits'], 0);
        final resOutType = currentSpec['dailyOutputResourceType']?.toString();
        final resOutAmt =
            asDoubleOr(currentSpec['dailyOutputResourceAmount'], 0);

        final uEnergy = asDoubleOr(currentSpec['dailyInputEnergy'], 0);
        final uFood = asDoubleOr(currentSpec['dailyInputFood'], 0);
        final uMat = asDoubleOr(currentSpec['dailyInputMaterials'], 0);
        final uComp = asDoubleOr(currentSpec['dailyInputComponents'], 0);
        final uDat = asDoubleOr(currentSpec['dailyInputCompute'], 0);

        final hasEnoughSlots = availablePrivateSlots >= footprint;

        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side:
                BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Row(
            children: [
              Icon(Icons.domain_add_outlined, color: context.primaryColor),
              const SizedBox(width: 8),
              Text('Acquire District Plot & Construct',
                  style: context.topicTitleStyle),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Blueprint Dropdown
                  Text('ARCHITECTURAL BLUEPRINT', style: context.captionStyle),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    dropdownColor: context.panelColor,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(context.radiusControl)),
                    ),
                    items: privateBlueprints.map((b) {
                      final type = b['type']?.toString() ?? '';
                      final name = b['name']?.toString() ?? type;
                      final slots = asIntOr(b['slotFootprint'], 1);
                      return DropdownMenuItem(
                          value: type,
                          child: Text(
                              '$name ($slots Slot${slots > 1 ? 's' : ''})'));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedType = val;
                          final match = privateBlueprints
                              .firstWhere((x) => x['type'] == val);
                          nameCtrl.text =
                              match['name']?.toString() ?? 'Facility';
                        });
                      }
                    },
                  ),
                  SizedBox(height: context.spacingControl),

                  // Facility Name
                  Text('FACILITY NAME', style: context.captionStyle),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(context.radiusControl)),
                    ),
                  ),
                  SizedBox(height: context.spacingControl),

                  // Blueprint Specifications Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius:
                          BorderRadius.circular(context.radiusControl),
                      border: Border.all(color: context.subtleBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentSpec['description']?.toString() ?? '',
                          style: context.widgetFooterStyle,
                        ),
                        const SizedBox(height: 10),
                        // Zoning Footprint & Cost
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                EarthBadge(
                                  label:
                                      '$footprint DISTRICT SLOT${footprint > 1 ? 'S' : ''}',
                                  variant: EarthBadgeVariant.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  hasEnoughSlots
                                      ? '($availablePrivateSlots Free Slots Available)'
                                      : '(Requires $footprint Slots · Only $availablePrivateSlots Free)',
                                  style: context.captionStyle.copyWith(
                                    color: hasEnoughSlots
                                        ? context.successColor
                                        : context.dangerColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Construction Cost: ${formatWholeNumber(creditCost)} C + $materialCost Materials',
                          style: context.widgetTitleStyle
                              .copyWith(color: context.primaryColor),
                        ),
                        const Divider(height: 16),
                        // Daily Inflow / Outflow
                        Text('AUTONOMOUS DAILY OPERATING CYCLE',
                            style: context.captionStyle),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('UPKEEP DRAINS',
                                      style: context.widgetFooterStyle),
                                  const SizedBox(height: 4),
                                  if (opCost > 0)
                                    Text(
                                        '• ${formatWholeNumber(opCost)} C / day',
                                        style: context.bodyStyle),
                                  if (uEnergy > 0)
                                    Text(
                                        '• ${uEnergy.toStringAsFixed(1)} Energy / day',
                                        style: context.bodyStyle),
                                  if (uFood > 0)
                                    Text(
                                        '• ${uFood.toStringAsFixed(1)} Food / day',
                                        style: context.bodyStyle),
                                  if (uMat > 0)
                                    Text(
                                        '• ${uMat.toStringAsFixed(1)} Materials / day',
                                        style: context.bodyStyle),
                                  if (uComp > 0)
                                    Text(
                                        '• ${uComp.toStringAsFixed(1)} Components / day',
                                        style: context.bodyStyle),
                                  if (uDat > 0)
                                    Text(
                                        '• ${uDat.toStringAsFixed(1)} Compute / day',
                                        style: context.bodyStyle),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('OUTPUT YIELDS',
                                      style: context.widgetFooterStyle),
                                  const SizedBox(height: 4),
                                  if (baseRev > 0)
                                    Text(
                                        '+${formatWholeNumber(baseRev)} C / day',
                                        style: context.bodyStyle.copyWith(
                                            color: context.successColor,
                                            fontWeight: FontWeight.bold)),
                                  if (resOutAmt > 0 && resOutType != null)
                                    Text(
                                        '+${resOutAmt.toStringAsFixed(1)} ${resOutType.toUpperCase()} / day',
                                        style: context.bodyStyle.copyWith(
                                            color: context.successColor,
                                            fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            EarthButton(
              label: 'CANCEL',
              variant: EarthButtonVariant.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            EarthButton(
              label: 'COMMENCE CONSTRUCTION',
              icon: Icons.check_circle_outline,
              variant: EarthButtonVariant.primary,
              onPressed: !hasEnoughSlots
                  ? null
                  : () async {
                      EarthAudioEngine.instance.playClick();
                      Navigator.of(dialogContext).pop();
                      await action(() => const EarthApi().purchaseBuilding(
                            buildingType: selectedType,
                            name: nameCtrl.text.trim().isEmpty
                                ? 'Facility'
                                : nameCtrl.text.trim(),
                            territoryId: territoryId,
                          ));
                    },
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showBuildingUpgradeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> building,
) async {
  final id = building['id']?.toString() ?? '';
  final name = building['name']?.toString() ?? 'Facility';
  final currentTier = asIntOr(building['tier'], 1);
  final nextTier = currentTier + 1;
  final outAmt = asDoubleOr(building['resource_output_amount'], 0);
  final outType = building['resource_output_type']?.toString();
  final projectedAmt = (outAmt * 1.30);

  final upgradeCreditCost = (currentTier * 5000 + 4000);
  final upgradeMaterialCost = (currentTier * 40 + 20);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text('Upgrade Facility to Tier $nextTier',
          style: context.topicTitleStyle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Upgrading $name enhances operational efficiency, boosts daily commercial yield by +30%, and fully restores facility health to 100%.',
            style: context.bodyStyle,
          ),
          const SizedBox(height: 12),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Current Tier: $currentTier',
                        style: context.widgetFooterStyle),
                    Text('Upgraded Tier: $nextTier',
                        style: context.widgetFooterStyle
                            .copyWith(color: context.successColor)),
                  ],
                ),
                const SizedBox(height: 6),
                if (outAmt > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'Yield: +${outType == 'credits' || outType == null ? formatWholeNumber(outAmt) : outAmt.toStringAsFixed(1)} ${(outType ?? 'CRD').toUpperCase()}',
                          style: context.widgetFooterStyle),
                      Text(
                          'Projected: +${outType == 'credits' || outType == null ? formatWholeNumber(projectedAmt) : projectedAmt.toStringAsFixed(1)} ${(outType ?? 'CRD').toUpperCase()}',
                          style: context.widgetFooterStyle.copyWith(
                              color: context.successColor,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                const Divider(height: 16),
                Text(
                  'Upgrade Investment: ${formatWholeNumber(upgradeCreditCost)} CRD + $upgradeMaterialCost Materials',
                  style: context.widgetTitleStyle
                      .copyWith(color: context.primaryColor),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        EarthButton(
          label: 'CANCEL',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        EarthButton(
          label: 'EXECUTE UPGRADE',
          icon: Icons.arrow_upward_outlined,
          variant: EarthButtonVariant.primary,
          onPressed: () async {
            EarthAudioEngine.instance.playClick();
            Navigator.of(dialogContext).pop();
            await action(
                () => const EarthApi().upgradeBuilding(buildingId: id));
          },
        ),
      ],
    ),
  );
}

Future<bool?> showDemolishConfirmDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> building,
) async {
  final id = building['id']?.toString() ?? '';
  final name = building['name']?.toString() ?? 'Facility';
  final footprint = asIntOr(building['slot_footprint'], 1);

  return await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.dangerColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: context.dangerColor),
          const SizedBox(width: 8),
          Text('Demolish Facility', style: context.topicTitleStyle),
        ],
      ),
      content: Text(
        'Are you sure you want to demolish $name? Demolition will close the facility, deallocate its $footprint district zoning slot(s) for new construction, and recycle 30% of its structural materials back to your warehouse.',
        style: context.bodyStyle,
      ),
      actions: [
        EarthButton(
          label: 'CANCEL',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        EarthButton(
          label: 'DEMOLISH & RECYCLE',
          icon: Icons.delete_forever_outlined,
          variant: EarthButtonVariant.danger,
          onPressed: () async {
            EarthAudioEngine.instance.playClick();
            Navigator.of(dialogContext).pop(true);
            await action(
                () => const EarthApi().demolishBuilding(buildingId: id));
          },
        ),
      ],
    ),
  );
}
