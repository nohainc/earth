import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
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
    final techName =
        (state.technology['name'] as String?)?.toUpperCase() ?? 'R&D SYSTEM';
    return EarthPanel(
      key: panelKey,
      title: 'TECHNOLOGY / $techName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state.technology['progress']}% complete',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Research focus: ${state.technology['focus'] ?? 'efficiency'}',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          Text(
            'Patents ${state.technologyRegistry['activePatents']}  ·  Licenses ${state.technologyRegistry['activeLicenses']}',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (state.technology['progress'] as num).toDouble() / 100,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => action(() => const EarthApi().fundResearch()),
            child: const Text('FUND 240 C'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed:
                busy ? null : () => showResearchComposerDialog(context, action),
            child: const Text('START NEW RESEARCH · 240 C MIN'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().grantPatent()),
                child: const Text('GRANT PATENT'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () =>
                        action(() => const EarthApi().licenseTechnology()),
                child: const Text('LICENSE 5%'),
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
