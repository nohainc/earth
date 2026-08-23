import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/consequence_preview_card.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showFormationComposer(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  required bool city,
  String? communityId,
  String? cityId,
}) async {
  final name = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        city ? 'Form a City' : 'Form a Corporation',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: name,
        autofocus: true,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: city ? 'City name' : 'Corporation name',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Cancel', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Submit',
          onPressed: () async {
            final selectedName = name.text.trim();
            if (selectedName.length < 3) return;
            Navigator.pop(dialogContext);
            await action(() => city
                ? const EarthApi().createCity(selectedName, communityId ?? 'COM-001')
                : const EarthApi().createCorporation(selectedName, cityId ?? 'CITY-0084'));
          },
        ),
      ],
    ),
  );
}

Future<void> showCommunityComposer(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
) async {
  final name = TextEditingController(text: 'Carthage Makers');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Found New Community',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: name,
        autofocus: true,
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: 'Community Name',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Found Community',
          onPressed: () async {
            final selectedName = name.text.trim();
            if (selectedName.length < 3) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().createCommunity());
          },
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
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Contribute to Community',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: TextField(
        controller: amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: context.bodyStyle.copyWith(color: context.inkColor),
        decoration: InputDecoration(
          labelText: 'Amount (Credits)',
          labelStyle: context.widgetFooterStyle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
        EarthButton(
          label: 'Contribute',
          onPressed: () async {
            final val = double.tryParse(amount.text.trim());
            if (val == null || val <= 0) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().contributeToCommunity(communityId, val));
          },
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
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            corporation ? 'Set corporation tax charter' : 'Set city tax charter',
            style: context.topicTitleStyle.copyWith(color: context.primaryColor),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Rates are entered as percentages (0–30%). Stored in exact basis points.',
                    style: context.widgetFooterStyle,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: income,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Income tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sales,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Sales tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: corporate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Corporate tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: property,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: context.bodyStyle.copyWith(color: context.inkColor),
                    decoration: InputDecoration(
                      labelText: 'Property tax (%)',
                      labelStyle: context.widgetFooterStyle,
                    ),
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
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'SAVE CHARTER',
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
        backgroundColor: context.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        title: Text(
          'Corporation Admission Policy',
          style: context.topicTitleStyle.copyWith(color: context.primaryColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'open',
              groupValue: policy,
              activeColor: context.primaryColor,
              onChanged: (value) => setState(() => policy = value!),
              title: Text('Open membership', style: context.widgetValueStyle),
              subtitle: Text('New members join the capital city immediately.', style: context.widgetFooterStyle),
            ),
            RadioListTile<String>(
              value: 'approval',
              groupValue: policy,
              activeColor: context.primaryColor,
              onChanged: (value) => setState(() => policy = value!),
              title: Text('Admin approval', style: context.widgetValueStyle),
              subtitle: Text('Administrators review membership requests.', style: context.widgetFooterStyle),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
          ),
          EarthButton(
            label: 'SAVE POLICY',
            onPressed: () async {
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().setCorporationAdmissionPolicy(
                    corporationId: corporationId,
                    policy: policy,
                  ));
            },
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
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Found a Corporation',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your corporation and its capital city are founded together. You become the first member and city resident.',
              style: context.widgetFooterStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: corporation,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Corporation name',
                labelStyle: context.widgetFooterStyle,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: capital,
              style: context.bodyStyle.copyWith(color: context.inkColor),
              decoration: InputDecoration(
                labelText: 'Capital city name',
                labelStyle: context.widgetFooterStyle,
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
          label: 'FOUND CORPORATION',
          onPressed: () async {
            final corporationName = corporation.text.trim();
            final cityName = capital.text.trim();
            if (corporationName.length < 3 || cityName.length < 3) return;
            Navigator.pop(dialogContext);
            await action(() => const EarthApi().createCorporationWithCapital(
                  corporationName: corporationName,
                  cityName: cityName,
                ));
          },
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
      .where((row) => corporationId == null || row['corporation_id']?.toString() == corporationId)
      .toList();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Text(
        'Change City Jurisdiction',
        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
      ),
      content: SizedBox(
        width: 520,
        child: cities.isEmpty
            ? const EarthEmptyState(
                message: 'No cities in your current corporation network are available.',
                icon: Icons.location_city_outlined,
              )
            : EarthDataList(
                children: cities.map((city) {
                  final id = city['id']?.toString() ?? '';
                  final rules = city['rules'] is Map
                      ? Map<String, dynamic>.from(city['rules'] as Map)
                      : const <String, dynamic>{};
                  final income = asDouble(rules['incomeTaxBps']);
                  final tax = income == null
                      ? 'Taxes: Default'
                      : 'Income tax: ${(income / 100).toStringAsFixed(2)}%';
                  final isCurrent = id == currentCityId;

                  return EarthDataRow(
                    title: city['name']?.toString() ?? id,
                    subtitle: '${city['residents'] ?? 0} residents · $tax',
                    leading: Icon(
                      Icons.location_city_outlined,
                      size: context.iconSize,
                      color: isCurrent ? context.primaryColor : context.mutedColor,
                    ),
                    trailing: isCurrent
                        ? const EarthBadge(label: 'CURRENT JURISDICTION')
                        : EarthButton(
                            label: 'MOVE',
                            variant: EarthButtonVariant.primary,
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await action(() => const EarthApi().joinCity(cityId: id));
                            },
                          ),
                  );
                }).toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('CLOSE', style: context.controlStyle.copyWith(color: context.mutedColor)),
        ),
      ],
    ),
  );
}
