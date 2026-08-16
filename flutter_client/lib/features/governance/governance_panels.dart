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
            'votes': <String, dynamic>{'support': 0, 'oppose': 0, 'uncast': 0},
          }
        : Map<String, dynamic>.from(proposals.first as Map);
    final votes = Map<String, dynamic>.from(
        (proposal['votes'] as Map<String, dynamic>?) ?? const {});
    final hasProposal = proposal['id'].toString().isNotEmpty;
    final proposalId = proposal['id'].toString();
    final isPassed = proposal['outcome'] == 'passed';
    final isChallenged = proposal['execution_status'] == 'challenged';
    final hasJudicialAuthority = state.roles.any((raw) {
      final role = raw as Map<String, dynamic>;
      final holder = role['human_id']?.toString();
      final name = role['name']?.toString().toLowerCase() ?? '';
      return holder == state.human['id'] &&
          (name.contains('court') ||
              name.contains('judge') ||
              name.contains('jurist'));
    });

    return EarthPanel(
      title: 'UC PROPOSAL ${proposal['id']}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal['title']),
          Text(
            '${proposal['status']} · ${proposal['outcome'] ?? 'pending'}',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          Text(
            'Quorum ${(((proposal['quorum'] as num?)?.toDouble() ?? .25) * 100).round()}% · approval ${(((proposal['approval_threshold'] as num?)?.toDouble() ?? .5) * 100).round()}%',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          if (proposal['deadline'] is Map)
            Text(
              formatProposalDeadline(
                  proposal['deadline'] as Map<String, dynamic>),
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          const SizedBox(height: 8),
          Text(
              'Support ${votes['support']}  ·  Oppose ${votes['oppose']}  ·  Uncast ${votes['uncast']}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['support', 'oppose', 'abstain']
                .map((choice) => OutlinedButton(
                    onPressed: busy || !hasProposal
                        ? null
                        : () => action(() => const EarthApi()
                            .vote(proposal['id'] as String, choice)),
                    child: Text(choice)))
                .toList(),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed:
                busy ? null : () => showProposalComposer(context, action),
            child: const Text('CREATE PROPOSAL'),
          ),
          if (hasProposal && isPassed && !isChallenged) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => showChallengeDialog(context, action, proposalId),
              child: const Text('FILE CONSTITUTIONAL CHALLENGE'),
            ),
          ],
          if (hasProposal && isChallenged && hasJudicialAuthority) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => showAppealRulingDialog(context, action, proposalId),
              child: const Text('ISSUE HIGH COURT RULING'),
            ),
          ],
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
      title: 'AUTHORITY / ACTIVE TERMS',
      child: state.roles.isEmpty
          ? const Text('No institutional terms are active yet.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.roles.map((raw) {
                final role = raw as Map<String, dynamic>;
                final holder = role['human_id'] as String?;
                final isMine = holder == state.human['id'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${role['name']}  ·  ${holder ?? 'OPEN'}  ·  until day ${role['ends_game_day'] ?? '—'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      if (isMine)
                        Wrap(
                          spacing: 6,
                          children: [
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => action(() => const EarthApi()
                                      .resignRole(role['id'] as String)),
                              child: const Text('RESIGN'),
                            ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => showDelegateDialog(
                                      context, action, role['id'] as String),
                              child: const Text('DELEGATE'),
                            ),
                          ],
                        )
                      else if (holder == null)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .claimRole(role['id'] as String)),
                          child: const Text('CLAIM'),
                        ),
                      if (!isMine && holder != null)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() => const EarthApi()
                                  .recallRole(role['id'] as String)),
                          child: const Text('RECALL'),
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
