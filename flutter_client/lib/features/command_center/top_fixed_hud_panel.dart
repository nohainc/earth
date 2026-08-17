import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/format_helpers.dart';

class YearAndDay {
  final int year;
  final int dayOfYear;
  const YearAndDay(this.year, this.dayOfYear);
}

class TopFixedHudPanel extends StatefulWidget {
  final EarthState state;
  final int unreadNotifications;
  final bool isLiveConnected;
  final bool isReconnecting;
  final bool showDrawerButton;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;

  const TopFixedHudPanel({
    super.key,
    required this.state,
    this.unreadNotifications = 0,
    this.isLiveConnected = false,
    this.isReconnecting = false,
    this.showDrawerButton = false,
    this.onOpenDrawer,
    this.onNavigate,
    this.onLogout,
    this.onSecurity,
  });

  @override
  State<TopFixedHudPanel> createState() => _TopFixedHudPanelState();
}

class _TopFixedHudPanelState extends State<TopFixedHudPanel> {
  Timer? _ticker;
  int _localElapsedSeconds = 0;
  int _baseElapsedRealSeconds = 0;

  static final int epochStartMs =
      DateTime.utc(2026, 1, 1, 0, 0, 0).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _syncClockWithServer();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _localElapsedSeconds++;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant TopFixedHudPanel oldWidget) {
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
      final totalRealSeconds = _baseElapsedRealSeconds + _localElapsedSeconds;
      final totalGameMinutes = totalRealSeconds;
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

  @override
  Widget build(BuildContext context) {
    final name = '${widget.state.human['name'] ?? 'Human'}';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'H';
    final city =
        '${(widget.state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';

    final credits = formatCreditsAmount(widget.state.human['credits']);
    final food = formatWholeNumber(widget.state.resources['food']);
    final mat = formatWholeNumber(widget.state.resources['material'] ?? widget.state.resources['materials']);
    final comp = formatWholeNumber(widget.state.resources['components']);
    final energy = formatWholeNumber(widget.state.resources['energy']);
    final compute = formatWholeNumber(widget.state.resources['compute']);

    final connectionColor = widget.isLiveConnected
        ? Colors.greenAccent
        : (widget.isReconnecting ? Colors.orangeAccent : Colors.redAccent);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff0e1024),
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. BRAND HEADER
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: violetColor,
                    width: 1.75,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: violetColor.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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

          // VERTICAL SEPARATOR 1
          _verticalSeparator(),

          // 2. CURRENT YEAR & DATE TIME
          Text(
            _formatLiveDateTime(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.3,
              color: mutedColor,
            ),
          ),

          // VERTICAL SEPARATOR 2
          _verticalSeparator(),

          // 3. 6-RESOURCE SECTION (ICONS + NUMBERS ONLY, NO RESOURCE TEXT NAMES)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableW = constraints.maxWidth;
                final isSingleRow = availableW >= 320;

                if (isSingleRow) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _hudResourceItem(Icons.account_balance_wallet_outlined, credits, violetColor, isCompact: false),
                        _dotSeparator(),
                        _hudResourceItem(Icons.eco_outlined, food, Colors.lightGreenAccent, isCompact: false),
                        _dotSeparator(),
                        _hudResourceItem(Icons.view_in_ar_outlined, mat, Colors.tealAccent, isCompact: false),
                        _dotSeparator(),
                        _hudResourceItem(Icons.settings_outlined, comp, cyanAccentColor, isCompact: false),
                        _dotSeparator(),
                        _hudResourceItem(Icons.bolt_outlined, energy, Colors.amberAccent, isCompact: false),
                        _dotSeparator(),
                        _hudResourceItem(Icons.memory_rounded, compute, violetColor, isCompact: false),
                      ],
                    ),
                  );
                } else {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _hudResourceItem(Icons.account_balance_wallet_outlined, credits, violetColor, isCompact: true)),
                          Expanded(child: _hudResourceItem(Icons.eco_outlined, food, Colors.lightGreenAccent, isCompact: true)),
                          Expanded(child: _hudResourceItem(Icons.view_in_ar_outlined, mat, Colors.tealAccent, isCompact: true)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(child: _hudResourceItem(Icons.settings_outlined, comp, cyanAccentColor, isCompact: true)),
                          Expanded(child: _hudResourceItem(Icons.bolt_outlined, energy, Colors.amberAccent, isCompact: true)),
                          Expanded(child: _hudResourceItem(Icons.memory_rounded, compute, violetColor, isCompact: true)),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
          ),

          const SizedBox(width: 8),

          // 4. ALARM / NOTIFICATIONS ICON WITH CONNECTION STATE COLOR INDICATOR
          InkWell(
            onTap: () => widget.onNavigate?.call('activity'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_outlined, size: 20, color: mutedColor),
                      if (widget.unreadNotifications > 0)
                        Positioned(
                          top: -3,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: connectionColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                            alignment: Alignment.center,
                            child: Text(
                              '${widget.unreadNotifications}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: connectionColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: connectionColor.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 5. USER AVATAR & ACCOUNT MENU
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            color: surfaceColor,
            elevation: 14,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            tooltip: '',
            onSelected: (value) {
              if (value == 'security') {
                widget.onSecurity?.call();
              } else if (value == 'logout') {
                widget.onLogout?.call();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Citizen of $city · Standing ${widget.state.human['standing'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: mutedColor,
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
                    Icon(Icons.shield_outlined, size: 16, color: mutedColor),
                    SizedBox(width: 10),
                    Text('Security & MFA', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 16, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Sign Out',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    violetColor.withValues(alpha: .8),
                    cyanAccentColor.withValues(alpha: .7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white24, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: violetColor.withValues(alpha: .3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // 6. HAMBURGER MENU (SHOWN ONLY WHEN SIDEBAR IS HIDDEN IN COMPACT MODE)
          if (widget.showDrawerButton) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: widget.onOpenDrawer,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.menu_rounded, size: 22, color: inkColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _verticalSeparator() => Container(
        height: 24,
        width: 1,
        color: Colors.white12,
        margin: const EdgeInsets.symmetric(horizontal: 10),
      );

  Widget _dotSeparator() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
      );

  Widget _hudResourceItem(IconData icon, String value, Color color, {required bool isCompact}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isCompact ? 11 : 13, color: color),
          const SizedBox(width: 3.5),
          Text(
            value,
            style: TextStyle(
              fontSize: isCompact ? 9.5 : 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}
