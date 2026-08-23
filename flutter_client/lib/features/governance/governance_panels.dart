import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
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
    final cityMap = city is Map ? Map<String, dynamic>.from(city) : const <String, dynamic>{};
    final citizenship =
        membership?['status']?.toString() ?? membership?['type']?.toString() ?? 'Independent citizen';
    final standing = human['standing'] ?? human['civic_standing'] ?? 'UNAVAILABLE';
    final voting = membership?['voting_eligible'] ?? membership?['votingEligible'] ?? true;
    final obligations =
        membership?['obligations']?.toString() ?? 'Review current laws and tax obligations';

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
                value: cityMap['name']?.toString().toUpperCase() ?? 'INDEPENDENT',
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
                accentColor: voting == true ? context.successColor : context.warningColor,
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

class CivicInfluencePanel extends StatelessWidget {
  final EarthState state;

  const CivicInfluencePanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final heldRoles = state.roles
        .where((raw) => raw is Map && raw['human_id']?.toString() == state.human['id']?.toString())
        .length;
    final proposals = (state.governance['proposals'] as List<dynamic>?)?.length ?? 0;
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

class ProposalPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final proposals = ((state.governance['proposals'] as List<dynamic>?) ?? const [])
        .where((raw) =>
            raw is Map && (raw['institution_id'] ?? raw['institutionId'] ?? institutionId)?.toString() == institutionId)
        .toList();
    final proposal = proposals.isEmpty
        ? <String, dynamic>{
            'id': '',
            'title': 'No open proposal is currently available.',
            'status': 'waiting',
            'outcome': 'pending',
            'execution_status': 'pending',
            'votes': <String, dynamic>{'support': 0, 'oppose': 0, 'uncast': 0},
          }
        : Map<String, dynamic>.from(proposals.first as Map);
    final votes = Map<String, dynamic>.from((proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final hasProposal = proposal['id'].toString().isNotEmpty;
    final proposalId = proposal['id'].toString();
    final isPassed = proposal['outcome'] == 'passed' || proposal['status'] == 'passed';
    final executionStatus =
        (proposal['execution_status']?.toString() ?? (isPassed ? 'ready' : 'pending')).toLowerCase();
    final isChallenged = executionStatus == 'challenged';
    final isVoided = executionStatus == 'voided' || proposal['outcome'] == 'voided';
    final isExecuted = executionStatus == 'executed';

    final currentDay = asIntOr(state.clock['day'], 1);
    final implDay = asInt(proposal['implementation_game_day']) ??
        (proposal['implementation_delay_days'] != null
            ? (asInt(proposal['resolved_game_day']) ?? currentDay) +
                asInt(proposal['implementation_delay_days'])!
            : (isPassed ? currentDay : null));
    final delayDaysRemaining =
        (implDay != null && currentDay < implDay && isPassed) ? (implDay - currentDay) : 0;
    final isCoolingOff =
        isPassed && delayDaysRemaining > 0 && !isChallenged && !isVoided && !isExecuted;

    final supportCount = asIntOr(votes['support'], 0);
    final opposeCount = asIntOr(votes['oppose'], 0);
    final uncastCount = asIntOr(votes['uncast'], 0);
    final totalVotes = supportCount + opposeCount + uncastCount;

    final quorumNum = asDoubleOr(proposal['quorum'], .25);
    final approvalThresholdNum = asDoubleOr(proposal['approval_threshold'], .50);
    final quorumPercent = (quorumNum * 100).round();
    final approvalPercent = (approvalThresholdNum * 100).round();

    final hasJudicialAuthority = state.roles.any((raw) {
      if (raw is! Map<String, dynamic>) return false;
      final role = raw;
      final holder = role['human_id']?.toString();
      final name = role['name']?.toString().toLowerCase() ?? '';
      return holder == state.human['id'] &&
          (name.contains('court') || name.contains('judge') || name.contains('jurist'));
    });

    Color statusColor = context.primaryColor;
    if (isChallenged) statusColor = context.warningColor;
    if (isVoided) statusColor = context.errorColor;
    if (isExecuted) statusColor = context.successColor;
    if (isCoolingOff) statusColor = context.warningColor;
    if (isPassed && !isCoolingOff && !isChallenged && !isVoided && !isExecuted) {
      statusColor = context.successColor;
    }

    return EarthSection(
      title: '$scopeLabel PROPOSAL ${hasProposal ? proposal['id'] : ''}',
      showSurface: false,
      infoBulletPoints: [
        'Universal Citizenship Democratic Ballot: Citizen-initiated legislation governing macroeconomic tax rates, statutory funds, and constitutional amendments.',
        'Quorum & Approval Thresholds: Quorum $quorumPercent%, Approval $approvalPercent% needed for enactment.',
        'Mandatory Implementation Delay (Cooling-Off Period): All passed legislation enters a mandatory cooling-off window prior to execution, allowing affected entities to file constitutional challenges.',
        'Legislative Stages: ACTIVE (open for citizen voting), COOLING-OFF (undergoing judicial review window), READY (authorized for ledger enactment), CHALLENGED (under High Court injunction), EXECUTED (enacted into planetary statutory law).',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Proposal Details & Progress Card
          Container(
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(context.radiusControl),
                      ),
                      child: Icon(Icons.how_to_vote_outlined, size: context.iconSize + 4, color: statusColor),
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
                              if (hasProposal) ...[
                                SizedBox(width: context.spacingInline),
                                EarthBadge(
                                  label: isCoolingOff ? 'COOLING-OFF' : executionStatus.toUpperCase(),
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
                          Text(
                            'Quorum $quorumPercent% · approval $approvalPercent%',
                            style: context.widgetFooterStyle,
                          ),
                          if (isCoolingOff) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.warningColor.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(context.radiusControl),
                                border: Border.all(color: context.warningColor.withValues(alpha: .3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.timer_outlined, size: 13, color: context.warningColor),
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
                          if (proposal['deadline'] is Map) ...[
                            const SizedBox(height: 4),
                            Text(
                              formatProposalDeadline(proposal['deadline'] as Map<String, dynamic>),
                              style: context.widgetFooterStyle.copyWith(
                                color: context.warningColor,
                                fontWeight: FontWeight.w600,
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
                        style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
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
              ],
            ),
          ),

          SizedBox(height: context.spacingTitleOffset),

          // 2. Legislative Action Buttons Hub
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in ['support', 'oppose', 'abstain'])
                EarthButton(
                  label: choice,
                  variant: choice == 'support'
                      ? EarthButtonVariant.primary
                      : (choice == 'oppose' ? EarthButtonVariant.danger : EarthButtonVariant.ghost),
                  onPressed: busy || !hasProposal || isExecuted || isVoided
                      ? null
                      : () => action(() => const EarthApi().vote(proposal['id'] as String, choice)),
                ),
              EarthButton(
                label: 'CREATE $scopeLabel PROPOSAL',
                icon: Icons.note_add_outlined,
                variant: EarthButtonVariant.secondary,
                onPressed: busy
                    ? null
                    : () => showProposalComposer(context, action,
                        institutionId: institutionId, scopeLabel: scopeLabel),
              ),
              if (hasProposal && isPassed && !isChallenged && !isVoided && !isExecuted)
                EarthButton(
                  label: isCoolingOff ? 'COOLING-OFF (DAY $implDay)' : 'EXECUTE PROPOSAL',
                  icon: isCoolingOff ? Icons.lock_clock_outlined : Icons.check_circle_outline,
                  variant: EarthButtonVariant.primary,
                  onPressed: busy || isCoolingOff
                      ? null
                      : () => action(() => const EarthApi().executeProposal(proposalId)),
                ),
              if (hasProposal && isPassed && !isChallenged && !isVoided && !isExecuted)
                EarthButton(
                  label: 'CHALLENGE PROPOSAL',
                  icon: Icons.gavel_outlined,
                  variant: EarthButtonVariant.danger,
                  onPressed: busy ? null : () => showChallengeDialog(context, action, proposalId),
                ),
              if (hasProposal && isChallenged && hasJudicialAuthority)
                EarthButton(
                  label: 'ISSUE RULING',
                  icon: Icons.balance_outlined,
                  variant: EarthButtonVariant.secondary,
                  onPressed: busy ? null : () => showAppealRulingDialog(context, action, proposalId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
                        : (holder == null ? Icons.help_outline : Icons.badge_outlined),
                    size: context.iconSize,
                    color: isMine
                        ? context.primaryColor
                        : (holder == null ? context.warningColor : context.secondaryColor),
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
                              : () => action(() => const EarthApi().resignRole(role['id'] as String)),
                        ),
                        EarthButton(
                          label: 'DELEGATE',
                          variant: EarthButtonVariant.secondary,
                          onPressed: busy
                              ? null
                              : () => showDelegateDialog(context, action, role['id'] as String),
                        ),
                      ] else if (holder == null) ...[
                        EarthButton(
                          label: 'CLAIM',
                          variant: EarthButtonVariant.primary,
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi().claimRole(role['id'] as String)),
                        ),
                      ] else ...[
                        EarthButton(
                          label: 'RECALL',
                          variant: EarthButtonVariant.danger,
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi().recallRole(role['id'] as String)),
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
          return (raw['institution_id'] ?? raw['institutionId'])?.toString() == institutionId;
        }).toList();
}

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
    final taxRules = ((state.finance['taxRules'] as List<dynamic>?) ?? const []);

    return EarthSection(
      title: 'LAWS IN FORCE / TAXES & PUBLIC SERVICES',
      showSurface: false,
      infoBulletPoints: const [
        'These are the rules currently shaping taxes and public services.',
        'Review what you pay, what public systems receive, and how the rules affect your work, business, and residency.',
        'Detailed municipal treasury controls belong in City & Services.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            margin: EdgeInsets.only(bottom: context.spacingTitleOffset),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
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
                        style: context.topicTitleStyle.copyWith(color: context.warningColor),
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

                return EarthDataRow(
                  title: '${rule['scope']} / ${rule['category']}',
                  subtitle: 'Rate: ${NumberFormatHelper.percent(rule['rate'])} · Version ${rule['version']}',
                  leading: Icon(
                    Icons.receipt_long_outlined,
                    size: context.iconSize,
                    color: context.primaryColor,
                  ),
                  trailing: EarthStatusPill(
                    label: 'RATE',
                    value: NumberFormatHelper.percent(rule['rate']),
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
          SizedBox(height: context.spacingControl),
          EarthButton(
            label: 'SETTLE BASIC LEVY ON 1,000 C',
            icon: Icons.account_balance_outlined,
            onPressed: busy ? null : () => action(() => const EarthApi().settleTax(1000)),
          ),
        ],
      ),
    );
  }
}
