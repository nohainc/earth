import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/format_helpers.dart';
import '../onboarding/onboarding_welcome_dialog.dart';
import '../../core/onboarding_controller.dart';
import 'theme_customizer_dialog.dart';
import '../../core/models/live_connection_status.dart';

class YearAndDay {
  final int year;
  final int dayOfYear;
  const YearAndDay(this.year, this.dayOfYear);
}

class _HudResource {
  final String key;
  final IconData icon;
  final Color color;
  final String value;
  final double net;

  const _HudResource(this.key, this.icon, this.color, this.value, this.net);
}

const _menuSurfaceColor = surfaceColor;
const _menuElevation = 14.0;
const _menuConstraints = BoxConstraints(minWidth: 210, maxWidth: 250);
const _menuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  side: BorderSide(color: Colors.white12),
);
const _menuTextStyle = EarthTypography.menu;

class TopFixedHudPanel extends StatefulWidget {
  final EarthState state;
  final int unreadNotifications;
  final int unreadCommMessages;
  final bool isLiveConnected;
  final bool isReconnecting;
  final LiveConnectionStatus? connectionStatus;
  final bool showDrawerButton;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;
  final VoidCallback? onCommLink;
  final VoidCallback? onReconnect;

  const TopFixedHudPanel({
    super.key,
    required this.state,
    this.unreadNotifications = 0,
    this.unreadCommMessages = 0,
    this.isLiveConnected = false,
    this.isReconnecting = false,
    this.connectionStatus,
    this.showDrawerButton = false,
    this.onOpenDrawer,
    this.onNavigate,
    this.onLogout,
    this.onSecurity,
    this.onCommLink,
    this.onReconnect,
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
    final flowMap =
        (widget.state.json['resourceFlows'] as Map<String, dynamic>?) ??
            const {};
    double netFor(String key) {
      final raw =
          flowMap[key] ?? (key == 'material' ? flowMap['materials'] : null);
      return asDoubleOr((raw as Map<String, dynamic>?)?['net'], 0);
    }

    final resources = [
      _HudResource('food', Icons.eco_outlined, EarthResourceColors.food,
          formatWholeNumber(widget.state.resources['food']), netFor('food')),
      _HudResource(
          'energy',
          Icons.bolt_outlined,
          EarthResourceColors.energy,
          formatWholeNumber(widget.state.resources['energy']),
          netFor('energy')),
      _HudResource(
          'material',
          Icons.view_in_ar_outlined,
          EarthResourceColors.materials,
          formatWholeNumber(widget.state.resources['material'] ??
              widget.state.resources['materials']),
          netFor('material')),
      _HudResource(
          'components',
          Icons.settings_outlined,
          EarthResourceColors.components,
          formatWholeNumber(widget.state.resources['components']),
          netFor('components')),
      _HudResource(
          'compute',
          Icons.memory_rounded,
          EarthResourceColors.compute,
          formatWholeNumber(widget.state.resources['compute']),
          netFor('compute')),
    ];
    final status = widget.connectionStatus ??
        (widget.isLiveConnected
            ? LiveConnectionStatus.live
            : (widget.isReconnecting
                ? LiveConnectionStatus.reconnecting
                : LiveConnectionStatus.offline));

    final (clockRes, timeStr) = _getLiveClockData();

    return LayoutBuilder(
      builder: (context, rootConstraints) {
        final totalWidth = rootConstraints.maxWidth;
        final resourceWidth = _measureResourceRowWidth(credits, resources);
        final dateWidth = _measureText(
          'YEAR ${clockRes.year}   DAY ${clockRes.dayOfYear}   $timeStr',
          const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.3,
          ),
        );
        final brandWidth = _measureBrandWidth();
        final centerWidth = math.max(resourceWidth, dateWidth);
        final rightActionsWidth = 112 + (widget.showDrawerButton ? 32 : 0);
        final showBrandText = totalWidth - 28 >=
            brandWidth + 10 + centerWidth + rightActionsWidth + 16;
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
                _hudSpacer(),
              ],

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'YEAR ${clockRes.year}   DAY ${clockRes.dayOfYear}   $timeStr',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.3,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _hudResourceItem(
                              Icons.account_balance_wallet_outlined,
                              credits,
                              EarthResourceColors.credits,
                              isCompact: false,
                            ),
                            for (final resource in resources) ...[
                              _hudSpacer(),
                              _hudResourceItem(
                                resource.icon,
                                resource.value,
                                resource.color,
                                isCompact: false,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Connection status now lives inside the Alerts menu.
              const SizedBox(width: 4),

              // Alerts stay as a single quiet icon with one combined badge.
              _buildAlertsMenu(context, status),

              const SizedBox(width: 6),

              // 5. USER ACCOUNT MENU (ICON INSTEAD OF AVATAR CIRCLE)
              PopupMenuButton<String>(
                position: PopupMenuPosition.under,
                offset: const Offset(0, 8),
                constraints: _menuConstraints,
                color: _menuSurfaceColor,
                elevation: _menuElevation,
                shape: _menuShape,
                onSelected: (value) {
                  if (value == 'security') {
                    widget.onSecurity?.call();
                  } else if (value == 'theme') {
                    showThemeCustomizerDialog(context);
                  } else if (value == 'audio') {
                    setState(() {
                      EarthAudioEngine.instance.toggleMute();
                      if (!EarthAudioEngine.instance.isMuted) {
                        EarthAudioEngine.instance.playClick();
                      }
                    });
                  } else if (value == 'onboarding') {
                    OnboardingController.instance.setDismissed(false);
                    showOnboardingWelcomeDialog(
                      context,
                      onNavigate: widget.onNavigate,
                    );
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
                          style: _menuTextStyle.copyWith(
                            color: inkColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Citizen of $city · Standing ${widget.state.human['standing'] ?? 0}',
                          style: _menuTextStyle.copyWith(
                            fontSize: 10,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  _menuItem(
                      'security', Icons.shield_outlined, 'Security & MFA'),
                  _menuItem('theme', Icons.palette_outlined, 'Theme'),
                  _menuItem(
                    'audio',
                    EarthAudioEngine.instance.isMuted
                        ? Icons.volume_off
                        : Icons.volume_up,
                    EarthAudioEngine.instance.isMuted
                        ? 'Enable Audio'
                        : 'Mute Audio',
                  ),
                  _menuItem('onboarding', Icons.school_outlined, 'Onboarding'),
                  const PopupMenuDivider(),
                  _menuItem('logout', Icons.logout, 'Sign Out',
                      color: Colors.redAccent),
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

  Widget _buildAlertsMenu(BuildContext context, LiveConnectionStatus status) {
    final connectionColor = status.color;
    final unreadTotal = widget.unreadNotifications + widget.unreadCommMessages;
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: _menuConstraints,
      color: _menuSurfaceColor,
      elevation: _menuElevation,
      shape: _menuShape,
      onSelected: (value) {
        if (value == 'messages') {
          widget.onCommLink?.call();
        } else if (value == 'reconnect') {
          widget.onReconnect?.call();
        } else {
          widget.onNavigate?.call('activity');
        }
      },
      itemBuilder: (context) => [
        _menuItem(
            'notifications', Icons.notifications_none_outlined, 'Notifications',
            trailing: widget.unreadNotifications > 0
                ? '${widget.unreadNotifications}'
                : null),
        _menuItem('messages', Icons.settings_input_antenna, 'Messages',
            trailing: widget.unreadCommMessages > 0
                ? '${widget.unreadCommMessages}'
                : null),
        _menuItem('social', Icons.hub_outlined, 'Invitations'),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value:
              status == LiveConnectionStatus.live ? 'connection' : 'reconnect',
          enabled: status != LiveConnectionStatus.live,
          height: 54,
          child: Row(
            children: [
              Icon(status.icon, size: 16, color: mutedColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connection', style: _menuTextStyle),
                    const SizedBox(height: 2),
                    Text(status.label,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.3,
                            color: mutedColor)),
                  ],
                ),
              ),
              if (status != LiveConnectionStatus.live)
                const Text(
                  'RECONNECT',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 20, color: connectionColor),
            Positioned(
              top: -3,
              right: -5,
              child: unreadTotal > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 14, minHeight: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: connectionColor,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('$unreadTotal',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900)),
                    )
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: connectionColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: connectionColor.withValues(alpha: .6),
                              blurRadius: 4,
                              spreadRadius: 1),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color color = mutedColor,
    String? trailing,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: _menuTextStyle)),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w400,
                color: mutedColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _hudSpacer() => const SizedBox(width: 10);

  double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  double _measureResourceRowWidth(
      String credits, List<_HudResource> resources) {
    const valueStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
    );

    double itemWidth(String value, {bool padded = false}) {
      return 13 + 3.5 + _measureText(value, valueStyle) + (padded ? 6 : 0);
    }

    var width = itemWidth(credits, padded: true);
    for (final resource in resources) {
      width += 10 + itemWidth(resource.value);
    }
    return width;
  }

  double _measureBrandWidth() {
    const titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 4,
    );
    const subtitleStyle = TextStyle(
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
    );
    return 24 +
        10 +
        math.max(
          _measureText('EARTH', titleStyle),
          _measureText('UNITED CORPORATIONS', subtitleStyle),
        );
  }

  Widget _hudResourceItem(IconData icon, String value, Color color,
      {required bool isCompact, VoidCallback? onTap}) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isCompact ? 11 : 13, color: color),
        const SizedBox(width: 3.5),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: isCompact ? 9.5 : 11,
              fontWeight: FontWeight.w700,
              color: mutedColor,
              letterSpacing: 1.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        key: const Key('btn-hud-credits-analytics'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: row,
        ),
      );
    }
    return row;
  }
}
