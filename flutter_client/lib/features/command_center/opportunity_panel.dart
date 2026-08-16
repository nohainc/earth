import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/earth_primitives.dart';

class OpportunityPanel extends StatelessWidget {
  final List<dynamic> opportunities;
  const OpportunityPanel({super.key, required this.opportunities});

  @override
  Widget build(BuildContext context) => EarthPanel(
        title: 'LIVE OPPORTUNITIES',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: opportunities.map((raw) {
            final opportunity = Map<String, dynamic>.from(raw as Map);
            final signal = opportunity['signal']?.toString() ?? 'world';
            final priority = opportunity['priority']?.toString() ?? 'medium';
            final color = priority == 'high'
                ? Colors.orangeAccent
                : priority == 'low'
                    ? Colors.tealAccent
                    : violetColor;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opportunity['title']?.toString() ?? 'World signal',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          opportunity['detail']?.toString() ?? '',
                          style: const TextStyle(color: mutedColor, fontSize: 11),
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
