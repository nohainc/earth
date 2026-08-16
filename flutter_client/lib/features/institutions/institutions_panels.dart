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
    final cityName = (city['name']?.toString() ?? 'NEW CARTHAGE').toUpperCase();
    final residents = city['residents'] ?? 100;
    final housingCap = city['housing_capacity'] ?? 120;
    final energyCap = city['energy_capacity'] ?? 200;

    final corp = state.institutions['corporation'] is Map<String, dynamic>
        ? (state.institutions['corporation'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final corporationId = corp['id']?.toString() ?? 'CORP-001';
    final corpName = (corp['name']?.toString() ?? 'CARTHAGE DYNAMICS').toUpperCase();
    final corpMembers = corp['member_count'] ?? 42;
    final corpVersion = corp['constitution_version'] ?? 1;

    final isCityResident = state.membership?['city_id'] != null;
    final isCorpMember = state.membership?['corporation_id'] != null;

    final housingRatio = formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio = formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);

    return EarthPanel(
      key: panelKey,
      title: 'INSTITUTIONS / CITY & CORP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City Section
          Text(
            'CITY: $cityName ($cityId)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '$residents residents · Housing cap: $housingCap · Energy cap: $energyCap',
            style: const TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            'Service pressure: Housing $housingRatio · Energy $energyRatio · Connect $connectRatio · Health $healthRatio',
            style: const TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => isCityResident
                        ? const EarthApi().leaveCity(cityId: cityId)
                        : const EarthApi().joinCity(cityId: cityId)),
                child: Text(isCityResident ? 'LEAVE CITY' : 'JOIN CITY'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi()
                        .setCityBudget('maintenance', cityId: cityId)),
                child: const Text('PROPOSE BUDGET'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showTaxCharterDialog(context, action, cityId),
                child: const Text('TAX CHARTER'),
              ),
              if (state.communities.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => showFormationComposer(
                            context,
                            action,
                            city: true,
                            communityId: (state.communities.first
                                as Map<String, dynamic>)['id'] as String,
                          ),
                  child: const Text('FORM CITY'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 10),

          // Corporation Section
          Text(
            'CORPORATION: $corpName ($corporationId)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '$corpMembers members · Constitution v$corpVersion · Status: ${isCorpMember ? 'MEMBER' : 'INDEPENDENT'}',
            style: const TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => isCorpMember
                        ? const EarthApi()
                            .leaveCorporation(corporationId: corporationId)
                        : const EarthApi()
                            .joinCorporation(corporationId: corporationId)),
                child: Text(isCorpMember ? 'LEAVE CORP' : 'JOIN CORP'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().spendCorporationTreasury(
                        100,
                        corporationId: corporationId)),
                child: const Text('FUND SERVICES · 100 C'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().contributeCorporation(100,
                        corporationId: corporationId)),
                child: const Text('CONTRIBUTE · 100 C'),
              ),
              if (isCityResident)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => showFormationComposer(
                            context,
                            action,
                            city: false,
                            cityId: cityId,
                          ),
                  child: const Text('FORM CORP'),
                ),
            ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${communities.length} registered communities',
                  style: const TextStyle(color: mutedColor, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showCommunityComposer(context, action),
                child: const Text('FOUND COMMUNITY'),
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
              final status = (community['status']?.toString() ?? 'active').toUpperCase();
              final members = (community['member_count'] as num?)?.toInt() ?? 12;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$name ($id)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(status, style: const TextStyle(fontSize: 9, color: mutedColor)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('$members active members',
                        style: const TextStyle(fontSize: 10, color: mutedColor)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi().joinCommunity(id)),
                          child: const Text('JOIN', style: TextStyle(fontSize: 10)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi().leaveCommunity(id)),
                          child: const Text('LEAVE', style: TextStyle(fontSize: 10)),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          ),
                          onPressed: busy
                              ? null
                              : () => showCommunityContributionDialog(context, action, id),
                          child: const Text('CONTRIBUTE', style: TextStyle(fontSize: 10)),
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
