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
        infoDescription:
            '• Strategic Alert Feed: Aggregates real-time events across the economic, civic, and operational spheres that demand citizen action.\n\n• Priority Tiers:\n  - HIGH (Orange): Immediate risk of resource deficit, machine failure, contract default, insolvency, or expiring ballot.\n  - MEDIUM (Violet): Actionable market arbitrage, profitable price spreads, or open governance referendums.\n  - LOW (Teal): Background civic notices, minor market trends, and non-critical updates.\n\n• Deep Navigation: Tapping an opportunity\'s action button immediately navigates you to the corresponding terminal panel to execute decisions.',
        width: double.infinity,
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
                  if (signal.contains('market')) {
                    targetSection = 'market';
                  } else if (signal.contains('governance') ||
                      signal.contains('civic') ||
                      signal.contains('vote')) {
                    targetSection = 'civic';
                  } else if (signal.contains('research') ||
                      signal.contains('tech')) {
                    targetSection = 'technology';
                  } else if (signal.contains('business') ||
                      signal.contains('production')) {
                    targetSection = 'business';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: onNavigate != null && targetSection != 'command'
                          ? () => onNavigate!(targetSection)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(top: 6, right: 10),
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
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                            color: inkColor,
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
                                  const SizedBox(height: 5),
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    children: [
                                      Text(
                                        signal.toUpperCase(),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const Text(
                                        '·',
                                        style: TextStyle(
                                          color: Colors.white24,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        '${priority.toUpperCase()} PRIORITY',
                                        style: const TextStyle(
                                          color: mutedColor,
                                          fontSize: 9,
                                          letterSpacing: .8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
        ),
      );
}
