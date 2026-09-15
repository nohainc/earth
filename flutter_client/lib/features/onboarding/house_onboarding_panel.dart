import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/house_onboarding_state.dart';

class HouseOnboardingPanel extends StatefulWidget {
  final EarthApi api;
  final ValueChanged<String> onNavigate;

  const HouseOnboardingPanel({
    super.key,
    required this.api,
    required this.onNavigate,
  });

  @override
  State<HouseOnboardingPanel> createState() => _HouseOnboardingPanelState();
}

class _HouseOnboardingPanelState extends State<HouseOnboardingPanel> {
  HouseOnboardingState? _state;
  Map<String, dynamic>? _entrySupport;
  Map<String, dynamic>? _catchUpTargets;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final response = await widget.api.getHouseOnboarding();
      if (!mounted) return;
      if (response['ok'] == false) {
        setState(
            () => _error = '${response['error'] ?? 'Onboarding unavailable'}');
        return;
      }
      setState(() => _state = HouseOnboardingState.fromJson(response));
      final entry = await widget.api.houseEntryOpportunities();
      if (mounted && entry['ok'] != false) {
        setState(() => _entrySupport = entry);
      }
      final targets = await widget.api.houseCatchUpTargets();
      if (mounted && targets['ok'] != false) {
        setState(() =>
            _catchUpTargets = targets['targets'] as Map<String, dynamic>?);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _claimEntrySupport() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await widget.api.claimHouseEntrySupport();
      if (!mounted) return;
      if (response['ok'] == false) {
        setState(() =>
            _error = '${response['error'] ?? 'Entry support unavailable'}');
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance({String? milestone, bool expertSkip = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await widget.api.advanceHouseOnboarding(
        milestone: milestone,
        expertSkip: expertSkip,
      );
      if (!mounted) return;
      if (response['ok'] == false) {
        setState(
            () => _error = '${response['error'] ?? 'Could not save progress'}');
      } else {
        if (!expertSkip && milestone != null) {
          const destinations = <String, String>{
            'review_house_assets': 'finance',
            'inspect_territory': 'command',
            'set_operating_policy': 'finance',
            'start_first_producer': 'corporation',
            'place_first_market_order': 'market',
            'discover_organization': 'corporations',
          };
          final destination = destinations[milestone];
          if (destination != null) widget.onNavigate(destination);
        }
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (state == null) return const SizedBox.shrink();
    if (state.status == 'COMPLETED' || state.status == 'SKIPPED') {
      return _buildCompact(context, state);
    }
    final next = state.recommendedNext;
    final progress = state.milestones.isEmpty
        ? 0.0
        : state.completedMilestones.length / state.milestones.length;
    return Container(
      key: const Key('house-onboarding-panel'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.explore_outlined,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('HOUSE ORIENTATION',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: .8))),
          Text('${state.completedMilestones.length}/${state.milestones.length}',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        if (next != null) ...[
          const SizedBox(height: 12),
          Text(next.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(next.description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              key: const Key('btn-house-onboarding-advance'),
              onPressed: _busy ? null : () => _advance(milestone: next.code),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('MARK READY'),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('btn-house-onboarding-skip'),
              onPressed: _busy ? null : () => _advance(expertSkip: true),
              child: const Text('EXPERT SKIP'),
            ),
          ]),
        ],
        if (_entrySupport != null) ...[
          const SizedBox(height: 12),
          _buildEntrySupport(context),
        ],
        if (_catchUpTargets != null) ...[
          const SizedBox(height: 12),
          _buildCatchUpTargets(context),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
    );
  }

  Widget _buildCompact(BuildContext context, HouseOnboardingState state) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          state.status == 'SKIPPED'
              ? 'HOUSE ORIENTATION SKIPPED'
              : 'HOUSE ORIENTATION COMPLETE',
          key: const Key('house-onboarding-complete'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );

  Widget _buildEntrySupport(BuildContext context) {
    final support = Map<String, dynamic>.from(
        (_entrySupport?['entrySupport'] as Map?) ?? const {});
    final eligible = support['eligible'] == true;
    final status = '${support['status'] ?? 'ELIGIBLE'}';
    final bundle = Map<String, dynamic>.from(
        (support['bundleDisplayUnits'] as Map?) ?? const {});
    return Container(
      key: const Key('house-entry-support'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: .35),
          borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.route_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LATE-ENTRY SUPPORT',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
          Text(status == 'CLAIMED'
              ? 'Resource support already claimed.'
              : 'A one-time resource bundle helps you find a sustainable niche. Credit and frontier technology are not included.'),
          if (eligible) ...[
            const SizedBox(height: 4),
            Text(
                bundle.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(' · '),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            OutlinedButton(
                key: const Key('btn-claim-entry-support'),
                onPressed: _busy ? null : _claimEntrySupport,
                child: const Text('CLAIM RESOURCE SUPPORT')),
          ],
        ])),
      ]),
    );
  }

  Widget _buildCatchUpTargets(BuildContext context) {
    final targets = _catchUpTargets!;
    final progress =
        Map<String, dynamic>.from((targets['progress'] as Map?) ?? const {});
    String pct(String key) =>
        '${((num.tryParse('${progress[key] ?? 0}') ?? 0) * 100).round()}%';
    final milestones = (targets['milestones'] as List?)
            ?.whereType<Map>()
            .map((milestone) => Map<String, dynamic>.from(milestone))
            .toList() ??
        const <Map<String, dynamic>>[];
    return Container(
      key: const Key('house-catch-up-targets'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: .35),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CATCH-UP TARGETS',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        Text(
            'Build a sustainable position by game day ${targets['targetGameDay'] ?? targets['target_game_day'] ?? '—'}. ${targets['complete'] == true ? 'Catch-up complete.' : 'Progress is measured from canonical world activity.'}'),
        const SizedBox(height: 4),
        Text(
            'Productive assets ${pct('FIRST_PRODUCTIVE_ASSET')} · market activity ${pct('FIRST_MARKET_ACTIVITY')} · organization access ${pct('FIRST_ORGANIZATION_RELATIONSHIP')}',
            style: Theme.of(context).textTheme.labelSmall),
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...milestones.map((milestone) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(milestone['achieved'] == true ? Icons.check_circle : Icons.radio_button_unchecked, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${milestone['title']}: ${milestone['description']}', style: Theme.of(context).textTheme.bodySmall)),
                ]),
              )),
        ],
      ]),
    );
  }
}
