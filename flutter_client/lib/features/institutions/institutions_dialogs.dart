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
                    if (name.text.trim().length < 3) return;
                    final selectedName = name.text.trim();
                    await action(() => city
                        ? const EarthApi()
                            .createCity(selectedName, communityId!)
                        : const EarthApi()
                            .createCorporation(selectedName, cityId!));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Submit')),
            ],
          ));
  name.dispose();
}

Future<void> showTaxCharterDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String cityId) async {
  final income = TextEditingController(text: '0');
  final sales = TextEditingController(text: '0');
  final corporate = TextEditingController(text: '0');
  final property = TextEditingController(text: '0');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Set city tax charter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Rates are entered as percentages. The authority stores them in exact basis points.',
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
            if (rates.any((value) => value == null || value < 0 || value > 100)) {
              return;
            }
            await action(() => const EarthApi().setCityTaxCharter(
                  cityId: cityId,
                  incomeTaxBps: (rates[0]! * 100).round(),
                  salesTaxBps: (rates[1]! * 100).round(),
                  corporateTaxBps: (rates[2]! * 100).round(),
                  propertyTaxBps: (rates[3]! * 100).round(),
                ));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
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
