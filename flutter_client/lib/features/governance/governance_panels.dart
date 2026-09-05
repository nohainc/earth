import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';
import 'governance_dialogs.dart';

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
        'The implementation delay is the cooling-off period after approval.',
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
                      label: 'IMPLEMENTATION DELAY',
                      value: '${rule['implementation_delay_days'] ?? '—'} DAYS',
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

class ProposalPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final String institutionId;
  final String scopeLabel;

  const ProposalPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.institutionId = 'OUC-001',
    this.scopeLabel = 'UC',
  });

  @override
  State<ProposalPanel> createState() => _ProposalPanelState();
}

class _ProposalPanelState extends State<ProposalPanel> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  final Set<String> _expiredRefreshes = <String>{};

  EarthState get state => widget.state;
  bool get busy => widget.busy;
  Future<void> Function(Future<EarthState> Function()) get action =>
      widget.action;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (mounted) setState(() => _now = now);
      _refreshExpiredProposals(now);
    });
  }

  void _refreshExpiredProposals(DateTime now) {
    if (widget.busy) return;
    final proposals =
        ((widget.state.governance['proposals'] as List<dynamic>?) ?? const []);
    for (final raw in proposals) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString() ?? '';
      final status = raw['status']?.toString().toLowerCase();
      final deadline = raw['deadline'];
      if (id.isEmpty || status != 'open' || deadline is! Map) continue;
      final closesAt = DateTime.tryParse(deadline['closesAt']?.toString() ??
          deadline['closes_at']?.toString() ??
          '');
      if (closesAt == null ||
          now.isBefore(closesAt) ||
          !_expiredRefreshes.add(id)) {
        continue;
      }
      // The server performs the authoritative resolution. This refresh makes
      // the City page show the new outcome without requiring a manual reload.
      () async {
        try {
          await widget.action(() => const EarthApi().world());
        } catch (_) {
          _expiredRefreshes.remove(id);
        }
      }();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = widget.busy;
    final action = widget.action;
    final institutionId = widget.institutionId;
    final scopeLabel = widget.scopeLabel;
    final proposals =
        ((state.governance['proposals'] as List<dynamic>?) ?? const [])
            .where((raw) {
              if (raw is! Map) return false;
              final pInst = (raw['institution_id'] ?? raw['institutionId'])?.toString();
              // Global/Universal proposals (institutionId null or empty or matching) belong to planetary / UC governance
              if (institutionId == 'OUC-001' || scopeLabel == 'UC') {
                return pInst == null || pInst.isEmpty || pInst == 'OUC-001';
              }
              return pInst == institutionId;
            })
            .toList();
    final rules = ((state.governance['rules'] as List<dynamic>?) ?? const [])
        .where((raw) =>
            raw is Map &&
            raw['institution_id']?.toString() == institutionId &&
            raw['status']?.toString() == 'active')
        .toList();
    final currentRule =
        rules.isEmpty ? null : Map<String, dynamic>.from(rules.first as Map);
    final ruleSummary = currentRule == null
        ? 'Common governance defaults apply: 25% quorum · 50% approval · 3-day voting period.'
        : 'Current rule: ${asIntOr(asDoubleOr(currentRule['quorum_threshold'], .25) * 100, 25)}% quorum · ${asIntOr(asDoubleOr(currentRule['approval_threshold'], .5) * 100, 50)}% approval · ${currentRule['voting_period_days'] ?? '—'}-day vote · ${currentRule['implementation_delay_days'] ?? '—'}-day delay.';

    if (proposals.isEmpty) {
      return EarthSection(
        title: '$scopeLabel PROPOSALS',
        showSurface: false,
        trailing: null,
        infoBulletPoints: [
          '$scopeLabel proposals remain open until their configured voting deadline. The result is calculated automatically after the deadline.',
          'Quorum is the minimum participation required; approval is the percentage of decisive votes needed to pass.',
          'Passed proposals observe the implementation delay, then execute automatically when their target conditions are met. Civic construction waits in the city queue if resources or space are unavailable.',
          'Stages: OPEN → PASSED/REJECTED → COOLING-OFF → READY/QUEUED → EXECUTED.',
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRuleSummary(context, ruleSummary),
            const SizedBox(height: 12),
            const EarthEmptyState(
              message: 'No active legislation is currently on the ballot.',
              icon: Icons.how_to_vote_outlined,
            ),
          ],
        ),
      );
    }

    final first = Map<String, dynamic>.from(proposals.first as Map);
    final hasSingle = proposals.length == 1;
    final sectionTitle = hasSingle
        ? '$scopeLabel PROPOSAL ${first['id'] ?? ''}'
        : '$scopeLabel PROPOSALS (${proposals.length})';

    return EarthSection(
      title: sectionTitle,
      showSurface: false,
      trailing: null,
      infoBulletPoints: [
        'Universal Citizenship Democratic Ballot: Citizen-initiated legislation governing macroeconomic tax rates, statutory funds, and constitutional amendments.',
        'Quorum and approval requirements are shown once in the current-rule summary above, not repeated on every proposal.',
        'Mandatory Implementation Delay (Cooling-Off Period): All passed legislation enters a mandatory cooling-off window prior to execution, allowing affected entities to file constitutional challenges.',
        'Legislative Stages: ACTIVE (open for citizen voting), COOLING-OFF (undergoing judicial review window), READY (authorized for ledger enactment), CHALLENGED (under High Court injunction), EXECUTED (enacted into planetary statutory law).',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRuleSummary(context, ruleSummary),
          const SizedBox(height: 12),
          for (final entry in proposals.asMap().entries) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: _buildProposalItem(
                  context, Map<String, dynamic>.from(entry.value as Map)),
            ),
            if (entry.key < proposals.length - 1)
              SizedBox(height: context.spacingControl),
          ],
        ],
      ),
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

  Widget _buildProposalItem(
      BuildContext context, Map<String, dynamic> proposal) {
    final votes = Map<String, dynamic>.from(
        (proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final proposalId = proposal['id']?.toString() ?? '';
    final isPassed =
        proposal['outcome'] == 'passed' || proposal['status'] == 'passed';
    final executionStatus = (proposal['execution_status']?.toString() ??
            (isPassed ? 'ready' : 'pending'))
        .toLowerCase();
    final isChallenged = executionStatus == 'challenged';
    final isQueued = executionStatus == 'queued';
    final isVoided =
        executionStatus == 'voided' || proposal['outcome'] == 'voided';
    final isExecuted = executionStatus == 'executed';

    final currentDay = asIntOr(state.clock['day'], 1);
    final implDay = asInt(proposal['implementation_game_day']) ??
        (proposal['implementation_delay_days'] != null
            ? (asInt(proposal['resolved_game_day']) ?? currentDay) +
                asInt(proposal['implementation_delay_days'])!
            : (isPassed ? currentDay : null));
    final delayDaysRemaining =
        (implDay != null && currentDay < implDay && isPassed)
            ? (implDay - currentDay)
            : 0;
    final isCoolingOff = isPassed &&
        delayDaysRemaining > 0 &&
        !isChallenged &&
        !isVoided &&
        !isExecuted;
    final deadline = proposal['deadline'];
    final closesAt = deadline is Map
        ? DateTime.tryParse(deadline['closesAt']?.toString() ??
            deadline['closes_at']?.toString() ??
            '')
        : null;
    final isVotingOpen =
        proposal['status']?.toString().toLowerCase() == 'open' &&
            (closesAt == null || _now.isBefore(closesAt));

    final supportCount = asIntOr(votes['support'], 0);
    final opposeCount = asIntOr(votes['oppose'], 0);
    final uncastCount = asIntOr(votes['uncast'], 0);
    final totalVotes = supportCount + opposeCount + uncastCount;

    const hasJudicialAuthority = false;

    Color statusColor = context.primaryColor;
    if (isChallenged) statusColor = context.warningColor;
    if (isVoided) statusColor = context.errorColor;
    if (isExecuted) statusColor = context.successColor;
    if (isCoolingOff) statusColor = context.warningColor;
    if (isQueued) statusColor = context.warningColor;
    if (isPassed &&
        !isCoolingOff &&
        !isChallenged &&
        !isVoided &&
        !isExecuted) {
      statusColor = context.successColor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(context.radiusControl),
              ),
              child: Icon(Icons.how_to_vote_outlined,
                  size: context.iconSize + 4, color: statusColor),
            ),
            SizedBox(width: context.spacingTitleOffset),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          proposal['title']?.toString() ?? '',
                          style: context.widgetValueStyle,
                        ),
                      ),
                      if (proposalId.isNotEmpty) ...[
                        SizedBox(width: context.spacingInline),
                        EarthBadge(
                          label: isCoolingOff
                              ? 'COOLING-OFF'
                              : executionStatus.toUpperCase(),
                          customColor: statusColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${proposal['status']} · Outcome: ${proposal['outcome'] ?? 'pending'}',
                    style: context.widgetFooterStyle,
                  ),
                  if (isQueued) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Approved — waiting for city space or resources. It will be retried automatically.',
                      style: context.widgetFooterStyle.copyWith(
                        color: context.warningColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isCoolingOff) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.warningColor.withValues(alpha: .12),
                        borderRadius:
                            BorderRadius.circular(context.radiusControl),
                        border: Border.all(
                            color: context.warningColor.withValues(alpha: .3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 13, color: context.warningColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Cooling-off active: Implementation Day $implDay ($delayDaysRemaining day(s) for challenge)',
                              style: context.widgetFooterStyle.copyWith(
                                color: context.warningColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: context.spacingTitleOffset),

        // Voting Tally Breakdown & Progress Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Support $supportCount  ·  Oppose $opposeCount  ·  Uncast $uncastCount',
              style: context.widgetTitleStyle,
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

        // Legislative Action Buttons
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (isVotingOpen)
              for (final choice in ['support', 'oppose', 'abstain'])
                EarthButton(
                  label: choice,
                  variant: choice == 'support'
                      ? EarthButtonVariant.primary
                      : (choice == 'oppose'
                          ? EarthButtonVariant.danger
                          : EarthButtonVariant.ghost),
                  onPressed:
                      busy || proposalId.isEmpty || isExecuted || isVoided
                          ? null
                          : () => action(
                              () => const EarthApi().vote(proposalId, choice)),
                ),
            if (proposalId.isNotEmpty &&
                isPassed &&
                !isChallenged &&
                !isVoided &&
                !isExecuted)
              EarthButton(
                label: isCoolingOff
                    ? 'COOLING-OFF (DAY $implDay)'
                    : 'EXECUTE PROPOSAL',
                icon: isCoolingOff
                    ? Icons.lock_clock_outlined
                    : Icons.check_circle_outline,
                variant: EarthButtonVariant.primary,
                onPressed: busy || isCoolingOff
                    ? null
                    : () => action(
                        () => const EarthApi().executeProposal(proposalId)),
              ),
            if (proposalId.isNotEmpty &&
                isPassed &&
                !isChallenged &&
                !isVoided &&
                !isExecuted)
              EarthButton(
                label: 'CHALLENGE PROPOSAL',
                icon: Icons.gavel_outlined,
                variant: EarthButtonVariant.danger,
                onPressed: busy
                    ? null
                    : () => showChallengeDialog(context, action, proposalId),
              ),
            if (proposalId.isNotEmpty && isChallenged && hasJudicialAuthority)
              EarthButton(
                label: 'ISSUE RULING',
                icon: Icons.balance_outlined,
                variant: EarthButtonVariant.secondary,
                onPressed: busy
                    ? null
                    : () => showAppealRulingDialog(context, action, proposalId),
              ),
          ],
        ),
      ],
    );
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
    final publicProposals =
        ((state.governance['proposals'] as List<dynamic>?) ?? const [])
            .where((raw) {
              if (raw is! Map) return false;
              final institutionId =
                  (raw['institution_id'] ?? raw['institutionId'])?.toString();
              return institutionId == null ||
                  institutionId.isEmpty ||
                  institutionId == 'OUC-001';
            })
            .toList();
    final openProposals = publicProposals.length;
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
                final category = rule['category']?.toString().toLowerCase() ?? '';
                final scope = rule['scope']?.toString().toUpperCase() ?? 'GLOBAL';
                final ratePct = NumberFormatHelper.percent(rule['rate']);
                final version = rule['version'] ?? 1;

                String formattedTitle;
                String description;
                IconData taxIcon;

                switch (category) {
                  case 'basic_income':
                  case 'basic-levy':
                    formattedTitle = 'Basic Income Tax';
                    description = 'Planetary baseline levy on daily citizen income and dividends';
                    taxIcon = Icons.person_outline;
                    break;
                  case 'business':
                  case 'revenue-tax':
                  case 'corporate':
                    formattedTitle = 'Corporate & Business Revenue Tax';
                    description = 'Operating levy on commercial enterprises and productive facilities';
                    taxIcon = Icons.domain_outlined;
                    break;
                  case 'market':
                  case 'sales':
                    formattedTitle = 'Market Exchange & Sales Fee';
                    description = 'Transaction fee applied to commodity exchange trades and orders';
                    taxIcon = Icons.swap_horiz_rounded;
                    break;
                  case 'property':
                    formattedTitle = 'Municipal Property Tax';
                    description = 'Assessment on real estate plots and operational buildings';
                    taxIcon = Icons.apartment_outlined;
                    break;
                  default:
                    formattedTitle = category
                        .replaceAll('_', ' ')
                        .replaceAll('-', ' ')
                        .split(' ')
                        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
                        .join(' ');
                    description = 'Statutory tax rule under $scope jurisdiction';
                    taxIcon = Icons.receipt_long_outlined;
                }

                return EarthDataRow(
                  title: formattedTitle,
                  subtitle: '$description · Scope: $scope · Rate: $ratePct · v$version',
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
