import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/format_helpers.dart';

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
  Map<String, dynamic> serverQuote = const {};
  bool quoteLoading = true;
  try {
    serverQuote = await const EarthApi().quoteResearch(name);
  } catch (_) {
    serverQuote = const {};
  } finally {
    quoteLoading = false;
  }

  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) {
              final quote = serverQuote['quote'] is Map
                  ? Map<String, dynamic>.from(serverQuote['quote'] as Map)
                  : const <String, dynamic>{};
              final quotedTechnology = serverQuote['technology'] is Map
                  ? Map<String, dynamic>.from(
                      serverQuote['technology'] as Map)
                  : const <String, dynamic>{};
              final blockers = (quote['blockers'] as List?)
                      ?.map((item) => item.toString())
                      .toList(growable: false) ??
                  const <String>[];
              final canStart = serverQuote['ok'] == true && blockers.isEmpty;
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
                            if (value != null) {
                              name = value;
                              setState(() {
                                serverQuote = const {};
                                quoteLoading = true;
                              });
                              const EarthApi()
                                  .quoteResearch(value)
                                  .then((quote) {
                                if (!context.mounted) return;
                                setState(() {
                                  serverQuote = quote;
                                  quoteLoading = false;
                                });
                              });
                            }
                          },
                          decoration: const InputDecoration(
                              labelText: 'Technology catalogue')),
                      const SizedBox(height: 14),
                      if (quoteLoading)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Loading authoritative research quote…'),
                        ),
                      if (serverQuote['ok'] == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          'CATALOG AUTHORITY\n'
                          'Cost: ${formatCreditUnits(quote['researchCostUnits'])}\n'
                          'Duration: ${quote['researchDurationGameDays'] ?? '—'} game days\n'
                          'Prerequisites: ${(quote['prerequisites'] as List?)?.join(', ') ?? 'None published'}\n'
                          'Effects: ${(quotedTechnology['effects'] as List?)?.map((effect) => effect is Map ? effect['effectType'] : effect).join(', ') ?? 'None published'}\n'
                          'Budget before: ${formatCreditUnits(quote['budgetBeforeUnits'])}\n'
                          'Budget after: ${formatCreditUnits(quote['budgetAfterUnits'])}\n'
                          'Completes on game day: ${quote['completesGameDay'] ?? '—'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (blockers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('BLOCKED: ${blockers.join(' · ')}',
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ],
                      if (!quoteLoading && serverQuote['ok'] != true)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Research quote unavailable.'),
                        ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: canStart
                          ? () async {
                              await action(
                                  () => const EarthApi().startResearch(name));
                              if (dialogContext.mounted)
                                Navigator.pop(dialogContext);
                            }
                          : null,
                      child: const Text('Start')),
                ],
              );
            },
          ));
}
