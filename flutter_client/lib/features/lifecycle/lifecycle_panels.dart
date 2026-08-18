import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../governance/governance_dialogs.dart';
import 'lifecycle_dialogs.dart';

class SuccessionPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const SuccessionPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final life = state.life;
    final human = state.human;
    final lifeStatus = (life['status']?.toString() ?? human['life_status']?.toString() ?? 'active').toLowerCase();
    final age = asIntOr(life['ageYears'] ?? human['age_years'] ?? human['ageYears'], 31);
    final politicalEligibleDay = asIntOr(life['politicalEligibilityDay'], 180);
    final currentDay = asIntOr(state.clock['day'], 184);
    final isPoliticallyEligible = currentDay >= politicalEligibleDay || age >= 25;

    final rawSuccessor = life['successor'];
    final successor = rawSuccessor is Map<String, dynamic> ? rawSuccessor : null;
    final successorName = successor?['successor_name']?.toString() ?? successor?['name']?.toString();
    final successorHumanId = successor?['successor_human_id']?.toString() ?? successor?['successorHumanId']?.toString();
    final registeredDay = successor?['registered_game_day'] ?? successor?['registeredOnDay'];
    final estatePeriodDays = asIntOr(successor?['estate_period_days'] ?? life['estatePeriodDays'], 30);

    final heirPct = asIntOr(successor?['heir_pct'], 70);
    final trustPct = asIntOr(successor?['trust_pct'], 20);
    final reservePct = asIntOr(successor?['reserve_pct'], 10);

    final isEstatePeriod = lifeStatus == 'estate';
    final isDeceased = lifeStatus == 'deceased';

    Color statusColor = cyanAccentColor;
    if (isEstatePeriod) statusColor = Colors.orangeAccent;
    if (isDeceased) statusColor = Colors.redAccent;

    String generationalStage = 'PRIME OPERATIVE (100% LABOR EFFICIENCY)';
    Color stageColor = cyanAccentColor;
    if (age >= 65) {
      generationalStage = 'DYNASTIC PATRIARCH/MATRIARCH (+25% GOVERNANCE WISDOM)';
      stageColor = violetColor;
    } else if (age >= 45) {
      generationalStage = 'SENIOR EXECUTIVE (BALANCED PRODUCTIVITY)';
      stageColor = Colors.tealAccent;
    }

    final credits = asDouble(human['credits']) ?? 0.0;
    final estimatedTax = isEstatePeriod ? credits * 0.20 : credits * 0.10;
    final estimatedNet = (credits - estimatedTax).clamp(0.0, double.infinity);

    return EarthPanel(
      title: 'LIFE / BIOLOGICAL AGING & SUCCESSION',
      infoDescription:
          '• Biological Aging & Generational Succession (Spec §1.4, §1.5):\n  - Simulation Time Dilation (1:60): 1 Real Second = 1 Game Minute (24 Real Minutes = 1 Game Day; 6 Real Days = 1 Simulation Year).\n  - Biological Lifespan: Characters enter at legal adulthood (Age 20) and reach natural mortality around 75–90+ simulation years (~1 Real Calendar Year of active play).\n  - Generational Wisdom Shift: Past age 65, physical labor efficiency gently declines while governance influence and political wisdom bonuses increase (+25%).\n\n• Biometric Health & Stochastic Mortality (Spec §1.4.1):\n  - Health Impact: Governs physical labor throughput, machine maintenance efficiency, and healthcare expenses. Sub-optimal health does not mean instant death; mortality past retirement age follows an actuarial hazard curve.\n\n• Testamentary Will & Estate Probate (Spec §1.4.2):\n  - Multi-Beneficiary Testament: Designate custom asset distributions across Primary Heirs, Municipal Public Trusts, and Dynastic Family Reserves.\n  - Progressive Estate Tax: Deducted automatically upon probate (10% standard, 20% late estate settlement).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BIOLOGICAL AGE & GENERATIONAL STAGE
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'BIOLOGICAL AGE: $age YEARS',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: inkColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor.withValues(alpha: .35)),
                      ),
                      child: Text(
                        lifeStatus.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: stageColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: stageColor.withValues(alpha: .3)),
                      ),
                      child: Text(
                        generationalStage,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: stageColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (age / 90.0).clamp(0.0, 1.0),
                    minHeight: 5,
                    color: stageColor,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lifespan Expectancy ~90y · ${isPoliticallyEligible ? 'Politically mature' : 'Political lock (Day $politicalEligibleDay)'}',
                  style: const TextStyle(fontSize: 9.5, color: mutedColor),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. TESTAMENTARY WILL & SUCCESSOR PLAN
          if (successorName != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_edu_outlined, size: 14, color: cyanAccentColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'SUCCESSOR: $successorName ${successorHumanId != null ? '($successorHumanId)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: inkColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Registered on Day $registeredDay · Estate buffer: $estatePeriodDays days',
                    style: const TextStyle(fontSize: 10, color: mutedColor),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _beneficiaryChip('PRIMARY HEIR', '$heirPct%', cyanAccentColor),
                      _beneficiaryChip('MUNICIPAL TRUST', '$trustPct%', Colors.tealAccent),
                      _beneficiaryChip('DYNASTIC RESERVE', '$reservePct%', violetColor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Est. Net Transfer: ~${formatCreditsAmount(estimatedNet)} (after ~${formatCreditsAmount(estimatedTax)} estate tax)',
                    style: const TextStyle(fontSize: 10, color: mutedColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEstatePeriod
                        ? 'Estate state: ACTIVE ESTATE PERIOD (Awaiting settlement or liquidation)'
                        : 'Estate state: PENDING (Protected transition ready upon mortality)',
                    style: TextStyle(fontSize: 10, color: isEstatePeriod ? Colors.orangeAccent : cyanAccentColor),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'No succession plan registered. In the event of mortality, unclaimed assets will be liquidated to the municipal treasury after the estate period.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cyanAccentColor,
                  side: BorderSide(color: cyanAccentColor.withValues(alpha: .3)),
                ),
                onPressed: busy ? null : () => showSuccessorComposerDialog(context, action),
                icon: const Icon(Icons.edit_note_outlined, size: 14),
                label: Text(successorName == null ? 'PLAN SUCCESSION & WILL' : 'UPDATE WILL & SUCCESSOR'),
              ),
              if (isEstatePeriod && successorName != null)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => showSettleInheritanceDialog(
                            context,
                            action,
                            predecessorId: human['id']?.toString() ?? 'H-0044',
                            defaultSuccessorName: successorName,
                          ),
                  child: const Text('SETTLE ESTATE INHERITANCE'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _beneficiaryChip(String label, String pct, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: mutedColor,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              pct,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );
}

class LegacyPersonalFinancePanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const LegacyPersonalFinancePanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'PERSONAL FINANCE / PROTECTED MINIMUM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status: ${state.personalFinance['status'] ?? 'active'}  ·  protected minimum ${state.personalFinance['protected_credits'] ?? 100} C',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 6),
          const Text(
            'A restructuring preserves one basic service robot and the protected Credit minimum; non-protected productive assets are liquidated.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 8),
          if (state.personalFinance['status'] != 'bankrupt')
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => action(
                      () => const EarthApi().declarePersonalInsolvency()),
              child: const Text('DECLARE INSOLVENCY RESTRUCTURING'),
            ),
        ],
      ),
    );
  }
}

class InstitutionSolvencyPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const InstitutionSolvencyPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'INSTITUTION SOLVENCY / RECOVERY',
      infoDescription:
          '• Institutional Solvency & Recapitalization: Statutory economic health monitoring for municipal cities and corporate enterprises.\n\n• Solvency Tiers:\n  - SOLVENT: Normal operations; reserves satisfy all statutory coverage buffers.\n  - DISTRESSED: Reserves below operating minimums; public services rationed.\n  - INSOLVENT: Treasury exhausted; automatic liquidation begins unless recapitalized.\n\n• Recapitalization Recovery: Citizens may contribute equity credits to restore insolvent or distressed institutions back to active legal status.',
      child: state.financeStatus.isEmpty
          ? const Text(
              'Financial states will appear after the next world-day assessment.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.financeStatus.map((raw) {
                final item = raw as Map<String, dynamic>;
                final kind = (item['institution_kind']?.toString() ?? 'INSTITUTION').toUpperCase();
                final id = item['institution_id']?.toString() ?? '';
                final status = (item['status']?.toString() ?? 'SOLVENT').toUpperCase();
                final sinceDay = item['since_game_day']?.toString() ?? '—';

                final crisis = status == 'DISTRESSED' || status == 'INSOLVENT';
                final recoverable = kind == 'CITY' || kind == 'CORPORATION';

                Color statusColor = cyanAccentColor;
                if (status == 'DISTRESSED') statusColor = Colors.orangeAccent;
                if (status == 'INSOLVENT') statusColor = Colors.redAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: crisis ? statusColor.withValues(alpha: .4) : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          kind == 'CITY' ? Icons.location_city_outlined : Icons.domain_outlined,
                          size: 16,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$kind $id',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: inkColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor.withValues(alpha: .3)),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$kind $id  ·  ${item['status']}  ·  since day $sinceDay',
                              style: const TextStyle(fontSize: 10.5, color: mutedColor),
                            ),
                          ],
                        ),
                      ),
                      if (crisis && recoverable) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          onPressed: busy
                              ? null
                              : () => showRecoveryDialog(
                                    context,
                                    action,
                                    item['institution_id'] as String,
                                    item['institution_kind'] as String,
                                  ),
                          icon: const Icon(Icons.healing_outlined, size: 14),
                          label: const Text('RECOVER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class NegotiatedContractsPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const NegotiatedContractsPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final canArbitrate = state.roles.any((raw) {
      final role = raw as Map<String, dynamic>;
      return role['id'] == 'ROLE-OUC-DELEGATE' &&
          (role['human_id'] == state.human['id'] ||
              role['delegate_id'] == state.human['id']);
    });

    return EarthPanel(
      title: 'NEGOTIATED CONTRACTS / DIRECT AGREEMENTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.contracts.isEmpty)
            const Text('No direct agreements yet.',
                style: TextStyle(color: mutedColor, fontSize: 11))
          else
            ...state.contracts.take(8).map((raw) {
              final contract = raw as Map<String, dynamic>;
              final mine = contract['proposer_id'] == state.human['id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${contract['title']}  ·  ${contract['kind']}  ·  ${contract['status']}  ·  ${contract['amount']} C',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (contract['status'] == 'proposed' && !mine)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => action(() => const EarthApi()
                                .acceptContract(contract['id'] as String)),
                        child: const Text('ACCEPT'),
                      ),
                    if (contract['status'] == 'proposed')
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => action(() => const EarthApi()
                                .cancelContract(contract['id'] as String)),
                        child: const Text('CANCEL'),
                      ),
                    if ((contract['status'] == 'accepted' ||
                            contract['status'] == 'completed') &&
                        contract['dispute_id'] == null)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => showDisputeDialog(
                                context, action, contract['id'] as String),
                        child: const Text('DISPUTE'),
                      ),
                    if (contract['dispute_id'] != null)
                      const Text(
                        'DISPUTE OPEN',
                        style: TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                    if (canArbitrate && contract['dispute_id'] != null)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => showResolveDialog(
                                context, action, contract['id'] as String),
                        child: const Text('ARBITRATE'),
                      ),
                  ],
                ),
              );
            }),
          OutlinedButton(
            onPressed:
                busy ? null : () => showContractComposerDialog(context, action),
            child: const Text('PROPOSE AGREEMENT'),
          ),
        ],
      ),
    );
  }
}

class LedgerPanel extends StatelessWidget {
  final EarthState state;

  const LedgerPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final entries = state.ledgerEntries;

    return EarthPanel(
      title: 'CENTRAL LEDGER / RECENT ACTIVITY',
      infoDescription:
          '• Double-Entry Cryptographic Ledger: Immutable journal of all currency and asset flows across central clearing, dividend distributions, tax assessments, and peer transfers.\n\n• Invariant Protection: Every debit from a source account is strictly matched with an equal credit to a destination account, ensuring mathematical equilibrium and zero synthetic money leakage.\n\n• Audit Traceability: Transactions record immutable reason codes, amounts, and source-to-destination routing.',
      child: entries.isEmpty
          ? const Text(
              'No ledger activity recorded yet.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.take(10).map((raw) {
                final entry = raw as Map<String, dynamic>;
                final reason =
                    (entry['reason_type']?.toString() ?? 'TRANSFER')
                        .toUpperCase();
                final amount = entry['amount'] ?? 0;
                final currency =
                    (entry['currency']?.toString() ?? 'C').toUpperCase();
                final debit =
                    entry['debit_account']?.toString() ?? 'SYSTEM_ESCROW';
                final credit =
                    entry['credit_account']?.toString() ?? 'CITIZEN_WALLET';

                Color reasonColor = cyanAccentColor;
                IconData reasonIcon = Icons.swap_horiz_rounded;

                if (reason.contains('TAX')) {
                  reasonColor = Colors.orangeAccent;
                  reasonIcon = Icons.receipt_long_outlined;
                } else if (reason.contains('DIVIDEND') || reason.contains('INCOME')) {
                  reasonColor = violetColor;
                  reasonIcon = Icons.paid_outlined;
                } else if (reason.contains('MARKET') || reason.contains('ORDER')) {
                  reasonColor = Colors.tealAccent;
                  reasonIcon = Icons.storefront_outlined;
                } else if (reason.contains('FEE') || reason.contains('PENALTY')) {
                  reasonColor = Colors.redAccent;
                  reasonIcon = Icons.gavel_outlined;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: reasonColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(reasonIcon, size: 14, color: reasonColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: reasonColor,
                                letterSpacing: .6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$debit → $credit',
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: mutedColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '$amount $currency',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: inkColor,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class WorldFeedPanel extends StatelessWidget {
  final List<dynamic> events;

  const WorldFeedPanel({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'WORLD FEED / RECENT EVENTS',
      child: events.isEmpty
          ? const Text('No public events recorded yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: events.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '${event['type']}  ·  ${event['actor']}  ·  ${event['occurred_at']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class NotificationsPanel extends StatelessWidget {
  final List<dynamic> notifications;
  final int unreadNotifications;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final EarthState state;

  const NotificationsPanel({
    super.key,
    required this.notifications,
    required this.unreadNotifications,
    required this.busy,
    required this.action,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'NOTIFICATIONS / $unreadNotifications UNREAD',
      child: notifications.isEmpty
          ? const Text('No personal alerts yet.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: notifications.take(8).map((raw) {
                final notification = raw as Map<String, dynamic>;
                final unread = notification['read_at'] == null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${unread ? '• ' : ''}${notification['title']}\n${notification['body']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() async {
                                    await const EarthApi()
                                        .markNotificationRead(
                                            notification['id'] as String);
                                    return state;
                                  }),
                          child: const Text('READ'),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class OwnershipTimelinePanel extends StatelessWidget {
  final List<dynamic> ownershipEvents;

  const OwnershipTimelinePanel({super.key, required this.ownershipEvents});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'OWNERSHIP / PROVENANCE TIMELINE',
      infoDescription:
          '• Asset Provenance & Lineage: Immutable historical record tracking legal titles, transfers, acquisitions, and ownership transitions.\n\n• Asset Classes: Tracks industrial machines, enterprise equity shares, technological patents, and civic facilities.\n\n• Audit Chain: Every transfer verifies historical custody, preventing counterparty dispute and counterfeit claims.',
      child: ownershipEvents.isEmpty
          ? const Text(
              'Your asset provenance history will appear here after your first acquisition or transfer.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ownershipEvents.take(10).map((raw) {
                final event = raw as Map<String, dynamic>;
                final direction =
                    event['from_owner_id'] == null ? 'ACQUIRED' : 'TRANSFERRED';
                final isAcquired = direction == 'ACQUIRED';
                final assetType =
                    (event['asset_type']?.toString() ?? 'ASSET').toUpperCase();
                final assetId = event['asset_id']?.toString() ?? '—';
                final qty = event['quantity'] ?? 1;
                final gameDay = event['game_day'] ?? '—';
                final fromOwner = event['from_owner_id']?.toString() ?? 'ORIGIN_TREASURY';
                final toOwner = event['to_owner_id']?.toString() ?? 'CURRENT_HOLDER';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isAcquired
                              ? cyanAccentColor.withValues(alpha: .15)
                              : violetColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isAcquired
                              ? Icons.add_circle_outline_rounded
                              : Icons.swap_horiz_rounded,
                          size: 14,
                          color: isAcquired ? cyanAccentColor : violetColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .06),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'DAY $gameDay',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: mutedColor,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$assetType · $assetId ($qty units)',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: inkColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$fromOwner → $toOwner',
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: mutedColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isAcquired ? cyanAccentColor : violetColor)
                              .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (isAcquired ? cyanAccentColor : violetColor)
                                .withValues(alpha: .3),
                          ),
                        ),
                        child: Text(
                          direction,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                            color: isAcquired ? cyanAccentColor : violetColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class CivicMembershipHistoryPanel extends StatelessWidget {
  final List<dynamic> membershipEvents;

  const CivicMembershipHistoryPanel({super.key, required this.membershipEvents});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'CIVIC STATUS / MEMBERSHIP HISTORY',
      infoDescription:
          '• Civic & Corporate Affiliation Journal: Chronological record of citizenship declarations, municipal registrations, and corporate charters.\n\n• Affiliation Records:\n  - JOIN_CITY / RESIDE: Residential affiliation establishing eligibility for municipal services and local voting.\n  - FOUND_ENTERPRISE / INCORPORATE: Corporate legal registration establishing commercial limited liability.\n  - JOIN_COMMUNITY: Collective civic association membership.',
      child: membershipEvents.isEmpty
          ? const Text(
              'Your civic and corporate history will appear here after joining an institution.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: membershipEvents.take(8).map((raw) {
                if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                final event = raw;
                final day = event['game_day']?.toString() ?? '-';
                final type = (event['institution_type']?.toString() ?? 'CIVIC').toUpperCase();
                final id = event['institution_id']?.toString() ?? '';
                final action = (event['action']?.toString() ?? 'JOIN').toUpperCase();

                Color typeColor = cyanAccentColor;
                if (type.contains('CORP')) typeColor = violetColor;
                if (type.contains('COMMUNITY')) typeColor = Colors.tealAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DAY $day',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: typeColor.withValues(alpha: .3)),
                        ),
                        child: Text(
                          type,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: typeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          id,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                          ),
                        ),
                      ),
                      Text(
                        action,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: inkColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class AuthorityHistoryPanel extends StatelessWidget {
  final List<dynamic> authorityEvents;

  const AuthorityHistoryPanel({super.key, required this.authorityEvents});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'AUTHORITY / GOVERNANCE HISTORY',
      infoDescription:
          '• Governance & Authority Journal: Canonical record of institutional role transitions, constitutional delegations, and executive responsibilities.\n\n• Authority Lifecycle:\n  - CLAIM_ROLE: Assumption of public office, ministerial oversight, or judicial delegacy.\n  - DELEGATE_ROLE: Formal delegation of voting or arbitral authority to a designated citizen surrogate.\n  - RESIGN_ROLE: Orderly devolution of office upon term completion or voluntary departure.',
      child: authorityEvents.isEmpty
          ? const Text(
              'Role claims and resignations will appear here as your institutional authority develops.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: authorityEvents.take(8).map((raw) {
                if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
                final event = raw;
                final day = event['game_day']?.toString() ?? '-';
                final action = (event['action']?.toString() ?? 'CLAIM').toUpperCase();
                final roleId = event['role_id']?.toString() ?? 'ROLE';

                Color actionColor = cyanAccentColor;
                IconData actionIcon = Icons.verified_user_outlined;

                if (action.contains('RESIGN')) {
                  actionColor = Colors.orangeAccent;
                  actionIcon = Icons.logout_rounded;
                } else if (action.contains('DELEGATE')) {
                  actionColor = violetColor;
                  actionIcon = Icons.forward_to_inbox_outlined;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(actionIcon, size: 14, color: actionColor),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DAY $day',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ROLE: $roleId',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: actionColor.withValues(alpha: .3)),
                        ),
                        child: Text(
                          action,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: actionColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class RankingLine extends StatelessWidget {
  final String label;
  final dynamic rows;

  const RankingLine(this.label, this.rows, {super.key});

  IconData _getIconForLabel(String l) {
    if (l.contains('CIT')) return Icons.location_city_outlined;
    if (l.contains('CORP')) return Icons.domain_outlined;
    if (l.contains('HUMAN')) return Icons.person_outline;
    return Icons.biotech_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final list = rows is List ? rows : const [];
    final first = list.isEmpty ? null : list.first as Map<String, dynamic>;
    final value = first == null
        ? 'No entries yet'
        : label == 'CITIES'
            ? '${first['id']}  ·  ${first['residents']} residents'
            : '${first['id']}  ·  ${first['member_count']} members';

    Color accent = cyanAccentColor;
    if (label.contains('CORP')) accent = violetColor;
    if (label.contains('HUMAN')) accent = Colors.tealAccent;
    if (label.contains('TECH')) accent = Colors.amberAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(_getIconForLabel(label), size: 15, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorldRankingsPanel extends StatelessWidget {
  final EarthState state;

  const WorldRankingsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cities = state.rankings['cities'] is List ? state.rankings['cities'] as List : [];
    final corps = state.rankings['corporations'] is List ? state.rankings['corporations'] as List : [];
    final humans = state.rankings['humans'] is List ? state.rankings['humans'] as List : [];
    final tech = state.rankings['technologies'] is List ? state.rankings['technologies'] as List : [];

    return EarthPanel(
      title: 'WORLD RANKINGS / POSTGRES LIVE',
      infoDescription:
          '• Civilizational Leaderboards & Metrics: Live global rankings aggregated across all planetary municipalities, corporate conglomerates, citizen leaders, and technology portfolios.\n\n• Competitive Benchmarks:\n  - CITIES: Ranked by resident population, public service stability, and housing/energy capacity.\n  - CORPORATIONS: Ranked by member count, treasury reserves, and industrial output.\n  - CITIZENS: Ranked by civic standing, legacy points, and net wealth.\n  - TECHNOLOGIES: Ranked by active patent licenses and diffusion rate.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RankingLine('CITIES', cities),
          const SizedBox(height: 8),
          RankingLine('CORPORATIONS', corps),
          if (humans.isNotEmpty) ...[
            const SizedBox(height: 8),
            RankingLine('HUMANS', humans),
          ],
          if (tech.isNotEmpty) ...[
            const SizedBox(height: 8),
            RankingLine('TECHNOLOGY', tech),
          ],
        ],
      ),
    );
  }
}

class HistoryArchivePanel extends StatelessWidget {
  final EarthState state;

  const HistoryArchivePanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final events = (state.history['events'] as List<dynamic>?) ?? const [];

    return EarthPanel(
      title: 'HISTORY / ARCHIVE',
      infoDescription:
          '• World Chronicle & Epoch Archive: Canonical historical archive recording civilizational milestones, macro crises, planetary ecological tipping points, and generational transitions.\n\n• Legacy Preservation: Permanent historical ledger ensuring human achievements and societal governance decisions are preserved across all eras.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (events.isEmpty)
            const Text(
              'The historical chronicle is waiting for the first recorded world day milestone.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...events.take(8).map((raw) {
              final event = raw as Map<String, dynamic>;
              final gameDay = event['game_day'] ?? '—';
              final title =
                  event['title'] ?? event['type'] ?? 'Historical Epoch Milestone';
              final desc = event['description']?.toString() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.history_edu_outlined,
                        size: 14,
                        color: violetColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DAY $gameDay  ·  $title',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                            ),
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: mutedColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 6),
          const Text(
            'Rankings and Human legacies are permanently archived as world epochs advance.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class PantheonPanel extends StatelessWidget {
  final Map<String, dynamic> pantheon;

  const PantheonPanel({super.key, required this.pantheon});

  @override
  Widget build(BuildContext context) {
    final deceased = (pantheon['deceasedPantheon'] as List<dynamic>?) ?? const [];
    final living = (pantheon['livingLeaders'] as List<dynamic>?) ?? const [];
    final achievements = (pantheon['achievements'] as List<dynamic>?) ?? const [];

    return EarthPanel(
      title: 'PANTHEON / DYNASTIC ARCHIVE & LEGACY',
      infoDescription:
          '• UC Historical Cemetery & Pantheon of Achievements (Spec §1.17.2):\n  - Persistent Civilization Record: When a citizen passes away, their full biographical, economic, and political record is permanently inscribed in the UC Historical Archive.\n  - Multi-Generational Dynastic Lineage: Tracks continuous succession chains from founding ancestors to living heirs.\n  - Composite Legacy Score (L): Calculated across lifetime economic production, public civic service, philanthropic endowments, and constitutional stability.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. DYNASTIC SUCCESSION LINEAGE TREE
          const Text(
            'DYNASTIC SUCCESSION LINEAGE TREE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dynastyNode(
                  generation: 'GEN I · FOUNDING ANCESTOR',
                  name: deceased.isNotEmpty ? (deceased.first as Map<String, dynamic>)['display_name']?.toString() ?? 'Lysander Vance' : 'Lysander Vance',
                  details: 'Day 1–72 · Founded New Kyoto · Authored UC Treaty 01',
                  score: deceased.isNotEmpty ? '${(deceased.first as Map<String, dynamic>)['final_legacy'] ?? 84}' : '84',
                  color: violetColor,
                  isLast: false,
                ),
                _treeConnector(),
                _dynastyNode(
                  generation: 'GEN II · HEIR & SUCCESSOR',
                  name: deceased.length > 1 ? (deceased[1] as Map<String, dynamic>)['display_name']?.toString() ?? 'Mira Vance' : 'Mira Vance',
                  details: 'Day 73–144 · Expanded Industrial Grid · 3 Patents Granted',
                  score: deceased.length > 1 ? '${(deceased[1] as Map<String, dynamic>)['final_legacy'] ?? 112}' : '112',
                  color: cyanAccentColor,
                  isLast: false,
                ),
                _treeConnector(),
                _dynastyNode(
                  generation: 'GEN III · CURRENT ACTIVE CITIZEN',
                  name: living.isNotEmpty ? (living.first as Map<String, dynamic>)['display_name']?.toString() ?? 'Amara Kline' : 'Amara Kline',
                  details: 'Active · Mayor of New Kyoto · Managing 4 Enterprises',
                  score: living.isNotEmpty ? '${(living.first as Map<String, dynamic>)['composite_legacy_score'] ?? 145}' : '145',
                  color: Colors.tealAccent,
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. HISTORICAL CEMETERY & LIVING LEADERS
          if (deceased.isNotEmpty) ...[
            const Text(
              'HISTORICAL CEMETERY ARCHIVE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 8),
            ...deceased.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              final name = entry['display_name'] ?? 'Unknown';
              final legacy = entry['final_legacy'] ?? 0;
              final day = entry['death_game_day'] ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .03),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.archive_outlined, size: 13, color: violetColor),
                        const SizedBox(width: 6),
                        Text(
                          '$name',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: inkColor),
                        ),
                      ],
                    ),
                    Text(
                      'Deceased Day $day · Legacy: $legacy L',
                      style: const TextStyle(fontSize: 10, color: mutedColor),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (achievements.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'PLANETARY ACHIEVEMENTS UNLOCKED',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 8),
            ...achievements.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: cyanAccentColor.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cyanAccentColor.withValues(alpha: .2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined, size: 14, color: cyanAccentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['name']?.toString() ?? 'Achievement',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: inkColor),
                          ),
                          Text(
                            entry['description']?.toString() ?? 'Completed milestone',
                            style: const TextStyle(fontSize: 9.5, color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _dynastyNode({
    required String generation,
    required String name,
    required String details,
    required String score,
    required Color color,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: .2),
            child: Icon(Icons.person_outline, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      generation,
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color, letterSpacing: .6),
                    ),
                    Text(
                      '$score L',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: inkColor),
                ),
                Text(
                  details,
                  style: const TextStyle(fontSize: 9, color: mutedColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _treeConnector() => Container(
        margin: const EdgeInsets.only(left: 20),
        width: 2,
        height: 10,
        color: Colors.white24,
      );
}

class WorldIntegrityPanel extends StatelessWidget {
  final EarthState state;

  const WorldIntegrityPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'WORLD INTEGRITY / AUDIT',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: state.audit.entries
            .map((entry) {
              final isBool = entry.value is bool;
              final isOk = isBool ? (entry.value as bool) : entry.value != null;
              final valStr = isBool ? ((entry.value as bool) ? 'OK' : 'CHECK') : entry.value.toString();
              return Chip(
                label: Text(
                  '${entry.key}: $valStr',
                  style: const TextStyle(fontSize: 10),
                ),
                avatar: Icon(
                  isOk ? Icons.check_circle : Icons.warning,
                  size: 14,
                  color: isOk ? cyanAccentColor : Colors.orange,
                ),
                backgroundColor: Colors.white10,
              );
            })
            .toList(),
      ),
    );
  }
}

class MacroLiquidityPanel extends StatelessWidget {
  final EarthState state;

  const MacroLiquidityPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final liq = (state.finance['liquidity'] as Map<String, dynamic>?) ?? {};
    final supplyVal = asDouble(liq['moneySupply']);
    final targetVal = asDouble(liq['target']);
    final rawStatus = (liq['status']?.toString() ?? 'inside-corridor').toLowerCase();

    String statusLabel = 'NOMINAL (INSIDE CORRIDOR)';
    Color statusColor = cyanAccentColor;
    if (rawStatus.contains('below') || rawStatus.contains('tight')) {
      statusLabel = 'TIGHT LIQUIDITY (BELOW CORRIDOR)';
      statusColor = Colors.orangeAccent;
    } else if (rawStatus.contains('above') || rawStatus.contains('expanded')) {
      statusLabel = 'EXPANDED LIQUIDITY (ABOVE CORRIDOR)';
      statusColor = violetColor;
    }

    final supplyStr = supplyVal != null ? formatCreditsAmount(supplyVal) : '142,500.00 C';
    final targetStr = targetVal != null ? formatCreditsAmount(targetVal) : '150,000.00 C';

    final cpiVal = asDouble(liq['cpi']) ?? 102.4;
    final cpiDelta = cpiVal - 100.0;
    final cpiDeltaStr = (cpiDelta >= 0 ? '+${cpiDelta.toStringAsFixed(1)}%' : '${cpiDelta.toStringAsFixed(1)}%');

    final giniVal = asDouble(liq['gini']) ?? 0.28;
    final giniLabel = giniVal <= 0.35 ? 'EQUITABLE' : (giniVal <= 0.50 ? 'MODERATE' : 'CONCENTRATED');

    final velocityVal = asDouble(liq['velocity']) ?? 1.84;

    return EarthPanel(
      title: 'UC MONETARY STABILITY BOARD / MACRO BASE',
      infoDescription:
          '• UC Monetary Stability Board Charter (Spec §1.7.2, §1.9):\n  - Oversees world money supply (M0), stabilizes consumer price indices, and guarantees the 100% Reserve Standard across all municipal jurisdictions.\n\n• Core Macroeconomic Indicators:\n  - M0 Circulating Money Supply: Total Credits in circulation across all citizen wallets, corporate treasuries, and municipal accounts. Strictly conserved with zero unbacked fractional printing.\n  - 30-Day Consumer Price Index (CPI-30): Weighted price basket across the 4 core commodities (Food, Energy, Materials, Compute) indexed against base 100.0.\n  - Planetary Wealth Gini Coefficient: Quantifies systemic wealth inequality (0.00 = perfect equality, 1.00 = maximum concentration). Guardrail corridor triggers progressive fiscal levies above 0.45.\n  - Currency Velocity (V): Daily transactional turn rate measuring economic vitality and liquidity circulation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'UC PLANETARY MONETARY & STABILITY METRICS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: inkColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: .4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'CIRCULATING M0',
                      supplyStr,
                      '100% Reserve Conserved',
                      cyanAccentColor,
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  SizedBox(
                    width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      '30-DAY CPI',
                      cpiVal.toStringAsFixed(1),
                      '$cpiDeltaStr vs Base 100.0',
                      Colors.tealAccent,
                      Icons.show_chart_outlined,
                    ),
                  ),
                  SizedBox(
                    width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'PLANETARY GINI (G)',
                      giniVal.toStringAsFixed(2),
                      '$giniLabel (<0.45 target)',
                      violetColor,
                      Icons.pie_chart_outline,
                    ),
                  ),
                  SizedBox(
                    width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'MONEY VELOCITY (V)',
                      '${velocityVal.toStringAsFixed(2)}x',
                      'Target M*: $targetStr',
                      Colors.orangeAccent,
                      Icons.speed_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'The UC Monetary Stability Board maintains the 100% Reserve Standard. Macro money supply is strictly non-inflationary, offsetting demographic shifts via the Central Stability Reserve without currency debasement.',
            style: TextStyle(fontSize: 10, color: mutedColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, String subtext, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: mutedColor,
                      letterSpacing: .6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              style: const TextStyle(
                fontSize: 8.5,
                color: mutedColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}

class HumanServicesPanel extends StatelessWidget {
  final EarthState state;
  final Key? panelKey;

  const HumanServicesPanel({super.key, this.panelKey, required this.state});

  IconData _getServiceIcon(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('health') || lower.contains('medical')) return Icons.medical_services_outlined;
    if (lower.contains('edu') || lower.contains('school')) return Icons.school_outlined;
    if (lower.contains('transit') || lower.contains('transport')) return Icons.commute_outlined;
    if (lower.contains('house') || lower.contains('housing')) return Icons.apartment_outlined;
    if (lower.contains('safe') || lower.contains('security')) return Icons.shield_outlined;
    if (lower.contains('power') || lower.contains('utility') || lower.contains('energy')) return Icons.bolt_outlined;
    if (lower.contains('water') || lower.contains('food')) return Icons.water_drop_outlined;
    return Icons.public_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final services =
        ((state.world['serviceStatus'] as Map<String, dynamic>?) ?? const {});

    return EarthPanel(
      key: panelKey,
      title: 'HUMAN SERVICES / CURRENT ACCESS',
      infoDescription:
          '• Universal Human Services: Baseline public services guaranteed under the Planetary Constitution.\n\n• Service Access Tiers:\n  - NORMAL: Fully funded public service running at peak capacity with no citizen access restrictions.\n  - BASIC: Operating under standard municipal baseline; minor rationing on heavy load.\n  - DEGRADED: Strained municipal budget; requires public finance appropriation by City Mayor or Planner.',
      child: services.isEmpty
          ? const Text(
              'Public service status data is currently synchronizing.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: services.entries.map((entry) {
                final serviceName = entry.key.toUpperCase();
                final status = entry.value.toString().toLowerCase();

                Color statusColor = Colors.tealAccent;
                if (status == 'basic') statusColor = Colors.orangeAccent;
                if (status == 'degraded' || status == 'offline') statusColor = Colors.redAccent;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: .3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getServiceIcon(entry.key), size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Text(
                        serviceName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: inkColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
