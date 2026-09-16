import 'package:flutter/material.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/navigation_registry.dart';
import '../../core/onboarding_controller.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../onboarding/onboarding_welcome_dialog.dart';
import 'theme_customizer_dialog.dart';

class Sidebar extends StatefulWidget {
  final EarthState state;
  final String selectedSection;
  final ValueChanged<String> onNavigate;
  final bool busy;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;
  final int unreadNotifications;
  final int unreadCommMessages;
  final bool isSlim;

  const Sidebar({
    super.key,
    required this.state,
    this.selectedSection = 'command',
    required this.onNavigate,
    this.busy = false,
    this.onLogout,
    this.onSecurity,
    this.unreadNotifications = 0,
    this.unreadCommMessages = 0,
    this.isSlim = false,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  int _expandedGroup = 0;

  @override
  void initState() {
    super.initState();
    final group = NavigationRegistry.groupIndexForSection(widget.selectedSection);
    _expandedGroup = group != -1 ? group : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = NavigationRegistry.groupIndexForSection(widget.selectedSection);
    if (group != -1) {
      _expandedGroup = group;
    }
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSection != widget.selectedSection) {
      final group =
          NavigationRegistry.groupIndexForSection(widget.selectedSection);
      if (group != -1) {
        _expandedGroup = group;
      }
    }
  }

  void _toggleGroup(int groupIdx) {
    EarthAudioEngine.instance.playClick();
    setState(() {
      _expandedGroup = _expandedGroup == groupIdx ? -1 : groupIdx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      (
        NavigationGroup.command.displayName,
        NavigationGroup.command.icon,
        NavigationRegistry.itemsForGroup(NavigationGroup.command, widget.state),
      ),
      (
        NavigationGroup.house.displayName,
        NavigationGroup.house.icon,
        NavigationRegistry.itemsForGroup(NavigationGroup.house, widget.state),
      ),
      (
        NavigationGroup.economy.displayName,
        NavigationGroup.economy.icon,
        NavigationRegistry.itemsForGroup(NavigationGroup.economy, widget.state),
      ),
      (
        NavigationGroup.society.displayName,
        NavigationGroup.society.icon,
        NavigationRegistry.itemsForGroup(NavigationGroup.society, widget.state),
      ),
      (
        NavigationGroup.world.displayName,
        NavigationGroup.world.icon,
        NavigationRegistry.itemsForGroup(NavigationGroup.world, widget.state),
      ),
    ];

    if (widget.isSlim) {
      return _buildSlimSidebar(context, groups);
    }

    final humanName = (widget.state.human['name'] ??
            widget.state.human['display_name'] ??
            'Citizen')
        .toString()
        .trim();
    final rawHouse = (widget.state.life['houseName'] ??
            widget.state.human['house_name'] ??
            widget.state.human['houseName'] ??
            '')
        .toString()
        .trim();
    final houseDisplay = rawHouse.isNotEmpty
        ? rawHouse.replaceFirst(
            RegExp(r'^house\s+(of\s+)?', caseSensitive: false), '')
        : 'Independent';

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          context.primaryColor.withValues(alpha: 0.04),
          context.canvasColor,
        ),
        border: Border(
          right: BorderSide(
            color: context.primaryColor.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. SCROLLABLE NAVIGATION LIST
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int groupIdx = 0;
                      groupIdx < groups.length;
                      groupIdx++) ...[
                    // GROUP HEADER
                    _buildGroupHeader(
                      context,
                      title: groups[groupIdx].$1,
                      icon: groups[groupIdx].$2,
                      isExpanded: _expandedGroup == groupIdx,
                      onTap: () => _toggleGroup(groupIdx),
                      isFirst: groupIdx == 0,
                    ),

                    // EXPANDABLE ITEMS LIST
                    if (_expandedGroup == groupIdx)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Column(
                          children: [
                            for (final item in groups[groupIdx].$3)
                              _buildNavItem(
                                context,
                                sectionKey: item.id,
                                label: item.getLabel(widget.state),
                                icon: item.icon,
                                badge: null,
                                isSelected:
                                    item.id == widget.selectedSection ||
                                        item.canonicalRoute ==
                                            widget.selectedSection ||
                                        item.aliases
                                            .contains(widget.selectedSection),
                                onSelect: () {
                                  EarthAudioEngine.instance.playClick();
                                  widget.onNavigate(item.canonicalRoute);
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // 2. SIDEBAR FOOTER / PROFILE MENU
          _buildSidebarFooter(
            context,
            humanName: humanName,
            houseName: houseDisplay,
          ),
        ],
      ),
    );
  }

  // --- GROUP HEADER WIDGET ---
  Widget _buildGroupHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onTap,
    required bool isFirst,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 8, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            splashFactory: NoSplash.splashFactory,
            enableFeedback: false,
            foregroundColor:
                isExpanded ? context.primaryColor : context.mutedColor,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: isExpanded
                    ? context.primaryColor
                    : context.mutedColor.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color:
                        isExpanded ? context.primaryColor : context.mutedColor,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: context.mutedColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String sectionKey,
    required String label,
    required IconData icon,
    required String? badge,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: Semantics(
          button: true,
          label: label,
          selected: isSelected,
          child: TextButton(
            onPressed: onSelect,
            style: TextButton.styleFrom(
              splashFactory: NoSplash.splashFactory,
              enableFeedback: false,
              foregroundColor: context.primaryColor,
              backgroundColor: isSelected
                  ? context.primaryColor.withValues(alpha: 0.14)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: isSelected
                    ? BorderSide(
                        color: context.primaryColor.withValues(alpha: 0.32),
                        width: 0.8,
                      )
                    : BorderSide.none,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 10,
                  child: isSelected
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 3.2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: context.primaryColor,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: context.primaryColor
                                      .withValues(alpha: 0.65),
                                  blurRadius: 6,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? context.primaryColor
                      : context.mutedColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? context.inkColor : context.mutedColor,
                      letterSpacing: isSelected ? 0.2 : 0.0,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(
    BuildContext context, {
    required String humanName,
    required String houseName,
  }) {
    final isAccountSelected = widget.selectedSection == 'account';
    final initial = humanName.isNotEmpty ? humanName[0].toUpperCase() : 'C';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.canvasColor.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
            color: context.primaryColor.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. UNIFIED USER PROFILE BUTTON (Navigates to Account & Preferences)
          Material(
            color: isAccountSelected
                ? context.primaryColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                EarthAudioEngine.instance.playClick();
                widget.onNavigate('account');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isAccountSelected
                      ? Border.all(
                          color: context.primaryColor.withValues(alpha: 0.32),
                          width: 0.8,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.primaryColor.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: context.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        humanName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isAccountSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isAccountSelected
                              ? context.inkColor
                              : context.inkColor.withValues(alpha: 0.9),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: isAccountSelected
                          ? context.primaryColor
                          : context.mutedColor.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // 2. QUICK ACTION BAR (Appearance · Audio · Onboarding · Logout)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Appearance / Theme
              IconButton(
                icon: const Icon(Icons.palette_outlined, size: 16),
                tooltip: 'Appearance Suite',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                color: context.mutedColor,
                onPressed: () {
                  EarthAudioEngine.instance.playClick();
                  showThemeCustomizerDialog(context);
                },
              ),
              // Audio Toggle
              IconButton(
                icon: Icon(
                  EarthAudioEngine.instance.isMuted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  size: 16,
                ),
                tooltip: EarthAudioEngine.instance.isMuted
                    ? 'Enable Audio'
                    : 'Mute Audio',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                color: EarthAudioEngine.instance.isMuted
                    ? context.warningColor
                    : context.mutedColor,
                onPressed: () {
                  setState(() {
                    EarthAudioEngine.instance.toggleMute();
                    if (!EarthAudioEngine.instance.isMuted) {
                      EarthAudioEngine.instance.playClick();
                    }
                  });
                },
              ),
              // Guide & Onboarding
              IconButton(
                icon: const Icon(Icons.school_outlined, size: 16),
                tooltip: 'Guide & Onboarding',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                color: context.mutedColor,
                onPressed: () {
                  EarthAudioEngine.instance.playClick();
                  OnboardingController.instance.setDismissed(false);
                  showOnboardingWelcomeDialog(
                    context,
                    onNavigate: widget.onNavigate,
                  );
                },
              ),
              // Logout
              if (widget.onLogout != null)
                IconButton(
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  tooltip: 'Sign Out',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 30),
                  color: context.mutedColor,
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    widget.onLogout?.call();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlimSidebar(
    BuildContext context,
    List<(String, IconData, List<NavigationItem>)> groups,
  ) {
    final isAccountSelected = widget.selectedSection == 'account';

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          context.primaryColor.withValues(alpha: 0.04),
          context.canvasColor,
        ),
        border: Border(
          right: BorderSide(
            color: context.primaryColor.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  for (int g = 0; g < groups.length; g++) ...[
                    if (g > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: context.primaryColor.withValues(alpha: 0.1),
                        ),
                      ),
                    for (final item in groups[g].$3)
                      _buildSlimNavItem(
                        context,
                        sectionKey: item.id,
                        label: item.getLabel(widget.state),
                        icon: item.icon,
                        badge: null,
                        isSelected: item.id == widget.selectedSection ||
                            item.canonicalRoute == widget.selectedSection ||
                            item.aliases.contains(widget.selectedSection),
                        onSelect: () {
                          EarthAudioEngine.instance.playClick();
                          widget.onNavigate(item.canonicalRoute);
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Slim Footer
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.primaryColor.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 6),
                _buildSlimNavItem(
                  context,
                  sectionKey: 'account',
                  label: 'Account',
                  icon: Icons.manage_accounts_outlined,
                  badge: null,
                  isSelected: isAccountSelected,
                  onSelect: () {
                    EarthAudioEngine.instance.playClick();
                    widget.onNavigate('account');
                  },
                ),
                Tooltip(
                  message: 'Appearance Suite',
                  child: IconButton(
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    color: context.mutedColor,
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      showThemeCustomizerDialog(context);
                    },
                  ),
                ),
                Tooltip(
                  message: 'Guide & Onboarding',
                  child: IconButton(
                    icon: const Icon(Icons.school_outlined, size: 18),
                    color: context.mutedColor,
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      OnboardingController.instance.setDismissed(false);
                      showOnboardingWelcomeDialog(
                        context,
                        onNavigate: widget.onNavigate,
                      );
                    },
                  ),
                ),
                if (widget.onLogout != null)
                  Tooltip(
                    message: 'Sign Out',
                    child: IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      color: context.mutedColor,
                      onPressed: () {
                        EarthAudioEngine.instance.playClick();
                        widget.onLogout?.call();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlimNavItem(
    BuildContext context, {
    required String sectionKey,
    required String label,
    required IconData icon,
    required String? badge,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 300),
        child: Semantics(
          button: true,
          label: label,
          selected: isSelected,
          child: Material(
            color: isSelected
                ? context.primaryColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSelect,
              child: Container(
                width: 44,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(
                          color: context.primaryColor.withValues(alpha: 0.4),
                          width: 1.0,
                        )
                      : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? context.primaryColor
                          : context.mutedColor,
                    ),
                    if (badge != null)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
