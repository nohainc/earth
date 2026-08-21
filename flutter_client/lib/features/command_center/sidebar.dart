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
    if (['command', 'briefing', 'messages'].contains(section)) return 0;
    if (['business', 'contracts', 'finance', 'market'].contains(section)) return 1;
    if (['corporation', 'city', 'civic', 'life', 'dynasty'].contains(section)) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      (
        'OVERVIEW',
        [
          ('command', 'Command Center', Icons.dashboard_outlined),
          ('briefing', 'Daily Priorities', Icons.today_outlined),
          ('messages', 'Messages', Icons.settings_input_antenna),
        ]
      ),
      (
        'MANAGEMENT',
        [
          ('business', 'Businesses & Operations', Icons.storefront_outlined),
          ('contracts', 'Contracts & Revenue', Icons.handshake_outlined),
          (
            'finance',
            'Personal Finance',
            Icons.account_balance_wallet_outlined
          ),
          ('market', 'Trade & Supplies', Icons.swap_horiz),
        ]
      ),
      (
        'LIFE & SOCIETY',
        [
          ('corporation', 'Corporation', Icons.account_balance_outlined),
          ('city', 'City & Services', Icons.location_city_outlined),
          ('civic', 'Laws & Governance', Icons.account_balance_outlined),
          ('life', 'Life & Legacy', Icons.hourglass_empty_outlined),
          ('dynasty', 'Family & Dynasty', Icons.account_tree_outlined),
        ]
      ),
      (
        'DEVELOPMENT',
        [
          ('technology', 'Research & Technology', Icons.biotech_outlined),
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
                  for (int groupIdx = 0; groupIdx < groups.length; groupIdx++) ...[
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
                            Expanded(child: Text(groups[groupIdx].$1, style: EarthTypography.menuGroup)),
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
                                        onPressed: () => widget.onNavigate(item.$1),
                                        style: TextButton.styleFrom(
                                          splashFactory: NoSplash.splashFactory,
                                          enableFeedback: false,
                                          foregroundColor: violetColor,
                                          backgroundColor: item.$1 == widget.selectedSection
                                              ? violetColor.withValues(alpha: .16)
                                              : Colors.transparent,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          alignment: Alignment.centerLeft,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(item.$3, size: 16, color: item.$1 == widget.selectedSection ? inkColor : mutedColor),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                item.$2,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: EarthTypography.menu.copyWith(
                                                  color: item.$1 == widget.selectedSection ? inkColor : mutedColor,
                                                  fontWeight: item.$1 == widget.selectedSection ? FontWeight.w700 : FontWeight.w500,
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
