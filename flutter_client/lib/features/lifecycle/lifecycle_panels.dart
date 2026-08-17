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
    final age = life['ageYears'] ?? human['age_years'] ?? human['ageYears'] ?? 31;
    final politicalEligibleDay = life['politicalEligibilityDay'] ?? 180;
    final currentDay = state.clock['day'] ?? 184;
    final isPoliticallyEligible = (currentDay is num && currentDay >= politicalEligibleDay) || (age is num && age >= 25);

    final rawSuccessor = life['successor'];
    final successor = rawSuccessor is Map<String, dynamic> ? rawSuccessor : null;
    final successorName = successor?['successor_name']?.toString() ?? successor?['name']?.toString();
    final successorHumanId = successor?['successor_human_id']?.toString() ?? successor?['successorHumanId']?.toString();
    final registeredDay = successor?['registered_game_day'] ?? successor?['registeredOnDay'];
    final estatePeriodDays = successor?['estate_period_days'] ?? life['estatePeriodDays'] ?? 30;

    final isEstatePeriod = lifeStatus == 'estate';
    final isDeceased = lifeStatus == 'deceased';

    Color statusColor = cyanAccentColor;
    if (isEstatePeriod) statusColor = Colors.orangeAccent;
    if (isDeceased) statusColor = Colors.redAccent;

    return EarthPanel(
      title: 'LIFE / SUCCESSION & ESTATE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Age: $age years · ${isPoliticallyEligible ? 'Politically mature' : 'Political lock (Day $politicalEligibleDay)'}',
                  style: const TextStyle(color: mutedColor, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lifeStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (successorName != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Successor: $successorName ${successorHumanId != null ? '($successorHumanId)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Registered on Day $registeredDay · Estate buffer: $estatePeriodDays days',
                    style: const TextStyle(fontSize: 10, color: mutedColor),
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
              OutlinedButton(
                onPressed: busy ? null : () => showSuccessorComposerDialog(context, action),
                child: Text(successorName == null ? 'PLAN SUCCESSION' : 'UPDATE SUCCESSION PLAN'),
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
      child: state.financeStatus.isEmpty
          ? const Text(
              'Financial states will appear after the next world-day assessment.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.financeStatus.map((raw) {
                final item = raw as Map<String, dynamic>;
                final crisis = item['status'] == 'distressed' ||
                    item['status'] == 'insolvent';
                final recoverable = item['institution_kind'] == 'CITY' ||
                    item['institution_kind'] == 'CORPORATION';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['institution_kind']} ${item['institution_id']}  ·  ${item['status']}  ·  since day ${item['since_game_day']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      if (crisis && recoverable)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showRecoveryDialog(
                                    context,
                                    action,
                                    item['institution_id'] as String,
                                    item['institution_kind'] as String,
                                  ),
                          child: const Text('RECOVER'),
                        ),
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
    return EarthPanel(
      title: 'CENTRAL LEDGER / RECENT ACTIVITY',
      child: state.ledgerEntries.isEmpty
          ? const Text('No ledger activity yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.ledgerEntries.take(8).map((raw) {
                final entry = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${entry['reason_type']}  ·  ${entry['amount']} ${entry['currency']}\n${entry['debit_account']} → ${entry['credit_account']}',
                    style: const TextStyle(fontSize: 12),
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
      child: ownershipEvents.isEmpty
          ? const Text(
              'Your asset history will appear here after your first acquisition or transfer.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ownershipEvents.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                final direction =
                    event['from_owner_id'] == null ? 'acquired' : 'transferred';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DAY ${event['game_day']}  ·  ${event['asset_type']} ${event['asset_id']} $direction  ·  ${event['quantity']}',
                    style: const TextStyle(fontSize: 11),
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
      child: membershipEvents.isEmpty
          ? const Text(
              'Your civic and corporate history will appear here after joining an institution.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: membershipEvents.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DAY ${event['game_day']}  ·  ${event['institution_type']} ${event['institution_id']}  ·  ${event['action']}',
                    style: const TextStyle(fontSize: 11),
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
      child: authorityEvents.isEmpty
          ? const Text(
              'Role claims and resignations will appear here as your institutional authority develops.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: authorityEvents.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DAY ${event['game_day']}  ·  ${event['action']}  ·  ROLE ${event['role_id']}',
                    style: const TextStyle(fontSize: 11),
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

  @override
  Widget build(BuildContext context) {
    final list = rows is List ? rows : const [];
    final first = list.isEmpty ? null : list.first as Map<String, dynamic>;
    final value = first == null
        ? 'No entries yet'
        : label == 'CITIES'
            ? '${first['id']}  ·  ${first['residents']} residents'
            : '${first['id']}  ·  ${first['member_count']} members';
    return Row(
      children: [
        Text(
          label,
          style:
              const TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (events.isEmpty)
            const Text('The archive is waiting for the first recorded world day.')
          else
            ...events.take(6).map((raw) {
              final event = raw as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'DAY ${event['game_day'] ?? '—'}  ·  ${event['title'] ?? event['type'] ?? 'Historical Event'}',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }),
          const SizedBox(height: 6),
          const Text(
            'Rankings and Human legacies are preserved as the world changes.',
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
      title: 'PANTHEON / ACHIEVEMENTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Legacy is measured across generations, not only by current wealth.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 10),
          if (deceased.isEmpty && living.isEmpty && achievements.isEmpty)
            const Text('No recorded achievements yet.'),
          if (deceased.isNotEmpty) ...[
            const Text('DECEASED PANTHEON',
                style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
            ...deceased.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              return Text(
                '${entry['display_name']}  ·  legacy ${entry['final_legacy'] ?? 0}',
                style: const TextStyle(fontSize: 11),
              );
            }),
          ],
          if (living.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('LIVING LEADERS',
                style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
            ...living.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              return Text(
                '${entry['display_name']}  ·  score ${entry['composite_legacy_score'] ?? 0}',
                style: const TextStyle(fontSize: 11),
              );
            }),
          ],
          if (achievements.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('ACHIEVEMENTS UNLOCKED',
                style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
            ...achievements.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              return Text(
                '${entry['name']}  ·  ${entry['description'] ?? 'Completed'}',
                style: const TextStyle(fontSize: 11),
              );
            }),
          ],
        ],
      ),
    );
  }
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
            .map((entry) => Chip(
                  label: Text(
                    '${entry.key}: ${entry.value ? 'OK' : 'CHECK'}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  avatar: Icon(
                    entry.value ? Icons.check_circle : Icons.warning,
                    size: 14,
                    color: entry.value ? cyanAccentColor : Colors.orange,
                  ),
                  backgroundColor: Colors.white10,
                ))
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

    return EarthPanel(
      title: 'MACRO LIQUIDITY / WORLD ENGINE SIGNAL',
      infoDescription:
          'Systemic monetary base and liquidity tracking active money supply against the planetary economic target corridor.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'UNIVERSAL COALITION MONETARY EQUILIBRIUM',
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _metricBlock('CIRCULATING MONEY SUPPLY', supplyStr, cyanAccentColor),
              _metricBlock('MACRO TARGET (M*)', targetStr, mutedColor),
              _metricBlock('STABILIZATION BUFFER', 'Active (±20% Corridor)', Colors.tealAccent),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The UC World Engine dynamically buffers systemic money supply against demographic population shifts to prevent deflationary liquidity stalls and runaway debasement.',
            style: TextStyle(fontSize: 10, color: mutedColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _metricBlock(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: mutedColor, letterSpacing: .8),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      );
}

class HumanServicesPanel extends StatelessWidget {
  final EarthState state;
  final Key? panelKey;

  const HumanServicesPanel({super.key, this.panelKey, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      key: panelKey,
      title: 'HUMAN SERVICES / CURRENT ACCESS',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ((state.world['serviceStatus'] as Map<String, dynamic>?) ??
                const {})
            .entries
            .map((entry) => Chip(
                  label: Text('${entry.key.toUpperCase()}  ·  ${entry.value}'),
                  backgroundColor: entry.value == 'normal'
                      ? Colors.teal.withValues(alpha: .18)
                      : entry.value == 'basic'
                          ? Colors.orange.withValues(alpha: .18)
                          : Colors.red.withValues(alpha: .18),
                ))
            .toList(),
      ),
    );
  }
}
