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
    final cityId = state.institutions['city']['id']?.toString() ?? 'CITY-0084';
    final corporationId =
        state.institutions['corporation']['id']?.toString() ?? 'CORP-001';

    return EarthPanel(
      key: panelKey,
      title: 'INSTITUTIONS / CAPACITY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'CITY  ${state.institutions['city']['residents']} residents  ·  housing ${state.institutions['city']['housing_capacity']}  ·  energy ${state.institutions['city']['energy_capacity']}'),
          const SizedBox(height: 6),
          Text(
            'SERVICE PRESSURE  housing ${formatPercent(state.world['serviceRatios']?['housing'])}  ·  energy ${formatPercent(state.world['serviceRatios']?['energy'])}  ·  connectivity ${formatPercent(state.world['serviceRatios']?['connectivity'])}  ·  health ${formatPercent(state.world['serviceRatios']?['health'])}',
            style: const TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 6),
          Text(
            'CITY QUALIFICATION  ${((state.world['cityQualification'] as Map<String, dynamic>?)?.values.every((value) => value == true) ?? false) ? 'QUALIFIED' : 'IN PROGRESS'}',
            style: const TextStyle(
                color: mutedColor, fontSize: 10, letterSpacing: .5),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => const EarthApi()
                    .setCityBudget('maintenance', cityId: cityId)),
            child: const Text('PROPOSE MAINTENANCE BUDGET'),
          ),
          const SizedBox(height: 8),
          Text(
              'CORPORATION  ${state.institutions['corporation']['member_count']} members  ·  constitution v${state.institutions['corporation']['constitution_version']}'),
          const SizedBox(height: 6),
          Text(
            'CORPORATION QUALIFICATION  ${((state.world['corporationQualification'] as Map<String, dynamic>?)?.values.every((value) => value == true) ?? false) ? 'QUALIFIED' : 'IN PROGRESS'}',
            style: const TextStyle(
                color: mutedColor, fontSize: 10, letterSpacing: .5),
          ),
          const SizedBox(height: 10),
          Text(
            state.membership?['corporation_id'] == null
                ? 'Independent membership · eligible to join'
                : 'Member since game day ${state.membership?['joined_game_day']}',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => state.membership?['corporation_id'] == null
                    ? const EarthApi()
                        .joinCorporation(corporationId: corporationId)
                    : const EarthApi()
                        .leaveCorporation(corporationId: corporationId)),
            child: Text(state.membership?['corporation_id'] == null
                ? 'JOIN CORPORATION'
                : 'LEAVE CORPORATION'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => state.membership?['city_id'] == null
                    ? const EarthApi().joinCity(cityId: cityId)
                    : const EarthApi().leaveCity(cityId: cityId)),
            child: Text(state.membership?['city_id'] == null
                ? 'JOIN CITY'
                : 'LEAVE CITY'),
          ),
          const SizedBox(height: 8),
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
              child: const Text('FORM CITY FROM COMMUNITY'),
            ),
          if (state.membership?['city_id'] != null)
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => showFormationComposer(
                        context,
                        action,
                        city: false,
                        cityId: state.membership?['city_id'] as String,
                      ),
              child: const Text('FORM CORPORATION'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => const EarthApi().spendCorporationTreasury(
                    100,
                    corporationId: corporationId)),
            child: const Text('FUND CITY SERVICES · 100 C'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => const EarthApi().contributeCorporation(100,
                    corporationId: corporationId)),
            child: const Text('CONTRIBUTE TO TREASURY · 100 C'),
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
    return EarthPanel(
      title: 'COMMUNITIES / SHARED LIFE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.communities.isEmpty)
            const Text('No communities registered yet.')
          else
            ...state.communities.take(5).map((raw) {
              final community = raw as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '${community['name']}  ·  ${community['status']}',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action(() => const EarthApi().createCommunity()),
                child: const Text('FOUND CARTHAGE MAKERS'),
              ),
              if (state.communities.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() {
                            final id = (state.communities.first
                                as Map<String, dynamic>)['id'] as String;
                            return const EarthApi()
                                .contributeToCommunity(id, 50);
                          }),
                  child: const Text('CONTRIBUTE 50 C'),
                ),
              if (state.communities.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() {
                            final id = (state.communities.first
                                as Map<String, dynamic>)['id'] as String;
                            return const EarthApi().joinCommunity(id);
                          }),
                  child: const Text('JOIN COMMUNITY'),
                ),
              if (state.communities.isNotEmpty)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() {
                            final id = (state.communities.first
                                as Map<String, dynamic>)['id'] as String;
                            return const EarthApi().leaveCommunity(id);
                          }),
                  child: const Text('LEAVE COMMUNITY'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
