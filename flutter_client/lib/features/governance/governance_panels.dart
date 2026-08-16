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
    final isPassed = proposal['outcome'] == 'passed';
    final executionStatus = (proposal['execution_status']?.toString() ?? 'pending').toLowerCase();
    final isChallenged = executionStatus == 'challenged';
    final isVoided = executionStatus == 'voided' || proposal['outcome'] == 'voided';
    final isExecuted = executionStatus == 'executed';

    final hasJudicialAuthority = state.roles.any((raw) {
      final role = raw as Map<String, dynamic>;
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

    return EarthPanel(
      title: 'UC PROPOSAL ${hasProposal ? proposal['id'] : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  proposal['title']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              if (hasProposal) ...[
                const SizedBox(width: 8),
                Text(
                  executionStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Status: ${proposal['status']} · Outcome: ${proposal['outcome'] ?? 'pending'}',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          Text(
            'Quorum ${(((proposal['quorum'] as num?)?.toDouble() ?? .25) * 100).round()}% · approval ${(((proposal['approval_threshold'] as num?)?.toDouble() ?? .5) * 100).round()}%',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          if (proposal['deadline'] is Map) ...[
            const SizedBox(height: 2),
            Text(
              formatProposalDeadline(
                  proposal['deadline'] as Map<String, dynamic>),
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          ],
          Text(
            'Support ${votes['support']}  ·  Oppose ${votes['oppose']}  ·  Uncast ${votes['uncast']}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in ['support', 'oppose', 'abstain'])
                OutlinedButton(
                  onPressed: busy || !hasProposal || isExecuted || isVoided
                      ? null
                      : () => action(() => const EarthApi()
                          .vote(proposal['id'] as String, choice)),
                  child: Text(choice),
                ),
              OutlinedButton(
                onPressed:
                    busy ? null : () => showProposalComposer(context, action),
                child: const Text('CREATE PROPOSAL'),
              ),
              if (hasProposal && isPassed && !isChallenged && !isVoided && !isExecuted)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(() => const EarthApi()
                          .executeProposal(proposalId)),
                  child: const Text('EXECUTE PROPOSAL'),
                ),
              if (hasProposal && isPassed && !isChallenged && !isVoided && !isExecuted)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => showChallengeDialog(context, action, proposalId),
                  child: const Text('CHALLENGE PROPOSAL'),
                ),
              if (hasProposal && isChallenged && hasJudicialAuthority)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => showAppealRulingDialog(context, action, proposalId),
                  child: const Text('ISSUE RULING'),
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
      child: state.roles.isEmpty
          ? const Text('No institutional terms are active yet.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.roles.map((raw) {
                final role = raw as Map<String, dynamic>;
                final holder = role['human_id'] as String?;
                final isMine = holder == state.human['id'];
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
                      Text(
                        '${role['name']} · Holder: ${holder ?? 'OPEN'} · Until day ${role['ends_game_day'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (isMine) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .resignRole(role['id'] as String)),
                              child: const Text('RESIGN', style: TextStyle(fontSize: 10)),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => showDelegateDialog(
                                      context, action, role['id'] as String),
                              child: const Text('DELEGATE', style: TextStyle(fontSize: 10)),
                            ),
                          ] else if (holder == null) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .claimRole(role['id'] as String)),
                              child: const Text('CLAIM', style: TextStyle(fontSize: 10)),
                            ),
                          ] else ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .recallRole(role['id'] as String)),
                              child: const Text('RECALL', style: TextStyle(fontSize: 10)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
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
    return EarthPanel(
      title: 'PUBLIC FINANCE / GOVERNANCE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...((state.finance['taxRules'] as List<dynamic>?) ?? const [])
              .map((raw) {
            final rule = raw as Map<String, dynamic>;
            return Text(
              '${rule['scope']} / ${rule['category']}  ·  ${(NumberFormatHelper.percent(rule['rate']))}  ·  v${rule['version']}',
              style: const TextStyle(color: mutedColor, fontSize: 11),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Treasury settlement and public spending require authenticated player action.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() => const EarthApi().settleTax(1000)),
            child: const Text('SETTLE BASIC LEVY ON 1,000 C'),
          ),
          if (state.roles.any((raw) {
            final role = raw as Map<String, dynamic>;
            final holder = role['human_id']?.toString();
            final roleId = role['id']?.toString();
            return holder == state.human['id'] &&
                (roleId == 'ROLE-CITY-MAYOR' || roleId == 'ROLE-CITY-PLANNER');
          })) ...[
            const SizedBox(height: 8),
            const Text(
              'As an active city finance role, you can route UC funds into local services.',
              style: TextStyle(color: mutedColor, fontSize: 10),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => action(() => const EarthApi()
                      .spendPublicFinance('CITY-0084', 'public-services', 100)),
              child: const Text('FUND CITY SERVICES FROM UC · 100 C'),
            ),
          ],
        ],
      ),
    );
  }
}
