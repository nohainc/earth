import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/earth_primitives.dart';

class OpportunityPanel extends StatelessWidget {
  final List<dynamic> opportunities;
  final ValueChanged<String>? onNavigate;

  const OpportunityPanel({
    super.key,
    required this.opportunities,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) => EarthPanel(
        title: 'LIVE OPPORTUNITIES',
        width: double.infinity,
        onInfoTap: () => showEarthInfoDialog(
          context,
          title: 'LIVE SIGNALS & OPPORTUNITIES',
          subtitle: 'Prioritized simulation intelligence alerts',
          items: [
            {
              'label': 'Orange / High Priority',
              'description':
                  'Immediate decision vectors (e.g. tight commodity supply, urgent votes closing soon, high market price shifts).',
            },
            {
              'label': 'Violet / Medium Priority',
              'description':
                  'Standard operational updates (e.g. pending civic proposals, active commercial contract notices).',
            },
            {
              'label': 'Teal / Low Priority / Tech',
              'description':
                  'Longer-term advantages (e.g. ongoing research breakthroughs, R&D funding progress).',
            },
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: opportunities.isEmpty
              ? [
                  const Text(
                    'No critical alerts requiring immediate intervention.',
                    style: TextStyle(color: mutedColor, fontSize: 11),
                  ),
                ]
              : opportunities.map((raw) {
                  final opportunity = Map<String, dynamic>.from(raw as Map);
                  final signal = opportunity['signal']?.toString() ?? 'world';
                  final priority =
                      opportunity['priority']?.toString() ?? 'medium';
                  final color = priority == 'high'
                      ? Colors.orangeAccent
                      : priority == 'low'
                          ? Colors.tealAccent
                          : violetColor;

                  String targetSection = 'command';
                  String actionText = 'View →';
                  if (signal.contains('market')) {
                    targetSection = 'market';
                    actionText = 'View Market →';
                  } else if (signal.contains('governance') ||
                      signal.contains('civic') ||
                      signal.contains('vote')) {
                    targetSection = 'civic';
                    actionText = 'Review Vote →';
                  } else if (signal.contains('research') ||
                      signal.contains('tech')) {
                    targetSection = 'technology';
                    actionText = 'Open Research →';
                  } else if (signal.contains('business') ||
                      signal.contains('production')) {
                    targetSection = 'business';
                    actionText = 'Open Business →';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(top: 5, right: 10),
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      opportunity['title']?.toString() ??
                                          'World signal',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (onNavigate != null &&
                                      targetSection != 'command')
                                    InkWell(
                                      onTap: () => onNavigate!(targetSection),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        child: Text(
                                          actionText,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: violetColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                opportunity['detail']?.toString() ?? '',
                                style: const TextStyle(
                                    color: mutedColor, fontSize: 11),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                signal.toUpperCase(),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
        ),
      );
}
