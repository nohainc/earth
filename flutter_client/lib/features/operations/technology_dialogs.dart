import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showResearchComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  String name = 'Automated Assembly';
  final budget = TextEditingController(text: '240');
  String focus = 'efficiency';
  int minimumBudget(String technology) => const {
        'Automated Assembly': 240,
        'Clean Energy Systems': 320,
        'Food Synthesis': 280,
        'Predictive Maintenance': 300,
        'Civic Network Infrastructure': 360,
      }[technology] ?? 240;
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            final parsedBudget = double.tryParse(budget.text.trim()) ?? 240.0;
            return AlertDialog(
                title: const Text('Start Research Project'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: name,
                          items: const [
                            'Automated Assembly',
                            'Clean Energy Systems',
                            'Food Synthesis',
                            'Predictive Maintenance',
                            'Civic Network Infrastructure',
                          ].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => name = value);
                          },
                          decoration: const InputDecoration(labelText: 'Technology catalogue')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: budget,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                              labelText: 'Initial budget (minimum ${minimumBudget(name)} C)'),
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
                              .map((item) =>
                                  DropdownMenuItem(value: item, child: Text(item)))
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
                          unlockYield: '+15% $focus boost across industrial production',
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
                        await action(() => const EarthApi().startResearch(
                            name, amount,
                            focus: focus));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Start')),
                ],
              );
            },
          ));
}
