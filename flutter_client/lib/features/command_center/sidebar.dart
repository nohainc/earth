import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class Sidebar extends StatelessWidget {
  final EarthState state;
  final String selectedSection;
  final ValueChanged<String> onNavigate;

  const Sidebar({
    super.key,
    required this.state,
    this.selectedSection = 'command',
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${state.human['name'] ?? 'Human'}';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final city =
        '${(state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';
    final businessName = '${state.business['name'] ?? 'Business'}';
    final technologyName =
        '${state.technologyRegistry['activeProject'] ?? 'Technology'}';
    final items = [
      ('command', '✦  Command center'),
      ('market', '⌁  Central Market'),
      ('business', '◈  $businessName'),
      ('civic', '⊙  Civic life'),
      ('city', '⌖  $city'),
      ('technology', '✧  $technologyName'),
      ('life', '◒  Life & legacy'),
      ('contracts', '⇄  Contracts'),
    ];

    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '◌  EARTH',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 28, top: 2, bottom: 26),
            child: Text(
              'UNITED CORPORATIONS',
              style: TextStyle(
                fontSize: 8,
                color: mutedColor,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: violetColor,
                  child: Text(
                    initials.isEmpty ? 'H' : initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Human · $city',
                        style: const TextStyle(fontSize: 8, color: mutedColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onNavigate(item.$1),
                  style: TextButton.styleFrom(
                    backgroundColor: item.$1 == selectedSection
                        ? violetColor.withValues(alpha: .14)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    alignment: Alignment.centerLeft,
                  ),
              child: Text(
                    item.$2,
                    style: TextStyle(
                      color: item.$1 == selectedSection
                          ? violetColor
                          : mutedColor,
                      fontSize: 11,
                      fontWeight: item.$1 == selectedSection
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          const Divider(color: Colors.white12),
          const Text(
            '●  WORLD CLOCK',
            style: TextStyle(
              color: cyanAccentColor,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'DAY ${state.clock['day']} · ${state.clock['minute']}',
            style: const TextStyle(fontSize: 10, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
