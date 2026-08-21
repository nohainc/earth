import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class Sidebar extends StatefulWidget {
  final EarthState state;
  final String selectedSection;
  final ValueChanged<String> onNavigate;
  final bool busy;
  final bool canAdvanceDay;
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
    this.onAdvanceDay,
    this.onLogout,
    this.onSecurity,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  int _expandedGroup = 0;

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
    const groups = [
      ['command', 'briefing', 'messages'],
      [
        'business',
        'machines',
        'contracts',
        'market',
        'finance',
        'technology',
        'patents'
      ],
      ['corporation', 'city', 'civic', 'public-finance', 'civic-rankings'],
      ['life', 'dynasty', 'succession', 'history'],
    ];
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].contains(section)) return index;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isCorporationMember = widget.state.membership?['corporation_id'] != null;
    final corporation = widget.state.institutions['corporation'];
    final city = widget.state.institutions['city'];
    final corporationName = isCorporationMember && corporation is Map
        ? corporation['name']?.toString() ?? 'Corporation'
        : 'Corporation';
    final cityName = isCorporationMember && city is Map
        ? city['name']?.toString() ?? 'City & Services'
        : 'City & Services';
    final groups = [
      (
        'NOW',
        [
          ('command', 'Command Center', Icons.dashboard_outlined),
          ('briefing', 'Daily Priorities', Icons.today_outlined),
          ('messages', 'Messages', Icons.settings_input_antenna),
        ]
      ),
      (
        'BUSINESS',
        [
          ('business', 'Businesses & Operations', Icons.storefront_outlined),
          (
            'machines',
            'Machines & Production',
            Icons.precision_manufacturing_outlined
          ),
          ('contracts', 'Contracts & Revenue', Icons.handshake_outlined),
          ('market', 'Trade & Supplies', Icons.swap_horiz),
          (
            'finance',
            'Personal Finance',
            Icons.account_balance_wallet_outlined
          ),
          ('technology', 'Research & Technology', Icons.biotech_outlined),
          ('patents', 'Patents & Licensing', Icons.assignment_outlined),
        ]
      ),
      (
        'CIVIC',
        [
          ('corporation', corporationName, Icons.account_balance_outlined),
          if (isCorporationMember)
            ('city', cityName, Icons.location_city_outlined),
          ('civic', 'Earth Rules', Icons.public_outlined),
          (
            'public-finance',
            'Public Finance',
            Icons.account_balance_wallet_outlined
          ),
          ('civic-rankings', 'Rankings', Icons.leaderboard_outlined),
        ]
      ),
      (
        'LIFE',
        [
          ('life', 'Life & Legacy', Icons.hourglass_empty_outlined),
          ('dynasty', 'Family & Dynasty', Icons.account_tree_outlined),
          ('succession', 'Succession & Estate', Icons.fork_right_outlined),
          ('history', 'Historical Archive', Icons.history_outlined),
        ]
      ),
    ];

    return Container(
      width: 224,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. NAVIGATION MENU ITEMS
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int groupIdx = 0;
                      groupIdx < groups.length;
                      groupIdx++) ...[
                    InkWell(
                      onTap: () => setState(() => _expandedGroup =
                          _expandedGroup == groupIdx ? -1 : groupIdx),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 8,
                          top: groupIdx == 0 ? 0 : 10,
                          bottom: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(groups[groupIdx].$1,
                                    style: EarthTypography.menuGroup)),
                            Icon(
                              _expandedGroup == groupIdx
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: mutedColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: _expandedGroup == groupIdx
                          ? Column(
                              children: [
                                for (final item in groups[groupIdx].$2)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: TextButton(
                                        onPressed: () =>
                                            widget.onNavigate(item.$1),
                                        style: TextButton.styleFrom(
                                          splashFactory: NoSplash.splashFactory,
                                          enableFeedback: false,
                                          foregroundColor: violetColor,
                                          backgroundColor:
                                              item.$1 == widget.selectedSection
                                                  ? violetColor.withValues(
                                                      alpha: .16)
                                                  : Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          alignment: Alignment.centerLeft,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(item.$3,
                                                size: 16,
                                                color: item.$1 ==
                                                        widget.selectedSection
                                                    ? inkColor
                                                    : mutedColor),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                item.$2,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: EarthTypography.menu
                                                    .copyWith(
                                                  color: item.$1 ==
                                                          widget.selectedSection
                                                      ? inkColor
                                                      : mutedColor,
                                                  fontWeight: item.$1 ==
                                                          widget.selectedSection
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 2. FOOTER ADVANCE DAY (IF APPLICABLE)
          if (widget.canAdvanceDay) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1, thickness: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onAdvanceDay,
                icon: const Icon(Icons.fast_forward, size: 14),
                label: const Text('ADVANCE DAY',
                    style: TextStyle(fontSize: 10.5, letterSpacing: 1.3)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: violetColor,
                  side: const BorderSide(color: violetColor),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
