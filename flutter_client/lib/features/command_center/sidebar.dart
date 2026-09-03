import 'package:flutter/material.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/format_helpers.dart';

class Sidebar extends StatefulWidget {
  final EarthState state;
  final Map<String, dynamic>? activeBusiness;
  final String selectedSection;
  final ValueChanged<String> onNavigate;
  final bool busy;
  final VoidCallback? onLogout;
  final VoidCallback? onSecurity;
  final int unreadNotifications;
  final int unreadCommMessages;

  const Sidebar({
    super.key,
    required this.state,
    this.selectedSection = 'command',
    required this.onNavigate,
    this.activeBusiness,
    this.busy = false,
    this.onLogout,
    this.onSecurity,
    this.unreadNotifications = 0,
    this.unreadCommMessages = 0,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  int _expandedGroup = 0;

  @override
  void initState() {
    super.initState();
    _expandedGroup = _groupForSection(widget.selectedSection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expandedGroup = _groupForSection(widget.selectedSection);
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSection != widget.selectedSection) {
      _expandedGroup = _groupForSection(widget.selectedSection);
    }
  }

  int _groupForSection(String section) {
    if (section.startsWith('my-community')) return 2;
    if (section == 'corporations') return 2;
    const groups = [
      ['command', 'briefing', 'messages', 'notifications'],
      [
        'business',
        'buildings',
        'contracts',
        'market',
        'technology',
      ],
      [
        'corporation',
        'my-corporation',
        'city',
        'my-community',
        'civic',
        'public-finance'
      ],
      ['life', 'house', 'dynasty', 'finance', 'account'],
      [
        'corporations',
        'communities',
        'civic-rankings',
        'pantheon',
        'history',
        'constitution'
      ],
    ];
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].contains(section)) return index;
    }
    return 0;
  }

  void _toggleGroup(int groupIdx) {
    EarthAudioEngine.instance.playClick();
    setState(() {
      _expandedGroup = _expandedGroup == groupIdx ? -1 : groupIdx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCorporationMember =
        widget.state.membership?['corporation_id'] != null;
    final corporation = widget.state.institutions['corporation'];
    final city = widget.state.institutions['city'];
    final corporationName = isCorporationMember && corporation is Map
        ? corporation['name']?.toString() ?? 'Corporations'
        : 'Corporations';
    final cityName = isCorporationMember && city is Map
        ? city['name']?.toString() ?? 'My City'
        : 'Cities';

    final myCommunities = widget.state.myCommunities;

    final fullUserName = (widget.state.human['name'] ??
            widget.state.human['display_name'] ??
            'Life')
        .toString();
    final nameTokens = fullUserName.trim().split(RegExp(r'\s+'));
    final userName = nameTokens.first;
    final userSurname = nameTokens.length > 1 ? nameTokens.last : '';
    
    final rawHouseName = (widget.state.life['houseName'] ??
            widget.state.life['dynastyName'] ??
            widget.state.human['house_name'] ??
            widget.state.human['houseName'] ??
            widget.state.human['dynasty_name'])
        ?.toString()
        .trim();

    final houseName = rawHouseName != null && rawHouseName.isNotEmpty
        ? rawHouseName
            .replaceFirst(RegExp(r'^house\s+(of\s+)?', caseSensitive: false), '')
            .replaceAll(RegExp(r'\bNoga\b', caseSensitive: false), 'Noha')
        : (userSurname.isNotEmpty ? userSurname : 'House');

    final unreadNotifs = widget.unreadNotifications > 0
        ? widget.unreadNotifications
        : asIntOr(widget.state.json['unreadNotifications'], 0);

    final unreadMsgs = widget.unreadCommMessages > 0
        ? widget.unreadCommMessages
        : asIntOr(widget.state.json['unreadMessages'], 0);

    final groups = [
      (
        'NOW',
        Icons.radar_rounded,
        [
          (
            'command',
            'Command Center',
            Icons.dashboard_outlined,
            null,
          ),
          (
            'briefing',
            'Daily Priorities',
            Icons.today_outlined,
            null,
          ),
          (
            'messages',
            'Messages',
            Icons.settings_input_antenna,
            unreadMsgs > 0 ? '$unreadMsgs' : null,
          ),
          (
            'notifications',
            'Notifications',
            Icons.notifications_none_outlined,
            unreadNotifs > 0 ? '$unreadNotifs' : null,
          ),
        ]
      ),
      (
        'ECONOMY',
        Icons.apartment_rounded,
        [
          (
            'business',
            'Business',
            Icons.storefront_outlined,
            null,
          ),
          (
            'buildings',
            'Buildings',
            Icons.domain_outlined,
            null,
          ),
          (
            'technology',
            'Research',
            Icons.biotech_outlined,
            null,
          ),
          (
            'market',
            'Market',
            Icons.swap_horiz_rounded,
            null,
          ),
        ]
      ),
      (
        'CIVIC',
        Icons.account_balance_rounded,
        [
          if (isCorporationMember)
            (
              'corporation',
              corporationName,
              Icons.account_balance_outlined,
              null,
            )
          else
            (
              'corporations',
              'Corporations',
              Icons.domain_outlined,
              null,
            ),
          (
            'city',
            cityName,
            Icons.location_city_outlined,
            null,
          ),
          for (final comm in myCommunities)
            (
              'my-community:${comm['id']}',
              comm['name']?.toString() ?? 'Community',
              Icons.diversity_3_outlined,
              null,
            ),
          (
            'civic',
            'Public Governance',
            Icons.public_outlined,
            null,
          ),
        ]
      ),
      (
        'LIFE',
        Icons.fingerprint_rounded,
        [
          (
            'life',
            userName.isNotEmpty == true ? userName : 'Life',
            Icons.person_outline_rounded,
            null,
          ),
          (
            'house',
            houseName.isNotEmpty == true ? houseName : 'House',
            Icons.shield_outlined,
            null,
          ),
          (
            'finance',
            'Finance',
            Icons.account_balance_wallet_outlined,
            null,
          ),
          (
            'account',
            'Account',
            Icons.manage_accounts_outlined,
            null,
          ),
        ]
      ),
      (
        'EARTH',
        Icons.public_rounded,
        [
          (
            'communities',
            'Communities',
            Icons.groups_outlined,
            null,
          ),
          (
            'civic-rankings',
            'Rankings',
            Icons.leaderboard_outlined,
            null,
          ),
          (
            'constitution',
            'Constitution',
            Icons.gavel_outlined,
            null,
          ),
          (
            'history',
            'Memorial',
            Icons.account_balance_outlined,
            null,
          ),
        ]
      ),
    ];

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
                                sectionKey: item.$1,
                                label: item.$2,
                                icon: item.$3,
                                badge: item.$4,
                                isSelected:
                                    item.$1 == widget.selectedSection,
                                onSelect: () {
                                  EarthAudioEngine.instance.playClick();
                                  widget.onNavigate(item.$1);
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
            foregroundColor: isExpanded ? context.primaryColor : context.mutedColor,
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
                    color: isExpanded
                        ? context.primaryColor
                        : context.mutedColor,
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
                // Fixed-width Indicator Slot (preserves exact horizontal alignment across all items)
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

                // Item Icon
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? context.primaryColor
                      : context.mutedColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),

                // Item Label
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? context.inkColor : context.mutedColor,
                      letterSpacing: isSelected ? 0.2 : 0.0,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
}
