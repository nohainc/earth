import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class YearAndDay {
  final int year;
  final int dayOfYear;
  const YearAndDay(this.year, this.dayOfYear);
}

class Sidebar extends StatefulWidget {
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

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  Timer? _ticker;
  int _localElapsedSeconds = 0;
  int _baseElapsedRealSeconds = 0;

  // Cosmic Origin Epoch: 2026-01-01T00:00:00.000Z
  static final int epochStartMs =
      DateTime.utc(2026, 1, 1, 0, 0, 0).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _syncClockWithServer();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _localElapsedSeconds++;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.clock != widget.state.clock) {
      _syncClockWithServer();
    }
  }

  void _syncClockWithServer() {
    try {
      final clockMap = widget.state.json['clock'] as Map<String, dynamic>?;
      final rawServerTime = clockMap?['serverCurrentTime'];
      final serverMs = rawServerTime is num
          ? rawServerTime.toInt()
          : (rawServerTime is String ? int.tryParse(rawServerTime) : null) ??
              DateTime.now().toUtc().millisecondsSinceEpoch;

      final diffMs = serverMs - epochStartMs;
      _baseElapsedRealSeconds = diffMs > 0 ? (diffMs ~/ 1000) : 0;
    } catch (_) {
      _baseElapsedRealSeconds = 0;
    }
    _localElapsedSeconds = 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Calculates Year and Day-of-Year with 365 days per normal year,
  /// and 366 days on leap years (every 5th year).
  static YearAndDay calculateYearAndDay(int totalDays) {
    if (totalDays <= 0) return const YearAndDay(1, 1);
    int daysLeft = totalDays - 1;
    int year = 1;
    while (true) {
      final daysInThisYear = (year % 5 == 0) ? 366 : 365;
      if (daysLeft < daysInThisYear) {
        return YearAndDay(year, daysLeft + 1);
      }
      daysLeft -= daysInThisYear;
      year++;
    }
  }

  String _formatLiveDateTime() {
    try {
      // 1 real second = 1 in-game minute (60 in-game seconds)
      final totalRealSeconds = _baseElapsedRealSeconds + _localElapsedSeconds;
      final totalGameMinutes = totalRealSeconds; // 1 real sec -> 1 game min

      final inDayMinute = totalGameMinutes % 1440;
      final totalDays = (totalGameMinutes ~/ 1440) + 1;

      final hour = (inDayMinute ~/ 60) % 24;
      final minute = inDayMinute % 60;
      final timeStr =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

      final res = calculateYearAndDay(totalDays);
      return 'YEAR ${res.year} · DAY ${res.dayOfYear} · $timeStr';
    } catch (_) {
      return 'YEAR 1 · DAY 184 · 07:42';
    }
  }

  bool get _isLocalDatabaseMode {
    final host = Uri.base.host.toLowerCase();
    if (host.isNotEmpty &&
        host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '0.0.0.0' &&
        !host.contains('local')) {
      return false;
    }
    final env = widget.state.json['environment'] as String?;
    if (env == 'production') return false;
    final authority = widget.state.json['authority'] as String?;
    if (authority == 'production') return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.state.human['name'] ?? 'Human'}';
    final city =
        '${(widget.state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';
    final groups = [
      (
        'OVERVIEW',
        [
          ('command', 'Command', Icons.dashboard_outlined),
          ('activity', 'Activity', Icons.notifications_none),
        ]
      ),
      (
        'ECONOMY',
        [
          ('market', 'Market', Icons.swap_horiz),
          ('business', 'Business', Icons.business_center_outlined),
          ('finance', 'Finance', Icons.account_balance_wallet_outlined),
          ('contracts', 'Contracts', Icons.handshake_outlined),
        ]
      ),
      (
        'CIVIC & OPERATIONS',
        [
          ('civic', 'Civic', Icons.how_to_vote_outlined),
          ('city', city, Icons.location_city_outlined),
          ('technology', 'Technology', Icons.memory_outlined),
          ('life', 'Legacy', Icons.auto_awesome_outlined),
        ]
      ),
    ];

    final liveColor = widget.isLiveConnected
        ? cyanAccentColor
        : widget.isReconnecting
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      width: 244,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BRAND HEADER (Horizontally Centered, Thin Crisp Orbit Ring, 1.3 Letter Spacing)
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Clean thin orbit ring with ambient glow
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: violetColor,
                        width: 1.75,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: violetColor.withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'EARTH',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4.0,
                          color: violetColor,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'UNITED CORPORATIONS',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. LIVE WORLD CLOCK (Centered, Clean Text, Not Bold, Muted Color, 1.3 Spacing)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _formatLiveDateTime(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500, // Not bold
                  letterSpacing: 1.3, // 1.3 letter spacing
                  color: mutedColor, // Same as inactive menu item
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. USER IDENTITY (Muted color like inactive items, Flat/Transparent, Positioned below)
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            color: surfaceColor,
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            tooltip: 'User account menu',
            onSelected: (value) => value == 'security'
                ? widget.onSecurity?.call()
                : widget.onLogout?.call(),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: inkColor,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.state.human['email'] ?? 'amara@earthuc.com'} · $city',
                      style: const TextStyle(
                        fontSize: 10,
                        color: mutedColor,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 15, color: mutedColor),
                    SizedBox(width: 8),
                    Text(
                      'Account security',
                      style: TextStyle(fontSize: 12, letterSpacing: 1.3),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 15, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text(
                      'Sign out',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: violetColor.withValues(alpha: 0.45),
                    child: Text(
                      name.trim().isEmpty ? 'H' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                        letterSpacing: 1.3,
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
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500, // Matches inactive item weight
                            color: mutedColor, // Matches inactive menu item color
                            letterSpacing: 1.3,
                          ),
                        ),
                        Text(
                          city,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mutedColor.withValues(alpha: 0.75),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.unfold_more, size: 14, color: mutedColor),
                ],
              ),
            ),
          ),

          // 4. HORIZONTAL SEPARATOR LINE
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Colors.white12, height: 1, thickness: 1),
          ),

          // 5. NAVIGATION MENU ITEMS (Selected: White text; Activity item hosts live telemetry indicator)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int groupIdx = 0;
                      groupIdx < groups.length;
                      groupIdx++) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        top: groupIdx == 0 ? 8 : 20, // 2x top whitespace
                        bottom: 6,
                      ),
                      child: Text(
                        groups[groupIdx].$1,
                        style: const TextStyle(
                          color: mutedColor,
                          fontSize: 8.5,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final item in groups[groupIdx].$2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => widget.onNavigate(item.$1),
                            style: TextButton.styleFrom(
                              splashFactory: NoSplash.splashFactory, // No wave animation
                              enableFeedback: false,
                              foregroundColor: violetColor,
                              backgroundColor:
                                  item.$1 == widget.selectedSection
                                      ? violetColor.withValues(alpha: .16)
                                      : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 8,
                              ),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.$3,
                                  size: 16,
                                  color: item.$1 == widget.selectedSection
                                      ? violetColor
                                      : mutedColor,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      // Selected item uses crisp White color; weight remains regular/medium (NOT bold)
                                      color: item.$1 == widget.selectedSection
                                          ? Colors.white
                                          : mutedColor,
                                      fontSize: 12,
                                      letterSpacing: 1.3,
                                      fontWeight: FontWeight.w500, // Non-bold
                                    ),
                                  ),
                                ),
                                // Activity & Alerts: Shows NEW badge if alerts exist, or live connection beacon dot
                                if (item.$1 == 'activity')
                                  if (widget.unreadNotifications > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: liveColor.withValues(
                                          alpha: .18,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: liveColor,
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 6.5,
                                      height: 6.5,
                                      decoration: BoxDecoration(
                                        color: liveColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: liveColor.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 5,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // 6. ADVANCE DAY BUTTON & BOTTOM LINE (Only visible in Local DB / Dev mode; hidden in Production)
          if (_isLocalDatabaseMode && widget.onAdvanceDay != null) ...[
            const Divider(color: Colors.white12, height: 16, thickness: 1),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed:
                    widget.busy || !widget.canAdvanceDay ? null : widget.onAdvanceDay,
                icon: const Icon(Icons.skip_next_rounded, size: 16),
                label: const Text(
                  'Advance Day (Local DB)',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 1.3),
                ),
                style: TextButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  foregroundColor: violetColor.withValues(alpha: 0.8),
                  disabledForegroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
