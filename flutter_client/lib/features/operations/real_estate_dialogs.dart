import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';

export 'buildings_hub_screen.dart' show showDemolishConfirmDialog;

Future<bool?> showBuildingAcquisitionDialog(
  BuildContext context,
  dynamic action,
  List<dynamic> catalog,
  String territoryId,
  int availableSlots,
) async {
  String selectedType = catalog.isNotEmpty
      ? (catalog.first['type'] ?? catalog.first['building_type'] ?? '').toString()
      : '';
  final nameController = TextEditingController(text: 'New Facility');

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Acquire District Plot & Construct'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ARCHITECTURAL BLUEPRINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Enter facility name:'),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Facility Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            if (action is Function) {
              await (action as dynamic)(() async {
                return const EarthApi().purchaseV5Building(
                  buildingType: selectedType,
                  name: nameController.text.trim(),
                );
              });
            }
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          child: const Text('COMMENCE CONSTRUCTION'),
        ),
      ],
    ),
  );
}

Future<bool?> showBuildingUpgradeDialog(
  BuildContext context,
  dynamic action,
  Map<String, dynamic> building,
) async {
  final buildingId = building['id']?.toString() ?? '';
  final buildingName = building['name']?.toString() ?? 'Facility';

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Upgrade $buildingName'),
      content: Text('Upgrade $buildingName to the next Building Tier.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            if (action is Function) {
              await (action as dynamic)(() async {
                return const EarthApi().upgradeBuilding(
                  buildingId: buildingId,
                );
              });
            }
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          child: const Text('EXECUTE UPGRADE'),
        ),
      ],
    ),
  );
}
