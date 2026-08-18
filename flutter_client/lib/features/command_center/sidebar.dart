import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class Sidebar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    String cityName = 'City';
    final rawMembership = state.json['membership'];
    if (rawMembership is Map && rawMembership['city_id'] != null) {
      final rawInstitutions = state.json['institutions'];
      if (rawInstitutions is Map) {
        final city = rawInstitutions['city'];
        if (city is Map && city['name'] != null) {
          cityName = city['name'].toString();
        }
      }
    }

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
          ('business', 'Business', Icons.storefront_outlined),
          ('finance', 'Finance', Icons.account_balance_wallet_outlined),
        ]
      ),
      (
        'CIVIC & LAW',
        [
          ('civic', 'Civic', Icons.account_balance_outlined),
          ('city', cityName, Icons.location_city_outlined),
          ('contracts', 'Contracts', Icons.handshake_outlined),
        ]
      ),
      (
        'DEVELOPMENT',
        [
          ('map', 'Planetary Grid', Icons.public),
          ('dynasty', 'Dynasty Tree', Icons.account_tree_outlined),
          ('technology', 'Technology', Icons.biotech_outlined),
          ('life', 'Life & Legacy', Icons.hourglass_empty_outlined),
        ]
      ),
    ];

    return Container(
      width: 204,
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
                    Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        top: groupIdx == 0 ? 0 : 18,
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
                            onPressed: () => onNavigate(item.$1),
                            style: TextButton.styleFrom(
                              splashFactory: NoSplash.splashFactory,
                              enableFeedback: false,
                              foregroundColor: violetColor,
                              backgroundColor:
                                  item.$1 == selectedSection
                                      ? violetColor.withValues(alpha: .16)
                                      : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.$3,
                                  size: 16,
                                  color: item.$1 == selectedSection
                                      ? inkColor
                                      : mutedColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: item.$1 == selectedSection
                                          ? inkColor
                                          : mutedColor,
                                      fontSize: 12,
                                      letterSpacing: 1.3,
                                      fontWeight: item.$1 == selectedSection
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
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

          // 2. FOOTER ADVANCE DAY (IF APPLICABLE)
          if (canAdvanceDay) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1, thickness: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onAdvanceDay,
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
