import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../core/nano_markup_helper.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';

class CivicStatusPanel extends StatelessWidget {
  final EarthState state;

  const CivicStatusPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final human = state.human;
    final membership = state.membership;
    final city = state.institutions['city'];
    final cityMap = city is Map
        ? Map<String, dynamic>.from(city)
        : const <String, dynamic>{};
    final citizenship = membership?['status']?.toString() ??
        membership?['type']?.toString() ??
        'Independent citizen';
    final standing =
        human['standing'] ?? human['civic_standing'] ?? 'UNAVAILABLE';
    final voting =
        membership?['voting_eligible'] ?? membership?['votingEligible'] ?? true;
    final obligations = membership?['obligations']?.toString() ??
        'Review current laws and tax obligations';

    return EarthSection(
      title: 'CIVIC STATUS',
      showSurface: false,
      infoBulletPoints: const [
        'Your current place in the civic system: residency, standing, voting access, and obligations.',
        'These details explain what you can do in governance today.',
        'City services and detailed membership history remain on City & Services and your personal record.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'RESIDENCY',
                value:
                    cityMap['name']?.toString().toUpperCase() ?? 'INDEPENDENT',
                icon: Icons.location_city_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'CITIZENSHIP',
                value: citizenship.toUpperCase(),
                icon: Icons.badge_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'VOTING',
                value: voting == true ? 'ELIGIBLE' : 'RESTRICTED',
                icon: Icons.how_to_vote_outlined,
                accentColor: voting == true
                    ? context.successColor
                    : context.warningColor,
              ),
              EarthMetricTile(
                label: 'STANDING',
                value: standing.toString(),
                icon: Icons.trending_up_outlined,
                accentColor: context.warningColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingInline),
          Text(
            'Current obligation: $obligations',
            style: context.widgetFooterStyle,
          ),
        ],
      ),
    );
  }
}

class ActiveGovernanceRulePanel extends StatelessWidget {
  final EarthState state;
  final String institutionId;

  const ActiveGovernanceRulePanel(
      {super.key, required this.state, required this.institutionId});

  @override
  Widget build(BuildContext context) {
    final rules = ((state.governance['rules'] as List<dynamic>?) ?? const [])
        .where((raw) =>
            raw is Map &&
            raw['institution_id']?.toString() == institutionId &&
            raw['status']?.toString() == 'active')
        .toList();
    final rule =
        rules.isEmpty ? null : Map<String, dynamic>.from(rules.first as Map);
    final quorum =
        ((asDoubleOr(rule?['quorum_threshold'], 0.25)) * 100).round();
    final approval =
        ((asDoubleOr(rule?['approval_threshold'], 0.5)) * 100).round();

    return EarthSection(
      title: 'ACTIVE GOVERNANCE RULE',
      showSurface: false,
      infoBulletPoints: const [
        'Quorum is the minimum participation required for a valid vote.',
        'Approval is the share of decisive votes required for a proposal to pass.',
        'Approved proposals start automatically after daily settlement, or remain approved while city resources accumulate.',
      ],
      child: rule == null
          ? const EarthEmptyState(
              message: 'No active governance rule is configured for this city.',
              icon: Icons.rule_outlined)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${rule['name'] ?? 'City governance rule'} · Version ${rule['version'] ?? '—'}',
                    style: context.widgetTitleStyle),
                const SizedBox(height: 10),
                EarthMetricGrid(metrics: [
                  EarthMetricTile(
                      label: 'QUORUM',
                      value: '$quorum%',
                      icon: Icons.groups_outlined,
                      accentColor: context.primaryColor),
                  EarthMetricTile(
                      label: 'APPROVAL',
                      value: '$approval%',
                      icon: Icons.how_to_vote_outlined,
                      accentColor: context.secondaryColor),
                  EarthMetricTile(
                      label: 'VOTING PERIOD',
                      value: '${rule['voting_period_days'] ?? '—'} DAYS',
                      icon: Icons.schedule_outlined,
                      accentColor: context.primaryColor),
                  EarthMetricTile(
                      label: 'FUNDING WINDOW',
                      value: '7 DAYS',
                      icon: Icons.hourglass_bottom_outlined,
                      accentColor: context.warningColor),
                ]),
              ],
            ),
    );
  }
}

class CivicInfluencePanel extends StatelessWidget {
  final EarthState state;

  const CivicInfluencePanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const heldRoles = 0;
    final proposals =
        (state.governance['proposals'] as List<dynamic>?)?.length ?? 0;
    final communities = state.communities.length;

    return EarthSection(
      title: 'YOUR CIVIC INFLUENCE',
      showSurface: false,
      infoBulletPoints: const [
        'Influence grows through participation, public responsibility, and relationships.',
        'Voting, holding office, joining communities, and sponsoring proposals are different ways to shape the world.',
        'This is a direction for play, not a leaderboard.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose how you want to matter in public life.',
            style: context.widgetValueStyle,
          ),
          SizedBox(height: context.spacingControl),
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'OFFICES HELD',
                value: '$heldRoles',
                icon: Icons.account_balance_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'OPEN DECISIONS',
                value: '$proposals',
                icon: Icons.gavel_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'COMMUNITIES',
                value: '$communities',
                icon: Icons.groups_outlined,
                accentColor: context.primaryColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingInline),
          Text(
            'Possible paths: independent citizen · community leader · business-backed politician · city administrator · legal or planetary delegate.',
            style: context.widgetFooterStyle,
          ),
        ],
      ),
    );
  }
}

class TabbedProposalPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const TabbedProposalPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<TabbedProposalPanel> createState() => _TabbedProposalPanelState();
}

class _TabbedProposalPanelState extends State<TabbedProposalPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (mounted) setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _scopeFor(String? institutionId) {
    if (institutionId == null ||
        institutionId.isEmpty ||
        institutionId == 'OUC-001') {
      return 'WORLD';
    }
    final cityId = widget.state.institutions['city'] is Map
        ? (widget.state.institutions['city'] as Map)['id']?.toString()
        : null;
    if (institutionId == cityId ||
        institutionId.toUpperCase().startsWith('CITY-')) {
      return 'CITY';
    }
    return 'CORPORATION';
  }

  List<Map<String, dynamic>> _proposalsForScope(String scope) {
    final all =
        ((widget.state.governance['proposals'] as List<dynamic>?) ?? const []);
    final filtered = <Map<String, dynamic>>[];
    for (final raw in all) {
      if (raw is! Map) continue;
      final pInst = (raw['institution_id'] ?? raw['institutionId'])?.toString();
      final pScope = _scopeFor(pInst);
      if (pScope == scope) {
        filtered.add(Map<String, dynamic>.from(raw));
      }
    }
    // Sort by created_at / opens_at descending (newest first)
    filtered.sort((a, b) {
      final aTime = _createdAtMs(a);
      final bTime = _createdAtMs(b);
      return bTime.compareTo(aTime);
    });
    return filtered;
  }

  int _createdAtMs(Map<String, dynamic> p) {
    final createdAt = p['created_at'] ?? p['createdAt'];
    if (createdAt is num) return createdAt.toInt();
    if (createdAt != null) {
      final parsed = int.tryParse(createdAt.toString());
      if (parsed != null) return parsed;
      final date = DateTime.tryParse(createdAt.toString());
      if (date != null) return date.millisecondsSinceEpoch;
    }
    final opensAt = p['opens_at'] ?? p['opensAt'];
    if (opensAt is num) return opensAt.toInt();
    if (opensAt != null) {
      final parsed = int.tryParse(opensAt.toString());
      if (parsed != null) return parsed;
      final date = DateTime.tryParse(opensAt.toString());
      if (date != null) return date.millisecondsSinceEpoch;
    }
    // Fallback to game day for proposals without timestamps
    final day = asIntOr(p['opens_game_day'] ?? p['closes_game_day'], 0);
    return day * 86400000;
  }

  @override
  Widget build(BuildContext context) {
    final worldCount = _proposalsForScope('WORLD').length;
    final corpCount = _proposalsForScope('CORPORATION').length;
    final cityCount = _proposalsForScope('CITY').length;

    return EarthSection(
      title: 'PROPOSALS',
      showSurface: false,
      infoBulletPoints: const [
        'Proposals remain open until their configured voting deadline. The result is calculated automatically after the deadline.',
        'Quorum is the minimum participation required; approval is the percentage of decisive votes needed to pass.',
        'Passed proposals stay approved until daily settlement starts the action. The proposal then closes while construction or research continues separately.',
        'Stages: SCHEDULED → OPEN → APPROVED → ACTION STARTED → CLOSED.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScopeTabs(context, cityCount, corpCount, worldCount),
          SizedBox(height: context.spacingTitleOffset),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final scope = switch (_tabController.index) {
                0 => 'CITY',
                1 => 'CORPORATION',
                2 => 'WORLD',
                _ => 'CITY',
              };
              return _ProposalTabContent(
                key: ValueKey(scope),
                proposals: _proposalsForScope(scope),
                scopeLabel: scope,
                state: widget.state,
                busy: widget.busy,
                action: widget.action,
                now: _now,
                scopeFor: _scopeFor,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScopeTabs(
      BuildContext context, int cityCount, int corpCount, int worldCount) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.subtleBorderColor),
        ),
        child: Row(children: [
          _scopeTab(
              context, 0, 'CITY ($cityCount)', Icons.location_city_outlined),
          _scopeTab(context, 1, 'CORPORATION ($corpCount)',
              Icons.account_balance_outlined),
          _scopeTab(context, 2, 'WORLD ($worldCount)', Icons.public_outlined),
        ]),
      ),
    );
  }

  Widget _scopeTab(
      BuildContext context, int index, String label, IconData icon) {
    final selected = _tabController.index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _tabController.animateTo(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? context.primaryColor.withValues(alpha: .15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: context.primaryColor.withValues(alpha: .4))
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 14,
                  color: selected ? context.primaryColor : context.mutedColor),
              const SizedBox(width: 5),
              Text(label,
                  style: context.controlStyle.copyWith(
                      color: selected
                          ? context.primaryColor
                          : context.mutedColor)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProposalTabContent extends StatefulWidget {
  final List<Map<String, dynamic>> proposals;
  final String scopeLabel;
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final DateTime now;
  final String Function(String?) scopeFor;

  const _ProposalTabContent({
    super.key,
    required this.proposals,
    required this.scopeLabel,
    required this.state,
    required this.busy,
    required this.action,
    required this.now,
    required this.scopeFor,
  });

  @override
  State<_ProposalTabContent> createState() => _ProposalTabContentState();
}

class _ProposalTabContentState extends State<_ProposalTabContent> {
  static const _pageSize = 10;
  int _currentPage = 0;
  final Set<String> _expandedIds = <String>{};

  int get _totalPages =>
      (widget.proposals.length / _pageSize).ceil().clamp(1, 9999);

  List<Map<String, dynamic>> get _pageItems {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.proposals.length);
    if (start >= widget.proposals.length) return const [];
    return widget.proposals.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant _ProposalTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= _totalPages) {
      _currentPage = (_totalPages - 1).clamp(0, 9999);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules =
        ((widget.state.governance['rules'] as List<dynamic>?) ?? const [])
            .where((raw) => raw is Map && raw['status']?.toString() == 'active')
            .toList();
    final currentRule =
        rules.isEmpty ? null : Map<String, dynamic>.from(rules.first as Map);
    final ruleSummary = currentRule == null
        ? 'Common governance defaults apply: 25% quorum · 50% approval · 3-day vote · 7-day funding window.'
        : 'Current rule: ${asIntOr(asDoubleOr(currentRule['quorum_threshold'], .25) * 100, 25)}% quorum · ${asIntOr(asDoubleOr(currentRule['approval_threshold'], .5) * 100, 50)}% approval · ${currentRule['voting_period_days'] ?? '—'}-day vote · 7-day funding window.';

    if (widget.proposals.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRuleSummary(context, ruleSummary),
          const SizedBox(height: 12),
          const EarthEmptyState(
            message: 'No proposals in this category.',
            icon: Icons.how_to_vote_outlined,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRuleSummary(context, ruleSummary),
        const SizedBox(height: 12),
        for (final proposal in _pageItems) ...[
          _ProposalCard(
            proposal: proposal,
            state: widget.state,
            busy: widget.busy,
            action: widget.action,
            now: widget.now,
            isExpanded: _expandedIds.contains(proposal['id']?.toString()),
            onToggleExpand: () {
              final id = proposal['id']?.toString() ?? '';
              if (id.isEmpty) return;
              setState(() {
                if (_expandedIds.contains(id)) {
                  _expandedIds.remove(id);
                } else {
                  _expandedIds.add(id);
                }
              });
            },
            scopeFor: widget.scopeFor,
          ),
          SizedBox(height: context.spacingControl),
        ],
        if (_totalPages > 1) _buildPagination(context),
      ],
    );
  }

  Widget _buildRuleSummary(BuildContext context, String summary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.rule_outlined,
            size: context.iconSize, color: context.primaryColor),
        SizedBox(width: context.spacingInline),
        Expanded(child: Text(summary, style: context.widgetFooterStyle)),
      ],
    );
  }

  Widget _buildPagination(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed:
                _currentPage > 0 ? () => setState(() => _currentPage--) : null,
            icon: const Icon(Icons.chevron_left),
            color: context.primaryColor,
            tooltip: 'Previous page',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Page ${_currentPage + 1} of $_totalPages',
              style: context.controlStyle,
            ),
          ),
          IconButton(
            onPressed: _currentPage < _totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right),
            color: context.primaryColor,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final Map<String, dynamic> proposal;
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final DateTime now;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final String Function(String?) scopeFor;

  const _ProposalCard({
    required this.proposal,
    required this.state,
    required this.busy,
    required this.action,
    required this.now,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.scopeFor,
  });

  @override
  Widget build(BuildContext context) {
    final votes = Map<String, dynamic>.from(
        (proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final proposalId = proposal['id']?.toString() ?? '';
    final isPassed =
        proposal['outcome'] == 'passed' || proposal['status'] == 'passed';
    final executionStatus = (proposal['execution_status']?.toString() ??
            (isPassed ? 'ready' : 'pending'))
        .toLowerCase();
    final isAwaitingFunding = executionStatus == 'awaiting_funding';
    final isExpiredUnfunded = executionStatus == 'expired_unfunded';
    final isStarted = executionStatus == 'started';
    final isExecuted = executionStatus == 'executed';
    final outcome = proposal['outcome']?.toString().toLowerCase() ?? 'pending';
    final isApproved =
        proposal['status']?.toString().toLowerCase() == 'approved';
    final isScheduled =
        proposal['status']?.toString().toLowerCase() == 'scheduled';
    final badgeLabel = isStarted
        ? 'ACTION STARTED'
        : isExecuted
            ? 'EXECUTED'
            : isExpiredUnfunded
                ? 'UNFUNDED'
                : outcome == 'rejected'
                    ? 'REJECTED'
                    : outcome == 'no_quorum'
                        ? 'NO QUORUM'
                        : isAwaitingFunding
                            ? 'AWAITING FUNDING'
                            : isApproved || isPassed
                                ? 'APPROVED'
                                : isScheduled
                                    ? 'VOTING SCHEDULED'
                                    : proposal['status']
                                                ?.toString()
                                                .toLowerCase() ==
                                            'open'
                                        ? 'VOTING OPEN'
                                        : 'RESOLVING';

    final currentDay = asIntOr(state.clock['day'], 1);
    final currentMinute = asIntOr(state.clock['minute'], 0);
    final currentTotalMinutes = state.clock['totalGameMinutes'] != null
        ? asIntOr(state.clock['totalGameMinutes'], 0)
        : ((currentDay - 1) * 1440 + currentMinute);

    final deadline = proposal['deadline'];
    DateTime? closesAt;
    if (deadline is Map) {
      closesAt = DateTime.tryParse(deadline['closesAt']?.toString() ??
          deadline['closes_at']?.toString() ??
          '');
    }
    if (closesAt == null && proposal['closes_at'] != null) {
      final ms = proposal['closes_at'];
      if (ms is num) {
        closesAt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      }
    }
    final closesGameDay = asInt(proposal['voting_due_end_day'] ??
        proposal['votingDueEndDay'] ??
        proposal['closes_game_day'] ??
        proposal['closesGameDay']);
    // Whole-day voting closes after the final day, not at its 00:00 boundary.
    final closesGameMinute = proposal['voting_due_end_day'] != null ||
            proposal['votingDueEndDay'] != null
        ? 1440
        : asIntOr(
            proposal['closes_game_minute'] ?? proposal['closesGameMinute'], 0);
    final closesTotalMinutes = closesGameDay == null
        ? null
        : ((closesGameDay - 1) * 1440 + closesGameMinute);

    final gameDeadlinePassed = closesTotalMinutes != null
        ? currentTotalMinutes >= closesTotalMinutes
        : (closesAt != null && !now.isBefore(closesAt));

    final isVotingOpen =
        proposal['status']?.toString().toLowerCase() == 'open' &&
            !gameDeadlinePassed;

    final myVote = proposal['my_vote']?.toString() ??
        proposal['myVote']?.toString() ??
        ((proposal['ballots'] is Map)
            ? (proposal['ballots'] as Map)[state.human['id']?.toString()]
                ?.toString()
            : null);
    final voteDeadline = _formatGameDeadline(proposal);
    final gameMinutesRemaining = closesTotalMinutes == null
        ? null
        : (closesTotalMinutes - currentTotalMinutes);

    final supportCount = asIntOr(votes['support'], 0);
    final opposeCount = asIntOr(votes['oppose'], 0);
    final uncastCount = asIntOr(votes['uncast'], 0);
    final totalVotes = supportCount + opposeCount + uncastCount;

    Color statusColor = context.primaryColor;
    if (isExecuted) statusColor = context.successColor;
    if (isAwaitingFunding) statusColor = context.warningColor;
    if (isExpiredUnfunded || outcome == 'rejected' || outcome == 'no_quorum') {
      statusColor = context.errorColor;
    }
    if (isPassed && !isAwaitingFunding && !isExpiredUnfunded && !isExecuted) {
      statusColor = context.successColor;
    }

    // Format creation date & initiator
    final rawCreatorName = proposal['creator_name'] ??
        proposal['creatorName'] ??
        proposal['created_by_name'] ??
        proposal['author_name'] ??
        proposal['author'];
    final creatorHumanId = proposal['created_by_human_id'] ??
        proposal['createdByHumanId'] ??
        proposal['created_by'] ??
        proposal['creator_id'];
    final creatorDisplay =
        (rawCreatorName != null && rawCreatorName.toString().trim().isNotEmpty)
            ? rawCreatorName.toString().trim()
            : (creatorHumanId != null &&
                    creatorHumanId.toString().trim().isNotEmpty)
                ? 'Citizen (${creatorHumanId.toString().trim()})'
                : 'Citizen';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main top row with icon on left and header text column on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(context.radiusControl),
                ),
                child: Icon(
                    isStarted
                        ? Icons.play_circle_outline
                        : isApproved
                            ? Icons.verified_outlined
                            : Icons.how_to_vote_outlined,
                    size: context.iconSize + 4,
                    color: statusColor),
              ),
              SizedBox(width: context.spacingTitleOffset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row containing Title + Metadata on left, Badges on right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                proposal['title']?.toString() ?? '',
                                style: context.widgetValueStyle.copyWith(
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Initiated by: $creatorDisplay · Status: ${proposal['status']} · Outcome: ${proposal['outcome'] ?? 'pending'}',
                                style: context.widgetFooterStyle.copyWith(
                                  height: 1.25,
                                ),
                              ),
                              if (voteDeadline != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  isScheduled
                                      ? 'Voting begins: ${_formatGameStart(proposal, state) ?? 'next game day'} · Voting closes: $voteDeadline'
                                      : isVotingOpen &&
                                              gameMinutesRemaining != null
                                          ? 'Voting ends in ${_formatGameTimeRemaining(gameMinutesRemaining)} · $voteDeadline'
                                          : proposal['status']
                                                          ?.toString()
                                                          .toLowerCase() ==
                                                      'open' &&
                                                  proposal['outcome']
                                                          ?.toString()
                                                          .toLowerCase() ==
                                                      'pending'
                                              ? 'Voting ended · resolving result'
                                              : 'Voting ended · $voteDeadline',
                                  style: context.widgetFooterStyle.copyWith(
                                    color: isVotingOpen
                                        ? context.warningColor
                                        : context.mutedColor,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (proposalId.isNotEmpty) ...[
                          SizedBox(width: context.spacingInline),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              EarthBadge(
                                label: badgeLabel,
                                customColor: statusColor,
                              ),
                              if (myVote != null && myVote.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                EarthBadge(
                                  label: 'VOTED ${myVote.toUpperCase()}',
                                  customColor: context.successColor,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                    if (isAwaitingFunding) ...[
                      const SizedBox(height: 3),
                      Text(
                        _fundingProgress(proposal, currentDay),
                        style: context.widgetFooterStyle.copyWith(
                          color: context.warningColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (isPassed &&
                        !isStarted &&
                        !isExecuted &&
                        !isExpiredUnfunded) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Approved — the action will start automatically after daily settlement.',
                        style: context.widgetFooterStyle.copyWith(
                          color: context.successColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Voting tally breakdown & full-width progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Support $supportCount  ·  Oppose $opposeCount  ·  Uncast $uncastCount',
                  style: context.widgetTitleStyle,
                ),
              ),
              if (totalVotes > 0)
                Text(
                  '${((supportCount / totalVotes) * 100).toStringAsFixed(1)}% SUPPORT',
                  style: context.widgetTitleStyle
                      .copyWith(color: context.primaryColor),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: totalVotes == 0
                ? const LinearProgressIndicator(
                    value: 0,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                  )
                : Row(
                    children: [
                      if (supportCount > 0)
                        Expanded(
                          flex: supportCount,
                          child: Container(
                            height: 6,
                            color: context.primaryColor,
                          ),
                        ),
                      if (opposeCount > 0)
                        Expanded(
                          flex: opposeCount,
                          child: Container(
                            height: 6,
                            color: context.errorColor,
                          ),
                        ),
                      if (uncastCount > 0)
                        Expanded(
                          flex: uncastCount,
                          child: Container(
                            height: 6,
                            color: Colors.white12,
                          ),
                        ),
                    ],
                  ),
          ),

          SizedBox(height: context.spacingTitleOffset),

          // Expand / collapse
          TextButton.icon(
            onPressed: proposalId.isEmpty ? null : onToggleExpand,
            icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            label: Text(isExpanded ? 'HIDE DETAILS' : 'SHOW DETAILS'),
          ),
          if (isExpanded) _buildRichDetails(context, proposal),

          SizedBox(height: context.spacingTitleOffset),

          // Voting action buttons — only visible when voting is open
          if (isVotingOpen && (myVote == null || myVote.isEmpty))
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final choice in ['support', 'oppose', 'abstain'])
                  EarthButton(
                    label: choice,
                    variant: choice == 'support'
                        ? EarthButtonVariant.primary
                        : (choice == 'oppose'
                            ? EarthButtonVariant.danger
                            : EarthButtonVariant.ghost),
                    onPressed: busy ||
                            proposalId.isEmpty ||
                            isExecuted ||
                            isExpiredUnfunded
                        ? null
                        : () => action(
                            () => const EarthApi().vote(proposalId, choice)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _fundingProgress(Map<String, dynamic> proposal, int currentDay) {
    final start =
        asInt(proposal['funding_start_day'] ?? proposal['fundingStartDay']);
    final end =
        asInt(proposal['funding_due_end_day'] ?? proposal['fundingDueEndDay']);
    final reason = proposal['funding_block_reason']?.toString().trim();
    if (start == null || end == null) {
      return 'Approved — automatic funding check is being scheduled.';
    }
    final total = end - start + 1;
    final checked = (currentDay - start + 1).clamp(0, total);
    final remaining = (end - currentDay + 1).clamp(0, total);
    final prefix = currentDay < start
        ? 'Funding window starts on ${_formatGameDay(start)}.'
        : 'Awaiting funding — Day $checked of $total · $remaining day${remaining == 1 ? '' : 's'} left.';
    return reason == null || reason.isEmpty ? prefix : '$prefix $reason.';
  }

  /// Rich, type-specific expanded details based on target_category and typed targets.
  Widget _buildRichDetails(
      BuildContext context, Map<String, dynamic> proposal) {
    final targetCategory =
        (proposal['target_category'] ?? proposal['targetCategory'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
    final targetKind = (proposal['target_kind'] ?? proposal['targetKind'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final buildingCatalogId =
        (proposal['building_catalog_id'] ?? proposal['buildingCatalogId'])
            ?.toString();
    final researchProjectId =
        (proposal['research_project_id'] ?? proposal['researchProjectId'])
            ?.toString();

    final targetValue = proposal['target_value_json'] ??
        proposal['targetValue'] ??
        proposal['target'];
    final targetMap = targetValue is Map
        ? Map<String, dynamic>.from(targetValue)
        : targetValue is String
            ? NanoMarkupHelper.decode(targetValue)
            : <String, dynamic>{};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(context.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author / Initiator line
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: context.primaryColor),
                const SizedBox(width: 6),
                Text('Initiator / Sponsor:', style: context.captionStyle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (proposal['creator_name'] ??
                            proposal['creatorName'] ??
                            proposal['created_by_name'] ??
                            proposal['author'] ??
                            proposal['created_by_human_id'] ??
                            'Citizen')
                        .toString(),
                    style: context.widgetFooterStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.inkColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Always show the proposal body/rationale at the top
          if ((proposal['body']?.toString() ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(proposal['body'].toString(),
                  style: context.widgetFooterStyle),
            ),

          // Type-specific rich details
          if (targetCategory == 'megaproject_procurement' ||
              targetCategory == 'building' ||
              targetKind == 'building_catalog' ||
              (buildingCatalogId != null && buildingCatalogId.isNotEmpty))
            _buildBuildingDetails(context, targetMap,
                buildingCatalogId: buildingCatalogId)
          else if (targetCategory == 'technology' ||
              targetCategory == 'research' ||
              targetKind == 'research_project' ||
              (researchProjectId != null && researchProjectId.isNotEmpty))
            _buildResearchDetails(context, targetMap,
                researchProjectId: researchProjectId)
          else if (targetCategory == 'finance' ||
              targetCategory == 'market' ||
              targetCategory == 'tax' ||
              targetKind == 'finance_rule')
            _buildFinanceDetails(context, targetMap)
          else if (targetMap.isNotEmpty)
            _buildGenericDetails(context, targetCategory, targetMap),

          // Execution status info
          if (proposal['execution_status']?.toString() == 'queued')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Blocker: the approved item is waiting for city capacity or the required resources.',
                style: context.widgetFooterStyle
                    .copyWith(color: context.warningColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBuildingDetails(
      BuildContext context, Map<String, dynamic> target,
      {String? buildingCatalogId}) {
    final buildingType = (buildingCatalogId ??
            target['building_type'] ??
            target['buildingType'] ??
            target['catalog_id'] ??
            target['type'] ??
            '')
        .toString();
    final catalog = state.buildingCatalog
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (item) =>
              item?['id']?.toString() == buildingType ||
              item?['building_type']?.toString() == buildingType ||
              (buildingCatalogId != null &&
                  item?['id']?.toString() == buildingCatalogId),
          orElse: () => null,
        );
    final detail = <String, dynamic>{...target, ...?catalog};
    final buildingName =
        detail['name'] ?? detail['catalog_name'] ?? buildingType;
    final footprint =
        asIntOr(detail['slot_footprint'] ?? detail['slotFootprint'], 1);
    final tier = detail['tier'] ?? 1;
    final category = (detail['category'] ?? 'civic').toString();
    final ownership = detail['ownership_class']?.toString() ?? 'civic';
    final desc = (detail['description'] ?? detail['catalog_description'] ?? '')
        .toString();
    final purpose = (detail['primary_economic_purpose'] ??
            detail['primaryEconomicPurpose'] ??
            EarthBuildingMeta.getEconomicPurpose(detail,
                category: category, ownership: ownership))
        .toString();

    final creditCost = asIntOr(
        detail['cost_credits'] ?? detail['baseCreditCost'] ?? detail['cost'],
        0);
    final matCost =
        asIntOr(detail['cost_materials'] ?? detail['baseMaterialCost'], 0);
    final compCost = asIntOr(detail['cost_components'], 0);
    final computeCost = asIntOr(detail['cost_compute'], 0);
    final constructionDays =
        asIntOr(detail['construction_days'], footprint * asIntOr(tier, 1));

    // Outputs
    final outputs = <(IconData, Color, String)>[];
    void addOutput(String key, String label, IconData icon, Color color) {
      final val = asDoubleOr(detail['output_$key'], 0);
      if (val > 0) {
        outputs.add((
          icon,
          color,
          key == 'credits'
              ? '${formatWholeNumber(val)} CRD / DAY'
              : '${val.toStringAsFixed(1)} $label / DAY'
        ));
      }
    }

    addOutput('credits', 'CREDITS', Icons.account_balance_wallet_outlined,
        EarthResourceColors.credits);
    addOutput(
        'energy', 'ENERGY', Icons.bolt_rounded, EarthResourceColors.energy);
    addOutput('food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
    addOutput('materials', 'MATERIALS', Icons.terrain_outlined,
        EarthResourceColors.materials);
    addOutput('components', 'COMPONENTS',
        Icons.precision_manufacturing_outlined, EarthResourceColors.components);
    addOutput('compute', 'COMPUTE', Icons.memory_rounded,
        EarthResourceColors.compute);

    // Inputs / Upkeep
    final inputs = <(IconData, Color, String)>[];
    void addInput(String key, String label, IconData icon, Color color) {
      final val = asDoubleOr(detail['input_$key'] ?? detail['upkeep_$key'], 0);
      if (val > 0) {
        inputs.add((
          icon,
          color,
          key == 'credits'
              ? '-${formatWholeNumber(val)} CRD'
              : '-${val.toStringAsFixed(1)} $label'
        ));
      }
    }

    addInput('credits', 'CREDITS', Icons.account_balance_wallet_outlined,
        EarthResourceColors.credits);
    addInput(
        'energy', 'ENERGY', Icons.bolt_rounded, EarthResourceColors.energy);
    addInput('food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
    addInput('materials', 'MATERIALS', Icons.terrain_outlined,
        EarthResourceColors.materials);
    addInput('components', 'COMPONENTS', Icons.precision_manufacturing_outlined,
        EarthResourceColors.components);
    addInput('compute', 'COMPUTE', Icons.memory_rounded,
        EarthResourceColors.compute);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Image on left, Name/Badges/Desc/Purpose on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(context.radiusControl),
                child: Image.asset(
                  EarthBuildingMeta.getAssetPath(
                      detail['building_type']?.toString() ?? buildingType),
                  width: 92,
                  height: 92,
                  cacheWidth: 256,
                  cacheHeight: 256,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 92,
                    height: 92,
                    color: context.subtleBorderColor,
                    child: Icon(Icons.apartment_outlined,
                        color: context.mutedColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buildingName.toString(),
                      style: context.widgetTitleStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        EarthBadge(
                          label:
                              '$footprint ${footprint == 1 ? "SPACE" : "SPACES"}',
                          variant: EarthBadgeVariant.neutral,
                        ),
                        EarthBadge(
                          label: category.toUpperCase(),
                          variant: EarthBadgeVariant.neutral,
                        ),
                        EarthBadge(
                          label: 'TIER $tier',
                          variant: EarthBadgeVariant.neutral,
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: context.bodyStyle.copyWith(
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Economic Purpose: $purpose',
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Cost line
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('COST', style: context.captionStyle),
              const SizedBox(width: 2),
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: EarthResourceColors.credits),
              Text(formatWholeNumber(creditCost),
                  style: context.widgetFooterStyle),
              if (matCost > 0) ...[
                const SizedBox(width: 4),
                Icon(EarthResourceMeta.forCommodity('materials').icon,
                    size: 14, color: EarthResourceColors.materials),
                Text('$matCost', style: context.widgetFooterStyle),
              ],
              if (compCost > 0) ...[
                const SizedBox(width: 4),
                Icon(EarthResourceMeta.forCommodity('components').icon,
                    size: 14, color: EarthResourceColors.components),
                Text('$compCost', style: context.widgetFooterStyle),
              ],
              if (computeCost > 0) ...[
                const SizedBox(width: 4),
                Icon(EarthResourceMeta.forCommodity('compute').icon,
                    size: 14, color: EarthResourceColors.compute),
                Text('$computeCost', style: context.widgetFooterStyle),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
              Text('${math.max(1, constructionDays)}d',
                  style: context.widgetFooterStyle),
            ],
          ),

          // Daily Upkeep line
          if (inputs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('DAILY UPKEEP', style: context.captionStyle),
                const SizedBox(width: 2),
                ...inputs.expand((input) => <Widget>[
                      Icon(input.$1, size: 14, color: input.$2),
                      Text(input.$3, style: context.widgetFooterStyle),
                    ]),
              ],
            ),
          ],

          // Daily Output line
          if (outputs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('OUTPUT', style: context.captionStyle),
                const SizedBox(width: 2),
                ...outputs.expand((out) => <Widget>[
                      Icon(out.$1, size: 14, color: out.$2),
                      Text(out.$3, style: context.widgetFooterStyle),
                    ]),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResearchDetails(
      BuildContext context, Map<String, dynamic> target,
      {String? researchProjectId}) {
    final researchName = (researchProjectId ??
            target['research_name'] ??
            target['technology_name'] ??
            target['name'] ??
            target['technology'] ??
            '')
        .toString();
    final corpResearchProjects =
        ((state.corporationBuildingResearch['projects'] as List<dynamic>?) ??
            const []);
    final corpProj = corpResearchProjects
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (p) =>
              p?['id']?.toString() == researchProjectId ||
              p?['catalog_id']?.toString() == researchName ||
              p?['building_type']?.toString() == researchName,
          orElse: () => null,
        );
    final catalogRows = state.technologyRegistry['catalog'];
    final catalog = catalogRows is List
        ? catalogRows
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .cast<Map<String, dynamic>?>()
            .firstWhere(
                (item) =>
                    item?['name']?.toString() == researchName ||
                    item?['technology_key']?.toString() == researchName ||
                    (researchProjectId != null &&
                        item?['id']?.toString() == researchProjectId),
                orElse: () => null)
        : null;
    final detail = <String, dynamic>{...target, ...?corpProj, ...?catalog};
    final buildingType =
        (detail['building_type'] ?? detail['buildingType'] ?? researchName)
            .toString();
    final targetTier =
        detail['target_tier'] ?? detail['tier'] ?? detail['level'] ?? 2;
    final title = detail['name'] ??
        detail['technology_name'] ??
        (buildingType.isNotEmpty
            ? '${_humanize(buildingType)} Tier $targetTier'
            : 'Research Initiative');
    final desc = (detail['description'] ??
            detail['catalog_description'] ??
            'Advanced technology blueprint development and operational upgrades.')
        .toString();
    final progress =
        asDoubleOr(detail['progress'] ?? detail['current_progress'], 0);
    final cost = asDoubleOr(
        detail['research_cost_credits'] ??
            detail['cost_credits'] ??
            detail['cost'] ??
            detail['costs'],
        40000);
    final durationMinutes = asIntOr(detail['duration_minutes'], 2880);
    final durationHours = math.max(1, (durationMinutes / 60).round());
    final category = (detail['category'] ?? 'TECHNOLOGY').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(context.radiusControl),
                child: Image.asset(
                  EarthBuildingMeta.getAssetPath(buildingType),
                  width: 92,
                  height: 92,
                  cacheWidth: 256,
                  cacheHeight: 256,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 92,
                    height: 92,
                    color: context.subtleBorderColor,
                    child:
                        Icon(Icons.science_outlined, color: context.mutedColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title',
                      style: context.widgetTitleStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        EarthBadge(
                          label: 'RESEARCH TIER $targetTier',
                          variant: EarthBadgeVariant.neutral,
                        ),
                        EarthBadge(
                          label: category.toUpperCase(),
                          variant: EarthBadgeVariant.neutral,
                        ),
                        if (progress > 0)
                          EarthBadge(
                            label: '${progress.toStringAsFixed(0)}% PROGRESS',
                            customColor: context.primaryColor,
                          ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: context.bodyStyle.copyWith(
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Unlocks: Tier $targetTier blueprint & upgraded efficiency (+25% output, +12% upkeep)',
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Research Cost & Duration
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('RESEARCH COST', style: context.captionStyle),
              const SizedBox(width: 2),
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: EarthResourceColors.credits),
              Text('${formatWholeNumber(cost)} CREDITS',
                  style: context.widgetFooterStyle),
              const SizedBox(width: 6),
              const Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
              Text('${durationHours}h', style: context.widgetFooterStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceDetails(
      BuildContext context, Map<String, dynamic> target) {
    final category =
        target['category'] ?? target['tax_category'] ?? target['type'] ?? '—';
    final currentRate = target['current_rate'] ?? target['rate'];
    final proposedRate =
        target['proposed_rate'] ?? target['new_rate'] ?? target['value'];
    final scope = target['scope'] ?? 'global';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 16, color: context.warningColor),
            const SizedBox(width: 6),
            Text('FINANCE / TAX PROPOSAL',
                style:
                    context.controlStyle.copyWith(color: context.warningColor)),
          ],
        ),
        const SizedBox(height: 8),
        _detailRow(context, 'Tax Category', _humanize(category.toString())),
        _detailRow(context, 'Scope', scope.toString().toUpperCase()),
        if (currentRate != null)
          _detailRow(
              context, 'Current Rate', NumberFormatHelper.percent(currentRate)),
        if (proposedRate != null)
          _detailRow(
              context,
              'Proposed Rate',
              proposedRate is num
                  ? NumberFormatHelper.percent(proposedRate)
                  : proposedRate.toString()),
        // Show any extra fields
        for (final entry in target.entries)
          if (!{
            'category',
            'tax_category',
            'type',
            'current_rate',
            'rate',
            'proposed_rate',
            'new_rate',
            'value',
            'scope'
          }.contains(entry.key))
            _detailRow(context, _humanize(entry.key), entry.value.toString()),
      ],
    );
  }

  Widget _buildGenericDetails(
      BuildContext context, String category, Map<String, dynamic> target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Target: ${_humanize(category)}',
                style: context.widgetFooterStyle),
          ),
        for (final entry in target.entries)
          _detailRow(context, _humanize(entry.key), entry.value.toString()),
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$label:',
                style: context.widgetFooterStyle
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: context.widgetFooterStyle)),
        ],
      ),
    );
  }

  String _humanize(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String? _formatGameStart(Map<String, dynamic> proposal, EarthState state) {
    var day = asInt(proposal['voting_start_day'] ??
        proposal['votingStartDay'] ??
        proposal['opens_game_day'] ??
        proposal['opensGameDay']);
    var minute = asIntOr(
        proposal['opens_game_minute'] ?? proposal['opensGameMinute'], 0);
    if (day == null) {
      final closesDay =
          asInt(proposal['closes_game_day'] ?? proposal['closesGameDay']);
      if (closesDay == null) return null;
      final ruleId = proposal['rule_version_id'] ?? proposal['ruleVersionId'];
      final rules = ((state.governance['rules'] as List<dynamic>?) ?? const []);
      final rule = rules.whereType<Map>().cast<Map?>().firstWhere(
          (item) => item?['id']?.toString() == ruleId?.toString(),
          orElse: () => null);
      final votingDays = asIntOr(rule?['voting_period_days'], 3);
      final startTotal = ((closesDay - 1) * 1440 +
              asIntOr(
                  proposal['closes_game_minute'] ??
                      proposal['closesGameMinute'],
                  0) -
              votingDays * 1440)
          .clamp(0, 1 << 31);
      day = startTotal ~/ 1440 + 1;
      minute = startTotal % 1440;
    }
    return _formatGameDay(day);
  }

  String? _formatGameDeadline(Map<String, dynamic> proposal) {
    final day = asInt(proposal['voting_due_end_day'] ??
        proposal['votingDueEndDay'] ??
        proposal['closes_game_day'] ??
        proposal['closesGameDay']);
    if (day == null) return null;
    // The due day remains fully open. Closing occurs at the boundary of the
    // following game day, which is clearer than the ambiguous "End of" text.
    return _formatGameDay(day + 1);
  }

  String _formatGameDay(int day) =>
      _formatGameDateTime(day, 0).replaceFirst(' · 00:00', '');

  String _formatGameDateTime(int day, int minute) {
    final hour = (minute ~/ 60).toString().padLeft(2, '0');
    final mins = (minute % 60).toString().padLeft(2, '0');

    // Accurate game calendar year and day calculation
    var daysLeft = day <= 0 ? 0 : day - 1;
    var year = 1;
    while (true) {
      final daysInYear = year % 5 == 0 ? 366 : 365;
      if (daysLeft < daysInYear) break;
      daysLeft -= daysInYear;
      year++;
    }
    final dayOfYear = daysLeft + 1;
    return 'Year $year · Day $dayOfYear · $hour:$mins';
  }

  String _formatGameTimeRemaining(int minutes) {
    final safe = minutes.clamp(0, 1 << 31);
    final days = safe ~/ 1440;
    final hours = (safe % 1440) ~/ 60;
    final mins = safe % 60;
    if (days > 0) {
      if (hours > 0) {
        return '$days day${days == 1 ? '' : 's'} $hours hour${hours == 1 ? '' : 's'}';
      }
      return '$days day${days == 1 ? '' : 's'}';
    }
    if (hours > 0) {
      if (mins > 0) {
        return '$hours hour${hours == 1 ? '' : 's'} $mins min';
      }
      return '$hours hour${hours == 1 ? '' : 's'}';
    }
    return '$mins minute${mins == 1 ? '' : 's'}';
  }
}

/*
class RolesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final String? institutionId;

  const RolesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.institutionId,
  });

  @override
  Widget build(BuildContext context) {
    final roles = _scopedRoles;

    return EarthSection(
      title: 'AUTHORITY / ACTIVE TERMS & DELEGATION',
      showSurface: false,
      infoBulletPoints: const [
        'Institutional Offices & Public Governance: Constitutional offices designated to oversee planetary infrastructure, municipal finance, and civil administration.',
        'Separation of Powers: Legislative and arbitral delegates vote on public referendums; Municipal Mayors & Planners allocate public finance; High Court Jurists hear constitutional appeals.',
        'Action Protocols: Open roles may be claimed by qualifying citizens; active incumbents may resign or designate surrogates via delegation.',
      ],
      child: roles.isEmpty
          ? const EarthEmptyState(
              message: 'No institutional terms are active yet.',
              icon: Icons.account_balance_outlined,
            )
          : EarthDataList(
              children: roles.indexed.map((indexed) {
                final raw = indexed.$2;
                final isLast = indexed.$1 == roles.length - 1;
                final role = raw as Map<String, dynamic>;
                final roleId = role['id']?.toString() ?? 'ROLE';
                final name = role['name']?.toString() ?? roleId;
                final holder = role['human_id'] as String?;
                final myId = state.human['id']?.toString() ?? 'H-0044';
                final isMine = holder == myId;
                final endsDay = role['ends_game_day'] ?? '—';

                return EarthDataRow(
                  title: '$name · Holder: ${holder ?? 'OPEN'}',
                  subtitle: 'Until day $endsDay',
                  leading: Icon(
                    isMine
                        ? Icons.account_circle_outlined
                        : (holder == null
                            ? Icons.help_outline
                            : Icons.badge_outlined),
                    size: context.iconSize,
                    color: isMine
                        ? context.primaryColor
                        : (holder == null
                            ? context.warningColor
                            : context.secondaryColor),
                  ),
                  badges: [
                    if (isMine)
                      const EarthBadge(
                        label: 'ASSIGNED TO YOU',
                        variant: EarthBadgeVariant.primary,
                      ),
                  ],
                  trailing: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isMine) ...[
                        EarthButton(
                          label: 'RESIGN',
                          variant: EarthButtonVariant.danger,
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .resignRole(role['id'] as String)),
                        ),
                        EarthButton(
                          label: 'DELEGATE',
                          variant: EarthButtonVariant.secondary,
                          onPressed: busy
                              ? null
                              : () => showDelegateDialog(
                                  context, action, role['id'] as String),
                        ),
                      ] else if (holder == null) ...[
                        EarthButton(
                          label: 'CLAIM',
                          variant: EarthButtonVariant.primary,
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .claimRole(role['id'] as String)),
                        ),
                      ] else ...[
                        EarthButton(
                          label: 'RECALL',
                          variant: EarthButtonVariant.danger,
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .recallRole(role['id'] as String)),
                        ),
                      ],
                    ],
                  ),
                  showDivider: !isLast,
                );
              }).toList(),
            ),
    );
  }

  List<dynamic> get _scopedRoles => institutionId == null
      ? state.roles
      : state.roles.where((raw) {
          if (raw is! Map) return false;
          return (raw['institution_id'] ?? raw['institutionId'])?.toString() ==
              institutionId;
        }).toList();
}

*/

class PublicFinanceGovernancePanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const PublicFinanceGovernancePanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final taxRules =
        ((state.finance['taxRules'] as List<dynamic>?) ?? const []);
    final proposals =
        ((state.governance['proposals'] as List<dynamic>?) ?? const []);
    final openProposals = proposals
        .where((raw) => raw is Map && raw['status']?.toString() == 'open')
        .length;
    const heldRoles = 0;

    final cockpit = EarthPageCockpit(
      status: 'LEGISLATIVE COMMONS',
      statusColor: context.goldColor,
      infoTitle: 'PUBLIC GOVERNANCE & STATUTES ARCHITECTURE',
      infoDescription:
          '• Active Tax & Public Law: Planetary and municipal statutes governing basic income, sales tax, corporate profit levies, and property rules.\n\n• Democratic Proposals: Citizen-sponsored referendums, rule changes, municipal charter amendments, and budgetary authorizations.\n\n• Civic Offices & Influence: Public offices held, voting rights, and constitutional democratic ratification.',
      title: 'PUBLIC GOVERNANCE',
      subtitle:
          'Active civic statutes, planetary tax rules, democratic proposals, and public budgets across Earth',
      metrics: [
        CockpitMetric(
          label: 'Tax Laws',
          value: '${taxRules.length}',
          icon: Icons.receipt_long_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Proposals',
          value: '$openProposals',
          icon: Icons.gavel_outlined,
          color: context.secondaryColor,
        ),
      ],
    );

    return EarthSection(
      title: 'LAWS IN FORCE / TAXES & PUBLIC SERVICES',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'These are the rules currently shaping taxes and public services.',
        'Review what you pay, what public systems receive, and how the rules affect your work, business, and residency.',
        'Detailed municipal treasury controls belong in City & Services.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cockpit,
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            margin: EdgeInsets.only(bottom: context.spacingTitleOffset),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border:
                  Border.all(color: context.primaryColor.withValues(alpha: .3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: context.warningColor,
                  size: context.iconSize + 3,
                ),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHY THIS MATTERS TO YOU',
                        style: context.topicTitleStyle
                            .copyWith(color: context.warningColor),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Tax rules change the credits you keep from work, business profit, property, and resource activity. Public budgets return value through city services and infrastructure. Review the rule, then decide whether to vote, adapt the business, or change residency.',
                        style: context.widgetFooterStyle.copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (taxRules.isNotEmpty) ...[
            EarthDataList(
              children: taxRules.indexed.map((indexed) {
                final raw = indexed.$2;
                final isLast = indexed.$1 == taxRules.length - 1;
                final rule = raw as Map<String, dynamic>;
                final category =
                    rule['category']?.toString().toLowerCase() ?? '';
                final scope =
                    rule['scope']?.toString().toUpperCase() ?? 'GLOBAL';
                final ratePct = NumberFormatHelper.percent(rule['rate']);
                final version = rule['version'] ?? 1;

                String formattedTitle;
                String description;
                IconData taxIcon;

                switch (category) {
                  case 'basic_income':
                  case 'basic-levy':
                    formattedTitle = 'Basic Income Tax';
                    description =
                        'Planetary baseline levy on daily citizen income and dividends';
                    taxIcon = Icons.person_outline;
                    break;
                  case 'business':
                  case 'revenue-tax':
                  case 'corporate':
                    formattedTitle = 'Corporate & Business Revenue Tax';
                    description =
                        'Operating levy on commercial enterprises and productive facilities';
                    taxIcon = Icons.domain_outlined;
                    break;
                  case 'market':
                  case 'sales':
                    formattedTitle = 'Market Exchange & Sales Fee';
                    description =
                        'Transaction fee applied to commodity exchange trades and orders';
                    taxIcon = Icons.swap_horiz_rounded;
                    break;
                  case 'property':
                    formattedTitle = 'Municipal Property Tax';
                    description =
                        'Assessment on real estate plots and operational buildings';
                    taxIcon = Icons.apartment_outlined;
                    break;
                  default:
                    formattedTitle = category
                        .replaceAll('_', ' ')
                        .replaceAll('-', ' ')
                        .split(' ')
                        .map((w) => w.isNotEmpty
                            ? '${w[0].toUpperCase()}${w.substring(1)}'
                            : '')
                        .join(' ');
                    description =
                        'Statutory tax rule under $scope jurisdiction';
                    taxIcon = Icons.receipt_long_outlined;
                }

                return EarthDataRow(
                  title: formattedTitle,
                  subtitle:
                      '$description · Scope: $scope · Rate: $ratePct · v$version',
                  leading: Icon(
                    taxIcon,
                    size: context.iconSize,
                    color: context.primaryColor,
                  ),
                  trailing: EarthStatusPill(
                    label: 'RATE',
                    value: ratePct,
                    color: context.primaryColor,
                  ),
                  showDivider: !isLast,
                );
              }).toList(),
            ),
          ],
          SizedBox(height: context.spacingTitleOffset),
          Text(
            'Treasury settlement and public spending require authenticated player action.',
            style: context.widgetFooterStyle,
          ),
        ],
      ),
    );
  }
}
