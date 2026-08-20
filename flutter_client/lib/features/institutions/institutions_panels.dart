import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'institutions_dialogs.dart';

class InstitutionsCapacityPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const InstitutionsCapacityPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['city'] is Map<String, dynamic>
        ? (state.institutions['city'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final cityId = city['id']?.toString() ?? 'CITY-0084';
    final cityName =
        (city['name']?.toString() ?? 'NEW CARTHAGE').toUpperCase();
    final residents = asIntOr(city['residents'], 100);
    final housingCap = asIntOr(city['housing_capacity'], 120);
    final energyCap = asIntOr(city['energy_capacity'], 200);

    final corp = state.institutions['corporation'] is Map<String, dynamic>
        ? (state.institutions['corporation'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final corporationId = corp['id']?.toString() ?? 'CORP-001';
    final corpName =
        (corp['name']?.toString() ?? 'CARTHAGE DYNAMICS').toUpperCase();
    final corpMembers = asIntOr(corp['member_count'], 42);
    final corpVersion = corp['constitution_version'] ?? 1;

    final isCityResident = state.membership?['city_id'] != null;
    final isCorpMember = state.membership?['corporation_id'] != null;

    final housingRatio =
        formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio =
        formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);

    return EarthPanel(
      key: panelKey,
      title: 'INSTITUTIONS / CITY & CORP',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Municipal & Corporate Institutions: Legal entities established under the Planetary Constitution to manage collective urban infrastructure and private commercial enterprises.\n\n• Municipal Operations:\n  - Residency: Citizens affiliated with a city gain access to subsidized public services and municipal voting.\n  - Housing & Energy Capacity: Physical limits on municipal residency and industrial manufacturing.\n  - Service Pressure Ratios: Real-time telemetry monitoring municipal infrastructure load across housing, power, connectivity, and health.\n\n• Corporate Enterprises:\n  - Limited Liability Charters: Registered corporate entities providing shared commercial treasury funds and specialized manufacturing capabilities.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CITY ADMINISTRATION COCKPIT CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cyanAccentColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_city_outlined,
                          size: 20, color: cyanAccentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'CITY: $cityName ($cityId)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isCityResident
                                          ? cyanAccentColor
                                          : mutedColor)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: (isCityResident
                                            ? cyanAccentColor
                                            : mutedColor)
                                        .withValues(alpha: .35),
                                  ),
                                ),
                                child: Text(
                                  isCityResident ? 'RESIDENT' : 'NON-RESIDENT',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color: isCityResident
                                        ? cyanAccentColor
                                        : mutedColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$residents residents · Housing cap: $housingCap · Energy cap: $energyCap',
                            style: const TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Service Pressure Gauges Box
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .03),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Service pressure: Housing $housingRatio · Energy $energyRatio · Connect $connectRatio · Health $healthRatio',
                    style: const TextStyle(
                      color: inkColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // City Action Buttons Hub
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isCityResident
                            ? Colors.orangeAccent
                            : cyanAccentColor,
                        side: BorderSide(
                          color: (isCityResident
                                  ? Colors.orangeAccent
                                  : cyanAccentColor)
                              .withValues(alpha: .35),
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => isCityResident
                              ? const EarthApi().leaveCity(cityId: cityId)
                              : const EarthApi().joinCity(cityId: cityId)),
                      child: Text(
                        isCityResident ? 'LEAVE CITY' : 'JOIN CITY',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: inkColor,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .setCityBudget('maintenance', cityId: cityId)),
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 14),
                      label: const Text(
                        'PROPOSE BUDGET',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: violetColor,
                        side: BorderSide(
                            color: violetColor.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => showTaxCharterDialog(context, action, cityId),
                      icon: const Icon(Icons.receipt_long_outlined, size: 14),
                      label: const Text(
                        'TAX CHARTER',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (state.communities.isNotEmpty)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cyanAccentColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: busy
                            ? null
                            : () => showFormationComposer(
                                  context,
                                  action,
                                  city: true,
                                  communityId: (state.communities.first
                                      as Map<String, dynamic>)['id'] as String,
                                ),
                        icon: const Icon(Icons.add_business_outlined, size: 14),
                        label: const Text(
                          'FORM CITY',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. CORPORATION ENTERPRISE COCKPIT CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.domain_outlined,
                          size: 20, color: violetColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'CORPORATION: $corpName ($corporationId)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isCorpMember
                                          ? violetColor
                                          : mutedColor)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: (isCorpMember
                                            ? violetColor
                                            : mutedColor)
                                        .withValues(alpha: .35),
                                  ),
                                ),
                                child: Text(
                                  isCorpMember ? 'MEMBER' : 'INDEPENDENT',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color: isCorpMember
                                        ? violetColor
                                        : mutedColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$corpMembers members · Constitution v$corpVersion · Status: ${isCorpMember ? 'MEMBER' : 'INDEPENDENT'}',
                            style: const TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Corporate Action Buttons Hub
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isCorpMember
                            ? Colors.orangeAccent
                            : violetColor,
                        side: BorderSide(
                          color: (isCorpMember
                                  ? Colors.orangeAccent
                                  : violetColor)
                              .withValues(alpha: .35),
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => isCorpMember
                              ? const EarthApi().leaveCorporation(
                                  corporationId: corporationId)
                              : const EarthApi().joinCorporation(
                                  corporationId: corporationId)),
                      child: Text(
                        isCorpMember ? 'LEAVE CORP' : 'JOIN CORP',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyanAccentColor,
                        side: BorderSide(
                            color: cyanAccentColor.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .spendCorporationTreasury(100,
                                  corporationId: corporationId)),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text(
                        'FUND SERVICES · 100 C',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: BorderSide(
                            color: Colors.tealAccent.withValues(alpha: .35)),
                      ),
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .contributeCorporation(100,
                                  corporationId: corporationId)),
                      icon: const Icon(Icons.savings_outlined, size: 14),
                      label: const Text(
                        'CONTRIBUTE · 100 C',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isCityResident)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: violetColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: busy
                            ? null
                            : () => showFormationComposer(
                                  context,
                                  action,
                                  city: false,
                                  cityId: cityId,
                                ),
                        icon: const Icon(Icons.corporate_fare_outlined,
                            size: 14),
                        label: const Text(
                          'FORM CORP',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CommunitiesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CommunitiesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final communities = state.communities;
    return EarthPanel(
      title: 'COMMUNITIES / SHARED LIFE',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Civic Communities & Cooperatives: Grassroots voluntary associations formed by citizens for collective mutual aid, cultural affinity, and shared municipal governance.\n\n• Membership & Contributions:\n  - JOIN / LEAVE: Free association allowing citizens to participate in community governance and welfare dividends.\n  - CONTRIBUTE: Voluntary treasury contributions funding local public projects and communal resources.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${communities.length} registered communities',
                  style: const TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cyanAccentColor,
                  side: BorderSide(
                      color: cyanAccentColor.withValues(alpha: .35)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: busy
                    ? null
                    : () => showCommunityComposer(context, action),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('FOUND COMMUNITY',
                    style:
                        TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (communities.isEmpty)
            const Text('No communities registered yet.',
                style: TextStyle(color: mutedColor, fontSize: 11))
          else
            ...communities.take(4).map((raw) {
              final community = raw as Map<String, dynamic>;
              final id = community['id']?.toString() ?? 'COM-001';
              final name = community['name']?.toString() ?? 'Community';
              final status =
                  (community['status']?.toString() ?? 'active').toUpperCase();
              final members = asIntOr(community['member_count'], 12);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.groups_outlined,
                              size: 15, color: Colors.tealAccent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$name ($id)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cyanAccentColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: cyanAccentColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: cyanAccentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$members active members',
                      style: const TextStyle(fontSize: 10.5, color: mutedColor),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: cyanAccentColor,
                            side: BorderSide(
                                color: cyanAccentColor.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().joinCommunity(id)),
                          child: const Text('JOIN',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.orangeAccent,
                            side: BorderSide(
                                color:
                                    Colors.orangeAccent.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().leaveCommunity(id)),
                          child: const Text('LEAVE',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: violetColor,
                            side: BorderSide(
                                color: violetColor.withValues(alpha: .3)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => showCommunityContributionDialog(
                                  context, action, id),
                          child: const Text('CONTRIBUTE',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
