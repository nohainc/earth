import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showDecommissionDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.errorColor.withValues(alpha: 0.5)),
            ),
            title: Text('Recycle machine?', style: dialogContext.pageTitleStyle.copyWith(color: dialogContext.errorColor)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'This permanently decommissions the machine and salvages 25 Material and 5 Components.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Recycle',
                variant: EarthButtonVariant.danger,
                onPressed: () async {
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .decommissionMachine(machineId, otp: otpCode));
                },
              ),
            ],
          ));
}

Future<void> showMachineUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Upgrade machine', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Upgrade cost: 600 Credits and 20 Components. Capacity increases by +0.2 and installation reduces condition by 5%.',
                style: dialogContext.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Upgrade',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi()
                      .upgradeMachine(machineId, otp: otpCode));
                },
              ),
            ],
          ));
}

Future<void> showMachineSaleDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String machineId) async {
  final buyer = TextEditingController();
  final price = TextEditingController(text: '1200');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
              side: BorderSide(color: dialogContext.subtleBorderColor),
            ),
            title: Text('Sell machine', style: dialogContext.pageTitleStyle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: buyer,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Buyer Human ID'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price in Credits (CR)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Authenticator code (if enabled)',
                ),
              ),
            ]),
            actions: [
              EarthButton(
                label: 'Cancel',
                variant: EarthButtonVariant.neutral,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              EarthButton(
                label: 'Sell',
                variant: EarthButtonVariant.primary,
                onPressed: () async {
                  final targetBuyer = buyer.text.trim();
                  final parsedPrice = double.tryParse(price.text.trim());
                  if (targetBuyer.isEmpty || parsedPrice == null || parsedPrice <= 0) return;
                  final otpCode = otp.text.trim();
                  Navigator.pop(dialogContext);
                  await action(() => const EarthApi().sellMachine(
                      machineId, targetBuyer, parsedPrice,
                      otp: otpCode));
                },
              ),
            ],
          ));
}

Future<void> showMachineAcquisitionDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  List<dynamic> productionCatalog,
) async {
  final catalogOptions = productionCatalog
      .whereType<Map>()
      .expand((sector) => (sector['machineTypes'] is List ? sector['machineTypes'] as List : const []).map((type) {
        final machineType = type.toString();
        final acquisition = sector['acquisition'] is Map ? Map<String, dynamic>.from(sector['acquisition'] as Map) : const <String, dynamic>{};
        return {'type': machineType, 'output': sector['output']?.toString() ?? 'resource', ...acquisition};
      }))
      .where((option) => option['credit'] != null)
      .toList();
  final options = catalogOptions.isNotEmpty
      ? catalogOptions
      : [
          {'type': 'energy-array', 'output': 'energy', 'credit': 3600, 'material': 60},
          {'type': 'food-synthesizer', 'output': 'food', 'credit': 4400, 'material': 75},
          {'type': 'extractor', 'output': 'material', 'credit': 4200, 'material': 80},
          {'type': 'fabricator', 'output': 'components', 'credit': 4800, 'material': 90},
          {'type': 'compute-node', 'output': 'compute', 'credit': 5200, 'material': 100},
        ];
  String selectedType = options.first['type'].toString();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: dialogContext.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
          side: BorderSide(color: dialogContext.subtleBorderColor),
        ),
        title: Text('Acquire Machine', style: dialogContext.pageTitleStyle),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a production unit from the machine catalog to expand capacity.',
                  style: dialogContext.widgetFooterStyle,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedType,
                  items: options.map((option) => DropdownMenuItem<String>(
                    value: option['type'].toString(),
                    child: Text('${option['type'].toString().replaceAll('-', ' ').toUpperCase()} · ${option['credit']} CR + ${option['material']} Material'),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 14),
                ConsequencePreviewCard(
                  consequence: DecisionConsequence.machineAcquisition(
                    machineName: selectedType.replaceAll('-', ' ').toUpperCase(),
                    costCredits: (options.firstWhere((option) => option['type'].toString() == selectedType)['credit'] as num).toDouble(),
                    outputYield: '${options.firstWhere((option) => option['type'].toString() == selectedType)['output']} production capacity',
                    businessName: 'Primary Enterprise',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          EarthButton(
            label: 'Cancel',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          EarthButton(
            label: 'Acquire',
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().acquireMachine(selectedType));
            },
          ),
        ],
      ),
    ),
  );
}
