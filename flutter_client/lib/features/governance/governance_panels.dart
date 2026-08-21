import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'governance_dialogs.dart';

class ProposalPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const ProposalPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final proposals =
        (state.governance['proposals'] as List<dynamic>?) ?? const [];
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
    final votes = Map<String, dynamic>.from(
        (proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final hasProposal = proposal['id'].toString().isNotEmpty;
    final proposalId = proposal['id'].toString();
    final isPassed = proposal['outcome'] == 'passed' || proposal['status'] == 'passed';
    final executionStatus =
        (proposal['execution_status']?.toString() ?? (isPassed ? 'ready' : 'pending')).toLowerCase();
    final isChallenged = executionStatus == 'challenged';
    final isVoided =
        executionStatus == 'voided' || proposal['outcome'] == 'voided';
    final isExecuted = executionStatus == 'executed';

    final currentDay = asIntOr(state.clock['day'], 1);
    final implDay = asInt(proposal['implementation_game_day']) ??
        (proposal['implementation_delay_days'] != null
            ? (asInt(proposal['resolved_game_day']) ?? currentDay) + asInt(proposal['implementation_delay_days'])!
            : (isPassed ? currentDay : null));
    final delayDaysRemaining = (implDay != null && currentDay < implDay && isPassed)
        ? (implDay - currentDay)
        : 0;
    final isCoolingOff = isPassed && delayDaysRemaining > 0 && !isChallenged && !isVoided && !isExecuted;

    final supportCount = asIntOr(votes['support'], 0);
    final opposeCount = asIntOr(votes['oppose'], 0);
    final uncastCount = asIntOr(votes['uncast'], 0);
    final totalVotes = supportCount + opposeCount + uncastCount;

    final quorumNum = asDoubleOr(proposal['quorum'], .25);
    final approvalThresholdNum =
        asDoubleOr(proposal['approval_threshold'], .50);
    final quorumPercent = (quorumNum * 100).round();
    final approvalPercent = (approvalThresholdNum * 100).round();

    final hasJudicialAuthority = state.roles.any((raw) {
      if (raw is! Map<String, dynamic>) return false;
      final role = raw;
      final holder = role['human_id']?.toString();
      final name = role['name']?.toString().toLowerCase() ?? '';
      return holder == state.human['id'] &&
          (name.contains('court') ||
              name.contains('judge') ||
              name.contains('jurist'));
    });

    Color statusColor = cyanAccentColor;
    if (isChallenged) statusColor = Colors.orangeAccent;
    if (isVoided) statusColor = Colors.redAccent;
    if (isExecuted) statusColor = Colors.greenAccent;
    if (isCoolingOff) statusColor = Colors.amberAccent;
    if (isPassed && !isCoolingOff && !isChallenged && !isVoided && !isExecuted) statusColor = Colors.tealAccent;

    return EarthPanel(
      title: 'UC PROPOSAL ${hasProposal ? proposal['id'] : ''}',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Universal Citizenship Democratic Ballot: Citizen-initiated legislation governing macroeconomic tax rates, statutory funds, and constitutional amendments.\n\n• Quorum & Approval Thresholds:\n  - Quorum: Minimum citizen participation required for ballot validity ($quorumPercent%).\n  - Approval: Majority threshold needed among cast ballots for proposal enactment ($approvalPercent%).\n\n• Mandatory Implementation Delay (Cooling-Off Period):\n  - Spec §1.8.2: All passed legislation enters a mandatory 3-day cooling-off window prior to execution, allowing affected entities to prepare or file constitutional challenges with the UC High Court.\n\n• Legislative Stages:\n  - ACTIVE: Open for citizen voting (support, oppose, abstain).\n  - COOLING-OFF: Approved ballot undergoing mandatory judicial review window.\n  - READY: Cooling-off complete; authorized for ledger enactment.\n  - CHALLENGED: Under injunction awaiting Supreme Court ruling.\n  - EXECUTED: Enacted into statutory planetary law.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. PROPOSAL HEADER & EXECUTION BADGE
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
                        color: statusColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.how_to_vote_outlined,
                          size: 20, color: statusColor),
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
                                  proposal['title']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: inkColor,
                                  ),
                                ),
                              ),
                              if (hasProposal) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color:
                                          statusColor.withValues(alpha: .35),
                                    ),
                                  ),
                                  child: Text(
                                    isCoolingOff
                                        ? 'COOLING-OFF'
                                        : executionStatus.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .8,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${proposal['status']} · Outcome: ${proposal['outcome'] ?? 'pending'}',
                            style: const TextStyle(
                                color: mutedColor, fontSize: 11),
                          ),
                          Text(
                            'Quorum $quorumPercent% · approval $approvalPercent%',
                            style: const TextStyle(
                                color: mutedColor, fontSize: 11),
                          ),
                          if (isCoolingOff) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amberAccent.withValues(alpha: .3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 13, color: Colors.amberAccent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Cooling-off active: Implementation Day $implDay ($delayDaysRemaining day(s) for challenge)',
                                      style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 10.5,
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
                              formatProposalDeadline(proposal['deadline']
                                  as Map<String, dynamic>),
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Voting Tally Breakdown & Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Support $supportCount  ·  Oppose $opposeCount  ·  Uncast $uncastCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: inkColor,
                      ),
                    ),
                    if (totalVotes > 0)
                      Text(
                        '${((supportCount / totalVotes) * 100).toStringAsFixed(1)}% SUPPORT',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cyanAccentColor,
                        ),
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
                                  color: cyanAccentColor,
                                ),
                              ),
                            if (opposeCount > 0)
                              Expanded(
                                flex: opposeCount,
                                child: Container(
                                  height: 6,
                                  color: Colors.redAccent,
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

          const SizedBox(height: 14),

          // 2. LEGISLATIVE ACTIONS HUB
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in ['support', 'oppose', 'abstain'])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: choice == 'support'
                        ? cyanAccentColor
                        : (choice == 'oppose' ? Colors.redAccent : mutedColor),
                    side: BorderSide(
                      color: choice == 'support'
                          ? cyanAccentColor.withValues(alpha: .3)
                          : (choice == 'oppose'
                              ? Colors.redAccent.withValues(alpha: .3)
                              : Colors.white24),
                    ),
                  ),
                  onPressed: busy || !hasProposal || isExecuted || isVoided
                      ? null
                      : () => action(() => const EarthApi()
                          .vote(proposal['id'] as String, choice)),
                  child: Text(
                    choice,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: inkColor,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed:
                    busy ? null : () => showProposalComposer(context, action),
                icon: const Icon(Icons.note_add_outlined, size: 14),
                label: const Text(
                  'CREATE PROPOSAL',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (hasProposal &&
                  isPassed &&
                  !isChallenged &&
                  !isVoided &&
                  !isExecuted)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isCoolingOff ? Colors.amberAccent : cyanAccentColor,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: busy || isCoolingOff
                      ? null
                      : () => action(
                          () => const EarthApi().executeProposal(proposalId)),
                  icon: Icon(isCoolingOff ? Icons.lock_clock_outlined : Icons.check_circle_outline, size: 14),
                  label: Text(
                    isCoolingOff ? 'COOLING-OFF (DAY $implDay)' : 'EXECUTE PROPOSAL',
                    style:
                        const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ),
              if (hasProposal &&
                  isPassed &&
                  !isChallenged &&
                  !isVoided &&
                  !isExecuted)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    side: BorderSide(
                        color: Colors.orangeAccent.withValues(alpha: .35)),
                  ),
                  onPressed: busy
                      ? null
                      : () => showChallengeDialog(context, action, proposalId),
                  icon: const Icon(Icons.gavel_outlined, size: 14),
                  label: const Text(
                    'CHALLENGE PROPOSAL',
                    style:
                        TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              if (hasProposal && isChallenged && hasJudicialAuthority)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: violetColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy
                      ? null
                      : () => showAppealRulingDialog(
                          context, action, proposalId),
                  icon: const Icon(Icons.balance_outlined, size: 14),
                  label: const Text(
                    'ISSUE RULING',
                    style:
                        TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
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

  const RolesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'AUTHORITY / ACTIVE TERMS & DELEGATION',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Institutional Offices & Public Governance: Constitutional offices designated to oversee planetary infrastructure, municipal finance, and civil administration.\n\n• Constitutional Separation of Powers:\n  - ROLE-OUC-DELEGATE: Legislative and arbitral delegate with voting authority on public referendums.\n  - ROLE-CITY-MAYOR / PLANNER: Municipal executive authority allocating public finance into civic services.\n  - ROLE-JUSTICE: Supreme court jurist hearing constitutional challenges and appeals.\n\n• Action Protocols: Open roles may be claimed by qualifying citizens; active incumbents may resign or designate surrogates via delegation.',
      child: state.roles.isEmpty
          ? const Text('No institutional terms are active yet.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Container(
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: state.roles.indexed.map((indexed) {
                  final raw = indexed.$2;
                  final isLast = indexed.$1 == state.roles.length - 1;
                  final role = raw as Map<String, dynamic>;
                  final roleId = role['id']?.toString() ?? 'ROLE';
                  final name = role['name']?.toString() ?? roleId;
                  final holder = role['human_id'] as String?;
                  final myId = state.human['id']?.toString() ?? 'H-0044';
                  final isMine = holder == myId;
                  final endsDay = role['ends_game_day'] ?? '—';

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: isLast
                            ? BorderSide.none
                            : const BorderSide(color: Colors.white10),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: (isMine
                                        ? cyanAccentColor
                                        : (holder == null
                                            ? Colors.orangeAccent
                                            : violetColor))
                                    .withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                isMine
                                    ? Icons.account_circle_outlined
                                    : (holder == null
                                        ? Icons.help_outline
                                        : Icons.badge_outlined),
                                size: 15,
                                color: isMine
                                    ? cyanAccentColor
                                    : (holder == null
                                        ? Colors.orangeAccent
                                        : violetColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$name · Holder: ${holder ?? 'OPEN'} · Until day $endsDay',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: inkColor,
                                ),
                              ),
                            ),
                            if (isMine)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cyanAccentColor.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color:
                                          cyanAccentColor.withValues(alpha: .3)),
                                ),
                                child: const Text(
                                  'ASSIGNED TO YOU',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: cyanAccentColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (isMine) ...[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.orangeAccent,
                                  side: BorderSide(
                                      color: Colors.orangeAccent
                                          .withValues(alpha: .3)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .resignRole(role['id'] as String)),
                                child: const Text('RESIGN',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: violetColor,
                                  side: BorderSide(
                                      color:
                                          violetColor.withValues(alpha: .3)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => showDelegateDialog(
                                        context, action, role['id'] as String),
                                child: const Text('DELEGATE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ] else if (holder == null) ...[
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: cyanAccentColor,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 2),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .claimRole(role['id'] as String)),
                                child: const Text('CLAIM',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ] else ...[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(
                                      color: Colors.redAccent
                                          .withValues(alpha: .3)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .recallRole(role['id'] as String)),
                                child: const Text('RECALL',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
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
    final taxRules =
        ((state.finance['taxRules'] as List<dynamic>?) ?? const []);

    return EarthPanel(
      title: 'PUBLIC FINANCE / GOVERNANCE',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Public Finance & Municipal Treasury: Statutory fiscal rules and public expenditure budgets funding planetary health, universal basic services, and municipal infrastructure.\n\n• Tax Rule System: Universal citizen tax rates evaluated across personal income, corporate surplus, asset transfers, and resource extraction.\n\n• Public Fund Routing: Citizens serving as City Mayors or City Planners possess authority to deploy UC municipal funds directly into public service operations.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: .3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.orangeAccent, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WHY THIS MATTERS TO YOU',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .9,
                              color: Colors.orangeAccent)),
                      SizedBox(height: 5),
                      Text(
                        'Tax rules change the credits you keep from work, business profit, property, and resource activity. Public budgets return value through city services and infrastructure. Review the rule, then decide whether to vote, adapt the business, or change residency.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (taxRules.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Text(
                      'STATUTORY TAX RULES',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: mutedColor,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  ...taxRules.indexed.map((indexed) {
                    final raw = indexed.$2;
                    final isLast = indexed.$1 == taxRules.length - 1;
                    final rule = raw as Map<String, dynamic>;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: isLast
                              ? BorderSide.none
                              : const BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${rule['scope']} / ${rule['category']}',
                            style: const TextStyle(
                              color: inkColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(NumberFormatHelper.percent(rule['rate']))}  ·  v${rule['version']}',
                            style: const TextStyle(
                              color: cyanAccentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          const Text(
            'Treasury settlement and public spending require authenticated player action.',
            style: TextStyle(color: mutedColor, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cyanAccentColor,
              side:
                  BorderSide(color: cyanAccentColor.withValues(alpha: .35)),
            ),
            onPressed: busy
                ? null
                : () => action(() => const EarthApi().settleTax(1000)),
            icon: const Icon(Icons.account_balance_outlined, size: 14),
            label: const Text(
              'SETTLE BASIC LEVY ON 1,000 C',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (state.roles.any((raw) {
            if (raw is! Map<String, dynamic>) return false;
            final role = raw;
            final holder = role['human_id']?.toString();
            final roleId = role['id']?.toString();
            return holder == state.human['id'] &&
                (roleId == 'ROLE-CITY-MAYOR' || roleId == 'ROLE-CITY-PLANNER');
          })) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: violetColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: violetColor.withValues(alpha: .25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'As an active city finance role, you can route UC funds into local services.',
                    style: TextStyle(
                        color: inkColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: violetColor,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: busy
                        ? null
                        : () => action(() => const EarthApi()
                            .spendPublicFinance(
                                'CITY-0084', 'public-services', 100)),
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text(
                      'FUND CITY SERVICES FROM UC · 100 C',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
