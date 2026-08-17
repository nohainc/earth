import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

/// The command-center executive citizen and planetary cockpit.
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

    final citizenName =
        (state.human['name'] as String?)?.toUpperCase() ?? 'ALEXANDER VANE';
    final citizenAge = state.human['age'] ?? '34';
    final citizenGen = state.human['generation'] ?? '1';
    final cityName =
        (state.institutions['city']?['name'] as String?)?.toUpperCase() ??
            'NEW CARTHAGE';
    final corpName =
        (state.institutions['corporation']?['name'] as String?)?.toUpperCase() ??
            'KLINE WORKS';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
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
                    '●  CITIZEN COCKPIT · ACTIVE',
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
                    tooltip: 'Citizen & Simulation Details',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => showEarthInfoDialog(
                      context,
                      title: 'CITIZEN & SIMULATION STATUS',
                      subtitle: 'Identity, demographic vitals, and planetary indices',
                      items: [
                        {
                          'label': 'Citizen Identity ($citizenName · Age $citizenAge)',
                          'description':
                              'Your active human citizen persona in the UC simulation. Generational knowledge, property ownership, and dynastic lineage are tied to this persona.',
                        },
                        {
                          'label': 'Affiliation & Charter ($cityName · $corpName)',
                          'description':
                              'Chartered municipal residency and corporate enterprise affiliation driving cycle dividends and voting representation.',
                        },
                        {
                          'label': 'World Health ($healthScore / 100 · $statusText)',
                          'description':
                              'Planetary simulation vitality reflecting aggregate resource availability, infrastructure uptime, and macroeconomic stability.',
                        },
                        {
                          'label': 'Living Cost Index ($lci)',
                          'description':
                              'Baseline cost multiplier for essential human upkeep (food, energy, shelter).',
                        },
                        {
                          'label': 'Essential Services Index ($esi)',
                          'description':
                              'Public utility uptime and municipal grid stability across chartered cities.',
                        },
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                citizenName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: inkColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'AGE $citizenAge  ·  $cityName  ·  GENERATION $citizenGen',
                style: const TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Affiliation: $corpName   ·   Biological Uptime: 98%   ·   Assembly Status: Active Member',
                style: TextStyle(
                  color: inkColor.withValues(alpha: .85),
                  fontSize: 11,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'World Health: $healthScore / 100 ($statusText)   ·   Living Cost Index: $lci   ·   Essential Services Index: $esi',
                style: const TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            top: 10,
            bottom: 10,
            child: Center(
              child: Container(
                width: 126,
                height: 126,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: violetColor.withValues(alpha: .5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: violetColor.withValues(alpha: .22),
                      blurRadius: 36,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 76,
                    height: 76,
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
                            fontSize: 22,
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
          ),
        ],
      ),
    );
  }
}
