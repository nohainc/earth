import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showResearchComposerDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    List<dynamic> catalog) async {
  final entries = catalog
      .whereType<Map>()
      .map((raw) {
        return Map<String, dynamic>.from(raw);
      })
      .where((item) => item['name'] != null)
      .toList();
  if (entries.isEmpty) return;
  String name = entries.first['name'].toString();
  final initialCost = entries.first['research_credit_cost_units'] ??
      entries.first['researchCostUnits'] ??
      entries.first['researchCost'] ??
      0;
  final budget = TextEditingController(text: initialCost.toString());
  String focus = 'efficiency';
  Map<String, dynamic> selectedEntry() => entries.firstWhere(
        (item) => item['name'].toString() == name,
        orElse: () => entries.first,
      );
  double minimumBudget(String technology) {
    final item = selectedEntry();
    return double.tryParse((item['research_credit_cost_units'] ??
                item['researchCostUnits'] ??
                item['researchCost'] ??
                0)
            .toString()) ??
        0;
  }

  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) {
              final parsedBudget =
                  double.tryParse(budget.text.trim()) ?? minimumBudget(name);
              return AlertDialog(
                title: const Text('Start Research Project'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: name,
                          items: entries
                              .map((item) => DropdownMenuItem(
                                  value: item['name'].toString(),
                                  child: Text(item['name'].toString())))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => name = value);
                          },
                          decoration: const InputDecoration(
                              labelText: 'Technology catalogue')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: budget,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText:
                                  'Initial budget (minimum ${minimumBudget(name)} C)'),
                          onChanged: (_) => setState(() {})),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: focus,
                          items: const [
                            'efficiency',
                            'durability',
                            'safety',
                            'cost'
                          ]
                              .map((item) => DropdownMenuItem(
                                  value: item, child: Text(item)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => focus = value);
                          },
                          decoration: const InputDecoration(
                              labelText: 'Research parameter focus')),
                      const SizedBox(height: 14),
                      ConsequencePreviewCard(
                        consequence: DecisionConsequence.researchFunding(
                          projectName: name,
                          computeAllocated: parsedBudget,
                          unlockYield:
                              'Effects are defined by the approved technology catalogue.',
                        ),
                      ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        final amount = double.tryParse(budget.text.trim());
                        if (amount == null || amount < minimumBudget(name)) {
                          return;
                        }
                        await action(() => const EarthApi()
                            .startResearch(name, amount, focus: focus));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Start')),
                ],
              );
            },
          ));
}
