import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'technology_dialogs.dart';

class TechnologyPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const TechnologyPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tech = state.technology;
    final research = tech['research'] is Map<String, dynamic>
        ? (tech['research'] as Map<String, dynamic>)
        : tech;
    final techName = (research['name'] as String?)?.toUpperCase() ??
        (tech['name'] as String?)?.toUpperCase() ??
        'ADAPTIVE MAINTENANCE AI';
    final progress =
        (asDouble(research['progress']) ?? asDouble(tech['progress']) ?? 0)
            .clamp(0.0, 100.0);
    final focus = research['focus'] ?? tech['focus'] ?? 'efficiency';
    final budget = research['budget'] ?? research['budgetPerDay'] ?? 240;
    final isComplete = progress >= 100;

    final activePatents =
        state.technologyRegistry['activePatents'] ?? (isComplete ? 1 : 0);
    final activeLicenses = state.technologyRegistry['activeLicenses'] ?? 1;

    return EarthPanel(
      key: panelKey,
      title: 'TECHNOLOGY / RESEARCH & PATENTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      techName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Focus: $focus · Budget: $budget C · Status: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}',
                      style: const TextStyle(color: mutedColor, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${progress.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isComplete ? cyanAccentColor : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress / 100,
            color: isComplete ? cyanAccentColor : Colors.lightBlueAccent,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Patents granted: $activePatents',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Active licenses: $activeLicenses (5.00% royalty)',
                    style:
                        const TextStyle(fontSize: 11, color: cyanAccentColor),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy || isComplete
                    ? null
                    : () => action(() => const EarthApi().fundResearch()),
                child: const Text('FUND 240 C'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showResearchComposerDialog(context, action),
                child: const Text('NEW PROJECT · 240 C'),
              ),
              OutlinedButton(
                onPressed: busy || !isComplete
                    ? null
                    : () => action(() => const EarthApi().grantPatent()),
                child: const Text('GRANT PATENT'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().licenseTechnology()),
                child: const Text('LICENSE (5%)'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showLicenseComposerDialog(context, action),
                child: const Text('LICENSE TO HUMAN'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
