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
  String cityId,
) async {
  final catalog = buildingCatalog.isNotEmpty
      ? buildingCatalog.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[
          {
            'type': 'restaurant',
            'name': 'Bistro & Molecular Restaurant',
            'category': 'commercial',
            'tier': 1,
            'baseCreditCost': 8500,
            'baseMaterialCost': 120,
            'maxStaffSlots': 4,
            'upkeepEnergy': 0.50,
            'upkeepFood': 0.25,
            'baseDailyRevenueCrd': 450,
            'description': 'Specialized molecular dining establishment that converts energy and biomass into liquid credit revenue.',
          },
          {
            'type': 'retail-store',
            'name': 'Retail Boutique & Department Store',
            'category': 'commercial',
            'tier': 1,
            'baseCreditCost': 9200,
            'baseMaterialCost': 140,
            'maxStaffSlots': 4,
            'upkeepEnergy': 0.40,
            'upkeepComponents': 0.15,
            'baseDailyRevenueCrd': 520,
            'description': 'Consumer goods outlet offering manufactured components and standard tools to city dwellers.',
          },
          {
            'type': 'fabrication-plant',
            'name': 'Automated Fabrication Plant',
            'category': 'industrial',
            'tier': 1,
            'baseCreditCost': 11000,
            'baseMaterialCost': 180,
            'maxStaffSlots': 6,
            'upkeepEnergy': 2.00,
            'upkeepMaterials': 1.50,
            'baseDailyRevenueCrd': 750,
            'description': 'Industrial manufacturing facility engineered to house precision CNC cells and assembly lines.',
          },
          {
            'type': 'server-farm',
            'name': 'Neural Data Center & Server Farm',
            'category': 'high_tech',
            'tier': 1,
            'baseCreditCost': 12500,
            'baseMaterialCost': 190,
            'maxStaffSlots': 6,
            'upkeepEnergy': 3.00,
            'upkeepComponents': 0.20,
            'baseDailyRevenueCrd': 800,
            'description': 'Liquid-cooled data facility providing high-throughput computational telemetry.',
          },
        ];

  final commercialCatalog = catalog.where((b) => b['category'] != 'municipal_megaproject').toList();
  String selectedType = commercialCatalog.first['type']?.toString() ?? 'restaurant';
  final nameCtrl = TextEditingController(text: commercialCatalog.first['name']?.toString() ?? 'Facility');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final currentSpec = commercialCatalog.firstWhere(
          (b) => b['type'] == selectedType,
          orElse: () => commercialCatalog.first,
        );
        final creditCost = asIntOr(currentSpec['baseCreditCost'], 8500);
        final materialCost = asIntOr(currentSpec['baseMaterialCost'], 120);
        final staffSlots = asIntOr(currentSpec['maxStaffSlots'], 4);
        final baseRev = asIntOr(currentSpec['baseDailyRevenueCrd'], 450);

        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text('Acquire Commercial / Industrial Plot', style: context.topicTitleStyle),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('BUILDING ARCHETYPE', style: context.captionStyle),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: context.panelColor,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.radiusControl)),
                    ),
                    items: commercialCatalog.map((b) {
                      final type = b['type']?.toString() ?? '';
                      final name = b['name']?.toString() ?? type;
                      return DropdownMenuItem(value: type, child: Text(name));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedType = val;
                          final match = commercialCatalog.firstWhere((x) => x['type'] == val);
                          nameCtrl.text = match['name']?.toString() ?? 'Facility';
                        });
                      }
                    },
                  ),
                  SizedBox(height: context.spacingControl),
                  Text('FACILITY NAME', style: context.captionStyle),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.radiusControl)),
                    ),
                  ),
                  SizedBox(height: context.spacingControl),
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
                        Text(
                          currentSpec['description']?.toString() ?? '',
                          style: context.widgetFooterStyle,
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ACQUISITION COST:', style: context.captionStyle),
                            Text('$creditCost CRD + $materialCost MAT',
                                style: context.widgetValueStyle.copyWith(color: context.warningColor)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('STAFF CAPACITY:', style: context.captionStyle),
                            Text('$staffSlots Staff / Robot Slots',
                                style: context.widgetValueStyle.copyWith(color: context.primaryColor)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('BASE REVENUE:', style: context.captionStyle),
                            Text('+$baseRev CRD / Day',
                                style: context.widgetValueStyle.copyWith(color: context.successColor)),
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
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'PURCHASE & BUILD',
              variant: EarthButtonVariant.primary,
              onPressed: () async {
                Navigator.pop(dialogContext);
                EarthAudioEngine.instance.playClick();
                await action(() => const EarthApi().purchaseBuilding(
                      buildingType: selectedType,
                      name: nameCtrl.text.trim(),
                      cityId: cityId,
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
  final buildingId = building['id']?.toString() ?? '';
  final name = building['name']?.toString() ?? 'Building';
  final currentTier = asIntOr(building['tier'], 1);
  final nextTier = currentTier + 1;
  final creditCost = 4500 * nextTier;
  final compCost = 20 * nextTier;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text('Upgrade $name', style: context.topicTitleStyle),
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Upgrading infrastructure to Tier $nextTier increases staff capacity by +4 slots and boosts base commercial yield by +35%.',
              style: context.widgetFooterStyle,
            ),
            SizedBox(height: context.spacingControl),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusControl),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('CURRENT LEVEL:', style: context.captionStyle),
                      Text('Tier $currentTier', style: context.widgetValueStyle),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('UPGRADE TARGET:', style: context.captionStyle),
                      Text('Tier $nextTier (+4 slots, +35% yield)',
                          style: context.widgetValueStyle.copyWith(color: context.primaryColor)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('REQUIRED INVESTMENT:', style: context.captionStyle),
                      Text('$creditCost CRD + $compCost COMP',
                          style: context.widgetValueStyle.copyWith(color: context.warningColor)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'COMMISSION UPGRADE',
          variant: EarthButtonVariant.primary,
          onPressed: () async {
            Navigator.pop(dialogContext);
            EarthAudioEngine.instance.playClick();
            await action(() => const EarthApi().upgradeBuilding(buildingId: buildingId));
          },
        ),
      ],
    ),
  );
}

Future<void> showMunicipalLaborDispatchDialog(
  BuildContext context,
  EarthState state,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final machines = state.machines.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  final activePool = state.municipalLabor.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  final pooledMachineIds = activePool.where((m) => m['status'] == 'active').map((m) => m['machine_id']?.toString()).toSet();

  final eligibleMachines = machines.where((m) {
    final status = m['status']?.toString() ?? 'active';
    final id = m['id']?.toString() ?? '';
    return status == 'active' && !pooledMachineIds.contains(id);
  }).toList();

  if (eligibleMachines.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All active machines are already dispatched or assigned.')),
    );
    return;
  }

  String selectedMachineId = eligibleMachines.first['id']?.toString() ?? '';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final machine = eligibleMachines.firstWhere((m) => m['id'] == selectedMachineId, orElse: () => eligibleMachines.first);
        final name = machine['name']?.toString() ?? 'Machine';
        final machineType = (machine['machine_type']?.toString() ?? 'rig').toUpperCase();
        final cond = asIntOr(machine['condition'], 100);

        return AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text('Dispatch Machine to Municipal Labor Pool', style: context.topicTitleStyle),
          content: SizedBox(
            width: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Assigning your automated robot or machine to the City Municipal Labor Pool provides rotating shift labor across public megaprojects (Power Grids, Hospitals, Transit Termini). The City Treasury pays guaranteed daily payroll to your account.',
                  style: context.widgetFooterStyle,
                ),
                SizedBox(height: context.spacingControl),
                Text('SELECT DISPATCH UNIT', style: context.captionStyle),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedMachineId,
                  dropdownColor: context.panelColor,
                  style: context.bodyStyle.copyWith(color: context.inkColor),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.radiusControl)),
                  ),
                  items: eligibleMachines.map((m) {
                    final id = m['id']?.toString() ?? '';
                    final mName = m['name']?.toString() ?? id;
                    final mType = (m['machine_type']?.toString() ?? 'rig').toUpperCase();
                    return DropdownMenuItem(value: id, child: Text('$mName ($mType)'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedMachineId = val;
                      });
                    }
                  },
                ),
                SizedBox(height: context.spacingControl),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('MACHINE STATUS:', style: context.captionStyle),
                          Text('$cond% Condition',
                              style: context.widgetValueStyle.copyWith(
                                color: cond > 70 ? context.successColor : context.warningColor,
                              )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ESTIMATED SHIFT PAYROLL:', style: context.captionStyle),
                          Text('~96 – 288 CRD / Day',
                              style: context.widgetValueStyle.copyWith(color: context.successColor)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'DISPATCH TO CITY WORKS',
              variant: EarthButtonVariant.primary,
              onPressed: () async {
                Navigator.pop(dialogContext);
                EarthAudioEngine.instance.playClick();
                await action(() => const EarthApi().registerMunicipalLabor(machineId: selectedMachineId));
              },
            ),
          ],
        );
      },
    ),
  );
}
