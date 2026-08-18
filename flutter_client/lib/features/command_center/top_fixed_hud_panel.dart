import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/format_helpers.dart';
import '../finance/net_worth_analytics_dialog.dart';
import '../onboarding/onboarding_welcome_dialog.dart';
import '../../core/onboarding_controller.dart';
import 'theme_customizer_dialog.dart';

class YearAndDay {
  final int year;
  final int dayOfYear;
  const YearAndDay(this.year, this.dayOfYear);
}

class TopFixedHudPanel extends StatefulWidget {
  final EarthState state;
  final int unreadNotifications;
  final int unreadCommMessages;
  final bool isLiveConnected;
  final bool isReconnecting;
  final bool showDrawerButton;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;
  final VoidCallback? onCommLink;
  final VoidCallback? onMapTap;

  const TopFixedHudPanel({
    super.key,
    required this.state,
    this.unreadNotifications = 0,
    this.unreadCommMessages = 0,
    this.isLiveConnected = false,
    this.isReconnecting = false,
    this.showDrawerButton = false,
    this.onOpenDrawer,
    this.onNavigate,
    this.onLogout,
    this.onSecurity,
    this.onCommLink,
    this.onMapTap,
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

  (YearAndDay, String) _getLiveClockData() {
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
      return (res, timeStr);
    } catch (_) {
      return (const YearAndDay(1, 184), '07:42');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.state.human['name'] ?? 'Human'}';
    final city =
        '${(widget.state.institutions['city'] as Map<String, dynamic>?)?['name'] ?? 'Independent'}';

    final credits = formatWholeNumber(widget.state.human['credits']);
    final food = formatWholeNumber(widget.state.resources['food']);
    final mat = formatWholeNumber(widget.state.resources['material'] ?? widget.state.resources['materials']);
    final comp = formatWholeNumber(widget.state.resources['components']);
    final energy = formatWholeNumber(widget.state.resources['energy']);
    final compute = formatWholeNumber(widget.state.resources['compute']);

    final connectionColor = widget.isLiveConnected
        ? Colors.greenAccent
        : (widget.isReconnecting ? Colors.orangeAccent : Colors.redAccent);

    final (clockRes, timeStr) = _getLiveClockData();

    return LayoutBuilder(
      builder: (context, rootConstraints) {
        final totalWidth = rootConstraints.maxWidth;
        // Switch to 2 rows when width < 800px
        final isSingleRow = totalWidth >= 800;
        // Hide app name text when width < 600px
        final showBrandText = totalWidth >= 600;
        const showBrand = true;

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
              // 1. BRAND HEADER (RESPONSIVELY COLLAPSIBLE)
              if (showBrand) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: violetColor,
                          width: 1.75,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: violetColor.withValues(alpha: 0.55),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    if (showBrandText) ...[
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
                  ],
                ),
                _verticalSeparator(),
              ],

              // 2. CURRENT YEAR & DATE TIME (1-ROW OR 2-ROWS)
              if (isSingleRow)
                Text(
                  'YEAR ${clockRes.year} · DAY ${clockRes.dayOfYear} · $timeStr',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.3,
                    color: mutedColor,
                  ),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YEAR ${clockRes.year}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'DAY ${clockRes.dayOfYear} · $timeStr',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),

              // VERTICAL SEPARATOR
              _verticalSeparator(),

              // 3. 6-RESOURCE SECTION
              Expanded(
                child: isSingleRow
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _hudResourceItem(
                              Icons.account_balance_wallet_outlined,
                              credits,
                              violetColor,
                              isCompact: false,
                              tooltip: 'Liquid Credits & Net-Worth Analytics',
                              onTap: () {
                                EarthAudioEngine.instance.playClick();
                                showNetWorthAnalyticsDialog(context, api: const EarthApi());
                              },
                            ),
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
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _hudResourceItem(
                                  Icons.account_balance_wallet_outlined,
                                  credits,
                                  violetColor,
                                  isCompact: true,
                                  tooltip: 'Liquid Credits & Net-Worth Analytics',
                                  onTap: () {
                                    EarthAudioEngine.instance.playClick();
                                    showNetWorthAnalyticsDialog(context, api: const EarthApi());
                                  },
                                ),
                              ),
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
                      ),
              ),

              const SizedBox(width: 8),

              // 4. ALARM / NOTIFICATIONS ICON WITH CONNECTION STATE COLOR INDICATOR
              InkWell(
                onTap: () => widget.onNavigate?.call('activity'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Stack(
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
                ),
              ),

              const SizedBox(width: 4),

              // COMM-LINK SUB-SPACE RELAY BUTTON WITH UNREAD BADGE
              InkWell(
                onTap: widget.onCommLink,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.settings_input_antenna,
                        size: 21,
                        color: EarthColors.cyanAccent,
                      ),
                      if (widget.unreadCommMessages > 0)
                        Positioned(
                          top: -3,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: EarthColors.cyanAccent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: EarthColors.cyanAccent.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                            alignment: Alignment.center,
                            child: Text(
                              '${widget.unreadCommMessages}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // PLANETARY MAP TACTICAL GRID BUTTON
              Tooltip(
                message: 'Planetary Tactical Grid & Concession Leases',
                child: InkWell(
                  onTap: widget.onMapTap,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      Icons.public,
                      size: 21,
                      color: EarthColors.cyanAccent,
                    ),
                  ),
                ),
              ),

              // AUDIO / SOUND ENGINE CONTROLLER
              Tooltip(
                message: EarthAudioEngine.instance.isMuted ? 'Unmute Audio & SFX' : 'Audio Atmosphere & SFX Settings',
                child: InkWell(
                  key: const Key('btn-audio-toggle'),
                  onTap: () {
                    setState(() {
                      EarthAudioEngine.instance.toggleMute();
                      if (!EarthAudioEngine.instance.isMuted) {
                        EarthAudioEngine.instance.playClick();
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      EarthAudioEngine.instance.isMuted ? Icons.volume_off : Icons.volume_up,
                      size: 21,
                      color: EarthAudioEngine.instance.isMuted ? EarthColors.textMuted : EarthColors.cyanAccent,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // THEME & AESTHETICS CONTROLLER
              Tooltip(
                message: 'Command Center Themes & Palettes',
                child: InkWell(
                  key: const Key('btn-theme-customizer'),
                  onTap: () {
                    EarthAudioEngine.instance.playClick();
                    showThemeCustomizerDialog(context);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      Icons.palette_outlined,
                      size: 21,
                      color: EarthColors.cyanAccent,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // ORIENTATION & FIRST-SESSION GUIDE
              Tooltip(
                message: 'First-Session Orientation Guide',
                child: InkWell(
                  key: const Key('btn-orientation-guide'),
                  onTap: () {
                    EarthAudioEngine.instance.playClick();
                    OnboardingController.instance.setDismissed(false);
                    showOnboardingWelcomeDialog(context);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      Icons.help_outline,
                      size: 21,
                      color: EarthColors.cyanAccent,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 5. USER ACCOUNT MENU (ICON INSTEAD OF AVATAR CIRCLE)
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
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 21,
                    color: mutedColor,
                  ),
                ),
              ),

              // 6. HAMBURGER MENU (SHOWN ONLY WHEN SIDEBAR IS HIDDEN IN COMPACT MODE)
              if (widget.showDrawerButton) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onOpenDrawer,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.menu_rounded, size: 21, color: inkColor),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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

  Widget _hudResourceItem(IconData icon, String value, Color color, {required bool isCompact, VoidCallback? onTap, String? tooltip}) {
    final row = Row(
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

    if (onTap != null) {
      return Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          key: const Key('btn-hud-credits-analytics'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: row,
          ),
        ),
      );
    }
    return row;
  }
}
