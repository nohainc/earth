part of '../../main.dart';

/// The command-center world-health visual is isolated from API and state
/// orchestration so dashboard work can evolve without enlarging main.dart.
class _HeroCard extends StatelessWidget {
  final EarthState state;

  const _HeroCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) => Container(
        height: 218,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          gradient: const LinearGradient(
            colors: [_surface, Color(0xff24234c)],
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '●  WORLD HEALTH · STABLE',
                  style: TextStyle(
                    color: _cyanAccent,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  '${state.world['health']}',
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -4,
                  ),
                ),
                Text(
                  'LCI ${state.world['livingCostIndex']}  ·  ESI ${state.world['essentialServicesIndex']}',
                  style: const TextStyle(color: _muted, fontSize: 10),
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
                    color: _violet.withValues(alpha: .5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _violet.withValues(alpha: .22),
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
                        colors: [_violet, Color(0xff5145b7)],
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
