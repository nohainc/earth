import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_consequence.dart';
import '../../shared/widgets/consequence_preview_card.dart';

Future<void> showResearchComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final name = TextEditingController(text: 'Quantum Matrix Grid');
  final budget = TextEditingController(text: '240');
  String focus = 'efficiency';
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
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Technology focus'),
                          onChanged: (_) => setState(() {})),
                      const SizedBox(height: 10),
                      TextField(
                          controller: budget,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Initial budget (minimum 240 C)'),
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
                          projectName: name.text.trim().isEmpty ? 'Classified Initiative' : name.text.trim(),
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
                        if (name.text.trim().length < 3 ||
                            amount == null ||
                            amount < 240) {
                          return;
                        }
                        await action(() => const EarthApi().startResearch(
                            name.text.trim(), amount,
                            focus: focus));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Start')),
                ],
              );
            },
          ));
}

Future<void> showLicenseComposerDialog(BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action) async {
  final licensee = TextEditingController();
  final fee = TextEditingController(text: '100');
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('License technology'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: licensee,
                  decoration:
                      const InputDecoration(labelText: 'Licensee Human ID')),
              TextField(
                  controller: fee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'License fee (minimum 50 C)')),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(fee.text.trim());
                    if (licensee.text.trim().isEmpty ||
                        amount == null ||
                        amount < 50) {
                      return;
                    }
                    await action(() => const EarthApi()
                        .licenseTechnologyTo(licensee.text, amount, otp.text));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('License')),
            ],
          ));
}
