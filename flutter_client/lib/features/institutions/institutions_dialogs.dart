import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showFormationComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    {required bool city, String? communityId, String? cityId}) async {
  final name = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: Text(city ? 'Form a City' : 'Form a Corporation'),
            content: TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: city ? 'City name' : 'Corporation name')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final selectedName = name.text.trim();
                    if (selectedName.length < 3) return;
                    Navigator.pop(dialogContext);
                    await action(() => city
                        ? const EarthApi()
                            .createCity(selectedName, communityId ?? 'COM-001')
                        : const EarthApi()
                            .createCorporation(selectedName, cityId ?? 'CITY-0084'));
                  },
                  child: const Text('Submit')),
            ],
          ));
  name.dispose();
}

Future<void> showCommunityComposer(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController(text: 'Carthage Makers');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Found New Community'),
      content: TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Community Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final selectedName = name.text.trim();
            if (selectedName.length < 3) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().createCommunity());
          },
          child: const Text('Found Community'),
        ),
      ],
    ),
  );
  name.dispose();
}

Future<void> showCommunityContributionDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String communityId,
) async {
  final amount = TextEditingController(text: '50');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Contribute to Community'),
      content: TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Amount (Credits)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final val = double.tryParse(amount.text.trim());
            if (val == null || val <= 0) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().contributeToCommunity(communityId, val));
          },
          child: const Text('Contribute'),
        ),
      ],
    ),
  );
  amount.dispose();
}

Future<void> showTaxCharterDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String cityId) async {
  final income = TextEditingController(text: '5.0');
  final sales = TextEditingController(text: '2.0');
  final corporate = TextEditingController(text: '10.0');
  final property = TextEditingController(text: '1.0');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Set city tax charter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Rates are entered as percentages (0–30%). Stored in exact basis points.',
            style: TextStyle(fontSize: 12),
          ),
          TextField(
            controller: income,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Income tax (%)'),
          ),
          TextField(
            controller: sales,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Sales tax (%)'),
          ),
          TextField(
            controller: corporate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Corporate tax (%)'),
          ),
          TextField(
            controller: property,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Property tax (%)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            final rates = [
              double.tryParse(income.text.trim()),
              double.tryParse(sales.text.trim()),
              double.tryParse(corporate.text.trim()),
              double.tryParse(property.text.trim()),
            ];
            if (rates.any((value) => value == null || value < 0 || value > 30)) {
              return;
            }
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().setCityTaxCharter(
                  cityId: cityId,
                  incomeTaxBps: (rates[0]! * 100).round(),
                  salesTaxBps: (rates[1]! * 100).round(),
                  corporateTaxBps: (rates[2]! * 100).round(),
                  propertyTaxBps: (rates[3]! * 100).round(),
                ));
          },
          child: const Text('SAVE CHARTER'),
        ),
      ],
    ),
  );
  income.dispose();
  sales.dispose();
  corporate.dispose();
  property.dispose();
}
