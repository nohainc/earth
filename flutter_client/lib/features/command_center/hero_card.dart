import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

/// The command-center world-health visual is isolated from API and state
/// orchestration so dashboard work can evolve without enlarging main.dart.
class HeroCard extends StatelessWidget {
  final EarthState state;

  const HeroCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final healthRaw = state.world['health'];
    final healthScore = (healthRaw is num)
        ? healthRaw.toInt()
        : int.tryParse(healthRaw?.toString() ?? '68') ?? 68;

    String statusText = 'STABLE';
    Color statusColor = cyanAccentColor;
    if (healthScore < 40) {
      statusText = 'RECOVERING';
      statusColor = Colors.orangeAccent;
    } else if (healthScore < 70) {
      statusText = 'NOMINAL';
      statusColor = Colors.tealAccent;
    }

    final lci = state.world['livingCostIndex'] ??
        state.world['living_cost_index'] ??
        '1.00';
    final esi = state.world['essentialServicesIndex'] ??
        state.world['essential_services_index'] ??
        state.world['infrastructure_health'] ??
        '1.00';

    return Container(
      width: double.infinity,
      height: 218,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        gradient: const LinearGradient(
          colors: [surfaceColor, Color(0xff24234c)],
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '●  WORLD HEALTH · $statusText',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.info_outline,
                      size: 13,
                      color: mutedColor.withValues(alpha: .8),
                    ),
                    tooltip: 'World Health information',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => showEarthInfoDialog(
                      context,
                      title: 'WORLD HEALTH & VITALS',
                      subtitle: 'Planetary simulation balance indicators',
                      items: [
                        {
                          'label': 'World Health Score ($healthScore / 100)',
                          'description':
                              'The composite vitality of the EARTH simulation. It reflects aggregate resource availability, machine breakdown rates, power grid stability, and macroeconomic solvency.',
                        },
                        {
                          'label': 'LCI — Living Cost Index ($lci)',
                          'description':
                              'Multiplier measuring the cost of basic subsistence needs (food, energy, shelter). A higher LCI increases daily human upkeep requirements.',
                        },
                        {
                          'label': 'ESI — Essential Services Index ($esi)',
                          'description':
                              'Infrastructure uptime and municipal public utility stability across all chartered cities.',
                        },
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                '$healthScore',
                style: const TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -4,
                ),
              ),
              Text(
                'LCI $lci  ·  ESI $esi',
                style: const TextStyle(color: mutedColor, fontSize: 10),
              ),
            ],
          ),
          Positioned(
            right: 55,
            top: 3,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: violetColor.withValues(alpha: .5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: violetColor.withValues(alpha: .22),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [violetColor, Color(0xff5145b7)],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'EARTH',
                        style: TextStyle(fontSize: 8, letterSpacing: 2),
                      ),
                      Text(
                        '${state.clock['day']}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'DAY',
                        style: TextStyle(fontSize: 8, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
