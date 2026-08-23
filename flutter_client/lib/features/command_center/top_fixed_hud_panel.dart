import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/design_system/earth_logo.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../core/onboarding_controller.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import '../onboarding/onboarding_welcome_dialog.dart';
import 'daily_briefing_dialog.dart';
import 'theme_customizer_dialog.dart';

class YearAndDay {
  final int year;
  final int dayOfYear;
  const YearAndDay(this.year, this.dayOfYear);
}

class _HudResource {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final String value;
  final double net;
  final String targetSection;

  const _HudResource({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.net,
    required this.targetSection,
  });
}

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
    final human = widget.state.human;
    final name = '${human['name'] ?? human['display_name'] ?? 'Human'}';
    final initials = _extractInitials(name);
    final standing = asInt(human['standing']) ?? 0;
    final city =
        '${(widget.state.institutions['city'] is Map ? widget.state.institutions['city']['name'] : null) ?? 'Independent'}';

    final credits = formatWholeNumber(human['credits']);
    final flowMap = (widget.state.json['resourceFlows'] is Map
        ? widget.state.json['resourceFlows'] as Map
        : const {});
    double netFor(String key) {
      final raw =
          flowMap[key] ?? (key == 'material' ? flowMap['materials'] : null);
      return asDoubleOr(raw is Map ? raw['net'] : null, 0);
    }

    final resources = [
      _HudResource(
        key: 'food',
        label: 'Food',
        icon: Icons.eco_outlined,
        color: EarthResourceColors.food,
        value: formatWholeNumber(widget.state.resources['food']),
        net: netFor('food'),
        targetSection: 'market',
      ),
      _HudResource(
        key: 'energy',
        label: 'Energy',
        icon: Icons.bolt_outlined,
        color: EarthResourceColors.energy,
        value: formatWholeNumber(widget.state.resources['energy']),
        net: netFor('energy'),
        targetSection: 'market',
      ),
      _HudResource(
        key: 'material',
        label: 'Materials',
        icon: Icons.view_in_ar_outlined,
        color: EarthResourceColors.materials,
        value: formatWholeNumber(widget.state.resources['material'] ??
            widget.state.resources['materials']),
        net: netFor('material'),
        targetSection: 'market',
      ),
      _HudResource(
        key: 'components',
        label: 'Components',
        icon: Icons.settings_outlined,
        color: EarthResourceColors.components,
        value: formatWholeNumber(widget.state.resources['components']),
        net: netFor('components'),
        targetSection: 'market',
      ),
      _HudResource(
        key: 'compute',
        label: 'Compute',
        icon: Icons.memory_rounded,
        color: EarthResourceColors.compute,
        value: formatWholeNumber(widget.state.resources['compute']),
        net: netFor('compute'),
        targetSection: 'technology',
      ),
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
        final isMobile = totalWidth < 680;
        final isTablet = totalWidth >= 680 && totalWidth < 980;

        return Container(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              context.primaryColor.withValues(alpha: 0.05),
              context.canvasColor,
            ),
            border: Border(
              bottom: BorderSide(
                color: context.primaryColor.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 16,
            vertical: isMobile ? 6 : 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. BRAND LOGO & TITLE
              _buildBrandHeader(context, isMobile, isTablet),

              if (!isMobile) const SizedBox(width: 12),

              // 2. CENTER: GAME CLOCK & RESOURCE BAR
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // GAME CLOCK TICKER
                    _buildGameClockPill(context, clockRes, timeStr, isMobile),
                    const SizedBox(height: 4),

                    // SMOOTH SCROLLING RESOURCE ROW WITH SHADER EDGE FADE
                    _buildResourceBar(context, credits, resources, isMobile),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 3. RIGHT TELEMETRY & ACTIONS
              if (!isMobile) ...[
                _buildLiveTelemetryPill(context, status),
                const SizedBox(width: 8),
              ],

              // ALERTS MENU
              _buildAlertsMenu(context, status),

              const SizedBox(width: 6),

              // USER ACCOUNT & EXECUTIVE PERSONA
              _buildExecutiveProfileMenu(
                context,
                name: name,
                initials: initials,
                standing: standing,
                city: city,
                isMobile: isMobile,
              ),

              // 4. HAMBURGER MENU FOR MOBILE / COLLAPSED SIDEBAR
              if (widget.showDrawerButton) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onOpenDrawer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.menu_rounded, size: 21, color: context.inkColor),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- BRAND HEADER ---
  Widget _buildBrandHeader(
      BuildContext context, bool isMobile, bool isTablet) {
    return InkWell(
      onTap: () {
        EarthAudioEngine.instance.playClick();
        widget.onNavigate?.call('command');
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            EarthLogo(
              size: isMobile ? 22 : 28,
              showGlow: true,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EARTH',
                    style: TextStyle(
                      fontSize: isTablet ? 15 : 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.5,
                      color: context.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'UNITED CORPORATIONS',
                    style: TextStyle(
                      fontSize: isTablet ? 7.5 : 8.5,
                      fontWeight: FontWeight.w600,
                      color: context.mutedColor,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- GAME CLOCK TICKER ---
  Widget _buildGameClockPill(BuildContext context, YearAndDay clockRes,
      String timeStr, bool isMobile) {
    return Tooltip(
      message: 'Game Clock (1s real = 1m game) · Click for Daily Briefing',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: () {
          EarthAudioEngine.instance.playClick();
          showDailyBriefingDialog(
            context,
            api: const EarthApi(),
            onNavigate: widget.onNavigate ?? (_) {},
          );
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: context.primaryColor.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Text(
            isMobile
                ? 'Y${clockRes.year} · D${clockRes.dayOfYear} · $timeStr'
                : 'YEAR ${clockRes.year}   DAY ${clockRes.dayOfYear}   $timeStr',
            style: TextStyle(
              fontSize: isMobile ? 9.5 : 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: context.mutedColor,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // --- RESOURCE BAR WITH SHADERMASK FADE ---
  Widget _buildResourceBar(BuildContext context, String credits,
      List<_HudResource> resources, bool isMobile) {
    final scrollChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInteractiveResourceChip(
          context: context,
          icon: Icons.account_balance_wallet_outlined,
          label: 'Credits',
          value: '$credits C',
          color: EarthResourceColors.credits,
          net: 0,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('finance');
          },
          isMobile: isMobile,
        ),
        for (final resource in resources) ...[
          SizedBox(width: isMobile ? 6 : 10),
          _buildInteractiveResourceChip(
            context: context,
            icon: resource.icon,
            label: resource.label,
            value: resource.value,
            color: resource.color,
            net: resource.net,
            onTap: () {
              EarthAudioEngine.instance.playClick();
              widget.onNavigate?.call(resource.targetSection);
            },
            isMobile: isMobile,
          ),
        ],
      ],
    );

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.02, 0.98, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(child: scrollChild),
        ),
      ),
    );
  }

  Widget _buildInteractiveResourceChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double net,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    final netStr = net == 0
        ? ''
        : ' (${net > 0 ? '+' : ''}${net.toStringAsFixed(1)}/d)';
    final tooltipText = '$label: $value$netStr';

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 5 : 7,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: net < 0
                  ? context.errorColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: isMobile ? 11 : 13, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 9.5 : 11,
                  fontWeight: FontWeight.w700,
                  color: context.inkColor,
                  letterSpacing: 0.8,
                ),
              ),
              if (net != 0) ...[
                const SizedBox(width: 3),
                Text(
                  net > 0 ? '▲' : '▼',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    color: net > 0 ? context.successColor : context.errorColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- LIVE TELEMETRY STATUS PILL ---
  Widget _buildLiveTelemetryPill(
      BuildContext context, LiveConnectionStatus status, {bool isMobile = false}) {
    return Tooltip(
      message: '${status.label}\n${status.description}',
      waitDuration: const Duration(milliseconds: 150),
      child: InkWell(
        key: const Key('hud-live-connection-status'),
        onTap: () {
          EarthAudioEngine.instance.playClick();
          if (status != LiveConnectionStatus.live) {
            widget.onReconnect?.call();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 6 : 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: status.color.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: status.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: status.color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                status.shortLabel,
                style: TextStyle(
                  color: status.color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ALERTS DROPDOWN MENU ---
  Widget _buildAlertsMenu(BuildContext context, LiveConnectionStatus status) {
    final unreadTotal = widget.unreadNotifications + widget.unreadCommMessages;

    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      color: context.surfaceColor,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(
          color: context.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      onSelected: (value) {
        EarthAudioEngine.instance.playClick();
        if (value == 'notifications') {
          widget.onNavigate?.call('notifications');
        } else if (value == 'messages') {
          widget.onCommLink?.call();
        } else if (value == 'social') {
          widget.onNavigate?.call('projects');
        }
      },
      itemBuilder: (context) => [
        _menuItem(
          context,
          'notifications',
          Icons.notifications_none_outlined,
          'Notifications',
          trailing: widget.unreadNotifications > 0
              ? '${widget.unreadNotifications}'
              : null,
        ),
        _menuItem(
          context,
          'messages',
          Icons.settings_input_antenna,
          'Messages',
          trailing: widget.unreadCommMessages > 0
              ? '${widget.unreadCommMessages}'
              : null,
        ),
        _menuItem(
          context,
          'social',
          Icons.assignment_turned_in_outlined,
          'Invitations',
        ),
      ],
      child: Tooltip(
        message: 'Alerts & Communications ($unreadTotal unread)',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_none_outlined,
                size: 21,
                color: unreadTotal > 0 ? context.primaryColor : context.mutedColor,
              ),
              if (unreadTotal > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints:
                        const BoxConstraints(minWidth: 15, minHeight: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: context.primaryColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      '$unreadTotal',
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
    );
  }

  // --- EXECUTIVE PROFILE MENU ---
  Widget _buildExecutiveProfileMenu(
    BuildContext context, {
    required String name,
    required String initials,
    required int standing,
    required String city,
    required bool isMobile,
  }) {
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 270),
      color: context.surfaceColor,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(
          color: context.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      onSelected: (value) {
        EarthAudioEngine.instance.playClick();
        if (value == 'life') {
          widget.onNavigate?.call('life');
        } else if (value == 'security') {
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
          value: 'life',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  color: context.inkColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Citizen of $city · Standing $standing',
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.mutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        _menuItem(
          context,
          'security',
          Icons.shield_outlined,
          'Security & MFA',
        ),
        _menuItem(
          context,
          'theme',
          Icons.palette_outlined,
          'Theme Suite',
        ),
        _menuItem(
          context,
          'audio',
          EarthAudioEngine.instance.isMuted ? Icons.volume_off : Icons.volume_up,
          EarthAudioEngine.instance.isMuted ? 'Enable Audio' : 'Mute Audio',
        ),
        _menuItem(
          context,
          'onboarding',
          Icons.school_outlined,
          'Onboarding',
        ),
        const PopupMenuDivider(),
        _menuItem(
          context,
          'logout',
          Icons.logout,
          'Sign Out',
          color: context.errorColor,
        ),
      ],
      child: Tooltip(
        message: '$name · Standing $standing · Account Menu',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.primaryColor.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      context.primaryColor.withValues(alpha: 0.8),
                      context.secondaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 5),
                Text(
                  '$standing',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.primaryColor,
                  ),
                ),
                const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    Color? color,
    String? trailing,
  }) {
    final itemColor = color ?? context.mutedColor;
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: itemColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w500,
                color: itemColor,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: context.primaryColor,
              ),
            ),
        ],
      ),
    );
  }

  String _extractInitials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final p1 = parts[0].isNotEmpty ? parts[0][0] : '';
      final p2 = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$p1$p2'.toUpperCase();
    } else if (fullName.isNotEmpty) {
      return fullName.substring(0, fullName.length.clamp(1, 2)).toUpperCase();
    }
    return 'EX';
  }
}

