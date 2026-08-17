import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        gradient: const LinearGradient(
          colors: [surfaceColor, Color(0xff24234c)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '●  CITIZEN COCKPIT · $statusText',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
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
                        subtitle:
                            'Identity, personal status, and planetary indices',
                        items: [
                          {
                            'label':
                                'Citizen Identity ($citizenName · Age $citizenAge)',
                            'description':
                                'Your active human persona in the UC simulation. Generational knowledge, property ownership, and dynastic lineage are tied to this persona.',
                          },
                          {
                            'label':
                                'Personal Standing (${state.human['standing'] ?? '0'}) & Legacy (${state.human['legacy'] ?? '0'})',
                            'description':
                                'Standing measures civic influence and assembly voting weight. Legacy tracks dynastic achievement points passed down to successors.',
                          },
                          {
                            'label':
                                'Biological Health (${state.human['health'] ?? '100'}%)',
                            'description':
                                'Physical condition and stamina of your persona.',
                          },
                          {
                            'label':
                                'World Health ($healthScore / 100 · $statusText)',
                            'description':
                                'Planetary simulation vitality reflecting aggregate resource availability, infrastructure uptime, and macroeconomic stability.',
                          },
                          {
                            'label':
                                'Living Cost Index ($lci) · Essential Services ($esi)',
                            'description':
                                'Baseline upkeep cost multiplier and municipal utility uptime across chartered cities.',
                          },
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  citizenName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: inkColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'AGE $citizenAge  ·  GEN $citizenGen  ·  $cityName',
                  style: const TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    letterSpacing: .7,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statusPill(
                      'Health',
                      '${formatWholeNumber(state.human['health'] ?? 100)}%',
                      Colors.tealAccent,
                    ),
                    _statusPill(
                      'Standing',
                      formatWholeNumber(state.human['standing'] ?? 0),
                      cyanAccentColor,
                    ),
                    _statusPill(
                      'Legacy',
                      formatWholeNumber(state.human['legacy'] ?? 0),
                      Colors.indigoAccent,
                    ),
                    _statusPill(
                      'World Health',
                      '$healthScore/100',
                      statusColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _citizenAvatar(citizenName),
        ],
      ),
    );
  }

  Widget _statusPill(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: const TextStyle(fontSize: 10, color: mutedColor),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _citizenAvatar(String name) {
    final nameParts = name.trim().split(RegExp(r'\s+'));
    final initials = nameParts.length >= 2
        ? '${nameParts[0].isNotEmpty ? nameParts[0][0] : ""}${nameParts[1].isNotEmpty ? nameParts[1][0] : ""}'
        : (name.isNotEmpty ? name.substring(0, name.length.clamp(1, 2)) : 'UC');

    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: violetColor.withValues(alpha: .5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: violetColor.withValues(alpha: .22),
            blurRadius: 30,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xff6c5ce7), Color(0xff3b3086)],
            ),
            border: Border.all(
              color: cyanAccentColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                initials.toUpperCase(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'CITIZEN',
                style: TextStyle(
                  fontSize: 7.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: cyanAccentColor.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
