import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';
import '../../shared/widgets/format_helpers.dart';

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
                        : const EarthApi().createCorporation(
                            selectedName, cityId ?? 'CITY-0084'));
                  },
                  child: const Text('Submit')),
            ],
          ));
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
            await action(
                () => const EarthApi().contributeToCommunity(communityId, val));
          },
          child: const Text('Contribute'),
        ),
      ],
    ),
  );
}

Future<void> showTaxCharterDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String institutionId, {
  bool corporation = false,
}) async {
  final income = TextEditingController(text: '5.0');
  final sales = TextEditingController(text: '2.0');
  final corporate = TextEditingController(text: '10.0');
  final property = TextEditingController(text: '1.0');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final parsedIncome = double.tryParse(income.text.trim()) ?? 5.0;
        final parsedCorporate = double.tryParse(corporate.text.trim()) ?? 10.0;
        return AlertDialog(
          title: Text(corporation
              ? 'Set corporation tax charter'
              : 'Set city tax charter'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Rates are entered as percentages (0–30%). Stored in exact basis points.',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextField(
                    controller: income,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Income tax (%)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: sales,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Sales tax (%)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: corporate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Corporate tax (%)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: property,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Property tax (%)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  ConsequencePreviewCard(
                    consequence: DecisionConsequence.municipalTaxAdjustment(
                      cityName: institutionId,
                      oldRatePct: 5.0,
                      newRatePct: (parsedIncome + parsedCorporate) / 2.0,
                    ),
                  ),
                ],
              ),
            ),
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
                if (rates
                    .any((value) => value == null || value < 0 || value > 30)) {
                  return;
                }
                Navigator.pop(dialogContext);
                await action(() => corporation
                    ? const EarthApi().setCorporationTaxCharter(
                        corporationId: institutionId,
                        incomeTaxBps: (rates[0]! * 100).round(),
                        salesTaxBps: (rates[1]! * 100).round(),
                        corporateTaxBps: (rates[2]! * 100).round(),
                        propertyTaxBps: (rates[3]! * 100).round(),
                      )
                    : const EarthApi().setCityTaxCharter(
                        cityId: institutionId,
                        incomeTaxBps: (rates[0]! * 100).round(),
                        salesTaxBps: (rates[1]! * 100).round(),
                        corporateTaxBps: (rates[2]! * 100).round(),
                        propertyTaxBps: (rates[3]! * 100).round(),
                      ));
              },
              child: const Text('SAVE CHARTER'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showAdmissionPolicyDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  String corporationId, {
  String currentPolicy = 'open',
}) async {
  var policy = currentPolicy == 'approval' ? 'approval' : 'open';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Corporation admission'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile<String>(
            value: 'open',
            groupValue: policy,
            onChanged: (value) => setState(() => policy = value!),
            title: const Text('Open membership'),
            subtitle:
                const Text('New members join the capital city immediately.'),
          ),
          RadioListTile<String>(
            value: 'approval',
            groupValue: policy,
            onChanged: (value) => setState(() => policy = value!),
            title: const Text('Admin approval'),
            subtitle: const Text('Administrators review membership requests.'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().setCorporationAdmissionPolicy(
                  corporationId: corporationId, policy: policy));
            },
            child: const Text('SAVE POLICY'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCorporationWithCapitalDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final corporation = TextEditingController();
  final capital = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Found a corporation'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Your corporation and its capital city are founded together. You become the first member and city resident.',
              style: TextStyle(fontSize: 11, color: mutedColor)),
          const SizedBox(height: 12),
          TextField(
              controller: corporation,
              decoration: const InputDecoration(labelText: 'Corporation name')),
          TextField(
              controller: capital,
              decoration:
                  const InputDecoration(labelText: 'Capital city name')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: () async {
            final corporationName = corporation.text.trim();
            final cityName = capital.text.trim();
            if (corporationName.length < 3 || cityName.length < 3) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().createCorporationWithCapital(
                corporationName: corporationName, cityName: cityName));
          },
          child: const Text('FOUND CORPORATION'),
        ),
      ],
    ),
  );
}

Future<void> showCityChangeDialog(
  BuildContext context,
  EarthState state,
  String currentCityId,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final corporationId = state.membership?['corporation_id']?.toString();
  final cities = (state.rankings['cities'] is List
          ? state.rankings['cities'] as List
          : const <dynamic>[])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where((row) => corporationId == null ||
          row['corporation_id']?.toString() == corporationId)
      .toList();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Change city'),
      content: SizedBox(
        width: 520,
        child: cities.isEmpty
            ? const Text('No cities in your current corporation network are available.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: cities.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final city = cities[index];
                  final id = city['id']?.toString() ?? '';
                  final rules = city['rules'] is Map
                      ? Map<String, dynamic>.from(city['rules'] as Map)
                      : const <String, dynamic>{};
                  final income = asDouble(rules['incomeTaxBps']);
                  final tax = income == null
                      ? 'taxes: default'
                      : 'income tax: ${(income / 100).toStringAsFixed(2)}%';
                  return ListTile(
                    title: Text(city['name']?.toString() ?? id),
                    subtitle: Text(
                        '${city['residents'] ?? 0} residents · $tax'),
                    trailing: id == currentCityId
                        ? const Text('CURRENT',
                            style: TextStyle(color: mutedColor, fontSize: 9))
                        : FilledButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await action(() =>
                                  const EarthApi().joinCity(cityId: id));
                            },
                            child: const Text('MOVE'),
                          ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE')),
      ],
    ),
  );
}
