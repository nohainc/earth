import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class Sidebar extends StatelessWidget {
  final EarthState state;
  final String selectedSection;
  final ValueChanged<String> onNavigate;
  final bool busy;
  final bool canAdvanceDay;
  final bool isLiveConnected;
  final bool isReconnecting;
  final int unreadNotifications;
  final VoidCallback? onAdvanceDay;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;

  const Sidebar({
    super.key,
    required this.state,
    this.selectedSection = 'command',
    required this.onNavigate,
    this.busy = false,
    this.canAdvanceDay = false,
    this.isLiveConnected = false,
    this.isReconnecting = false,
    this.unreadNotifications = 0,
    this.onAdvanceDay,
    this.onLogout,
    this.onSecurity,
  });

  String _clockLabel() {
    final rawMinute = state.clock['minute'];
    final minute =
        rawMinute is num ? rawMinute.toInt() : int.tryParse('$rawMinute') ?? 0;
    final hour = (minute ~/ 60) % 24;
    final displayMinute = minute % 60;
    return '${hour.toString().padLeft(2, '0')}:${displayMinute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final name = '${state.human['name'] ?? 'Human'}';
    final city =
        '${(state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';
    final businessName = '${state.business['name'] ?? 'Business'}';
    final technologyName =
        '${state.technologyRegistry['activeProject'] ?? 'Technology'}';
    final groups = [
      (
        'OVERVIEW',
        [
          ('command', 'Command center', Icons.dashboard_outlined),
          ('activity', 'Activity & alerts', Icons.notifications_none),
        ]
      ),
      (
        'ECONOMY',
        [
          ('market', 'Central Market', Icons.swap_horiz),
          ('business', businessName, Icons.business_center_outlined),
          (
            'finance',
            'Personal finance',
            Icons.account_balance_wallet_outlined
          ),
          ('contracts', 'Contracts', Icons.handshake_outlined),
        ]
      ),
      (
        'CIVIC & OPERATIONS',
        [
          ('civic', 'Civic life', Icons.how_to_vote_outlined),
          ('city', city, Icons.location_city_outlined),
          ('technology', technologyName, Icons.memory_outlined),
          ('life', 'Life & legacy', Icons.auto_awesome_outlined),
        ]
      ),
    ];
    final liveLabel = isLiveConnected
        ? 'LIVE'
        : isReconnecting
            ? 'RECONNECTING'
            : 'OFFLINE';
    final liveColor = isLiveConnected
        ? cyanAccentColor
        : isReconnecting
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('◌  EARTH',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3)),
                    Padding(
                      padding: EdgeInsets.only(left: 28, top: 2),
                      child: Text('UNITED CORPORATIONS',
                          style: TextStyle(
                              fontSize: 8,
                              color: mutedColor,
                              letterSpacing: 1.2)),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Advance one game day',
                child: IconButton(
                  onPressed: busy || !canAdvanceDay ? null : onAdvanceDay,
                  icon: const Icon(Icons.skip_next_rounded, size: 19),
                  color: violetColor,
                  disabledColor: Colors.white24,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PopupMenuButton<String>(
            onSelected: (value) =>
                value == 'security' ? onSecurity?.call() : onLogout?.call(),
            itemBuilder: (context) => [
              PopupMenuItem(
                  enabled: false,
                  child: Text('$name\n${state.human['email'] ?? ''}')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'security', child: Text('Account security')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            child: Row(children: [
              CircleAvatar(
                  radius: 15,
                  backgroundColor: violetColor,
                  child: Text(
                      name.trim().isEmpty ? 'H' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(fontSize: 10))),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700))),
              const Icon(Icons.expand_more, size: 16, color: mutedColor),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: liveColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(liveLabel,
                style:
                    TextStyle(color: liveColor, fontSize: 9, letterSpacing: 1)),
          ]),
          const SizedBox(height: 7),
          const Text('WORLD CLOCK',
              style:
                  TextStyle(color: mutedColor, fontSize: 8, letterSpacing: 1)),
          Text('DAY ${state.clock['day']} · ${_clockLabel()}',
              style: const TextStyle(fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in groups) ...[
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 8, top: 8, bottom: 5),
                      child: Text(group.$1,
                          style: const TextStyle(
                              color: mutedColor,
                              fontSize: 8,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700)),
                    ),
                    for (final item in group.$2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => onNavigate(item.$1),
                            style: TextButton.styleFrom(
                              foregroundColor: violetColor,
                              backgroundColor: item.$1 == selectedSection
                                  ? violetColor.withValues(alpha: .16)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Row(children: [
                              Icon(item.$3,
                                  size: 16,
                                  color: item.$1 == selectedSection
                                      ? violetColor
                                      : mutedColor),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(item.$2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: item.$1 == selectedSection
                                            ? inkColor
                                            : mutedColor,
                                        fontSize: 11,
                                        fontWeight: item.$1 == selectedSection
                                            ? FontWeight.w700
                                            : FontWeight.w500)),
                              ),
                              if (item.$1 == 'activity' &&
                                  unreadNotifications > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: cyanAccentColor.withValues(
                                          alpha: .15),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Text('NEW',
                                      style: TextStyle(
                                          color: cyanAccentColor,
                                          fontSize: 7,
                                          fontWeight: FontWeight.w800)),
                                ),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12),
          Text('$name · $city',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: mutedColor, fontSize: 9)),
        ],
      ),
    );
  }
}
