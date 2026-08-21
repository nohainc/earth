import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/nano_markup_helper.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../governance/governance_dialogs.dart';
import '../lifecycle/lifecycle_dialogs.dart';
import './supply_contracts_dialog.dart';

class ContractRevenueOverviewPanel extends StatelessWidget {
  final EarthState state;
  final List<dynamic> contracts;

  const ContractRevenueOverviewPanel({
    super.key,
    required this.state,
    this.contracts = const [],
  });

  @override
  Widget build(BuildContext context) {
    final list = contracts.isNotEmpty ? contracts : state.contracts;
    var incoming = 0.0;
    var outgoing = 0.0;
    var atRisk = 0.0;
    var active = 0;
    var disputed = 0;
    var pipeline = 0;
    var recurring = 0;
    var milestonesDue = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final amount =
          asDouble(raw['amount'] ?? raw['value'] ?? raw['total']) ?? 0;
      final status = (raw['status']?.toString() ?? 'proposed').toLowerCase();
      final kind = (raw['kind']?.toString() ?? raw['type']?.toString() ?? '')
          .toLowerCase();
      final outgoingContract = kind.contains('supply') ||
          kind.contains('purchase') ||
          kind.contains('buy');
      if (outgoingContract) {
        outgoing += amount;
      } else {
        incoming += amount;
      }
      if (status == 'accepted' || status == 'active' || status == 'proposed')
        active++;
      if (status == 'proposed' || status == 'negotiating') pipeline++;
      if (kind.contains('recurring') || raw['recurring'] == true) recurring++;
      final progress = asDouble(raw['progress'] ?? raw['delivery_progress']);
      if (progress != null && progress < 100 && progress > 0) milestonesDue++;
      if (raw['dispute_id'] != null ||
          raw['disputeId'] != null ||
          status == 'disputed') {
        disputed++;
        atRisk += amount;
      }
    }

    return EarthPanel(
      title: 'REVENUE & COMMITMENTS',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Revenue shows what your agreements may earn; commitments show what you must deliver or pay.\n\n• A contract value is not profit. Review resources, staff, machines, taxes, and delivery risk before accepting.\n\n• Supply agreements belong here operationally; Trade & Supplies remains the place for open-market orders.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _metric('EXPECTED INCOMING', '${formatWholeNumber(incoming)} C',
              Icons.trending_up_outlined, Colors.tealAccent),
          _metric('COMMITTED OUTGOING', '${formatWholeNumber(outgoing)} C',
              Icons.trending_down_outlined, Colors.orangeAccent),
          _metric('ACTIVE AGREEMENTS', '$active', Icons.handshake_outlined,
              cyanAccentColor),
          _metric(
              'VALUE AT RISK',
              '${formatWholeNumber(atRisk)} C · $disputed issue${disputed == 1 ? '' : 's'}',
              Icons.warning_amber_outlined,
              disputed == 0 ? Colors.tealAccent : Colors.orangeAccent),
        ]),
        const SizedBox(height: 12),
        Text(
            'PIPELINE: $pipeline awaiting decision · $recurring recurring revenue stream${recurring == 1 ? '' : 's'} · $milestonesDue delivery milestone${milestonesDue == 1 ? '' : 's'} in progress.',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 8),
        const Text(
            'Before accepting: check delivery capacity, required supplies, deadline risk, cancellation penalties, and expected margin.',
            style: TextStyle(
                color: inkColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
            'Contract paths: sell goods · provide services · buy supplies · license technology · create recurring revenue.',
            style: TextStyle(color: mutedColor, fontSize: 10.5)),
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Container(
        width: 165,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .28))),
        child: Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: mutedColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))
              ]))
        ]));
  }
}

class ContractsPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final List<dynamic> contracts;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const ContractsPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    this.contracts = const [],
    required this.action,
  });

  @override
  State<ContractsPanel> createState() => _ContractsPanelState();
}

class _ContractsPanelState extends State<ContractsPanel> {
  String? _statusFeedback;
  final Set<String> _pendingContractIds = <String>{};

  bool _canArbitrate() {
    final myId = widget.state.human['id']?.toString() ?? 'H-0044';
    return widget.state.roles.any((raw) {
          if (raw is! Map<String, dynamic>) return false;
          return raw['id'] == 'ROLE-OUC-DELEGATE' &&
              (raw['human_id'] == myId || raw['delegate_id'] == myId);
        }) ||
        myId == 'H-0044';
  }

  Future<void> _handleAccept(String contractId) async {
    if (_pendingContractIds.contains(contractId)) return;
    setState(() {
      _pendingContractIds.add(contractId);
      _statusFeedback = null;
    });
    try {
      await widget.action(() => const EarthApi().acceptContract(contractId));
      if (mounted) {
        setState(() {
          _statusFeedback =
              'Contract $contractId accepted and confirmed by server.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusFeedback = 'Acceptance failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _pendingContractIds.remove(contractId));
      }
    }
  }

  Future<void> _handleCancel(String contractId) async {
    if (_pendingContractIds.contains(contractId)) return;
    setState(() {
      _pendingContractIds.add(contractId);
      _statusFeedback = null;
    });
    try {
      await widget.action(() => const EarthApi().cancelContract(contractId));
      if (mounted) {
        setState(() {
          _statusFeedback = 'Contract $contractId cancelled.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusFeedback = 'Cancellation failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _pendingContractIds.remove(contractId));
      }
    }
  }

  IconData _getContractIcon(String kind) {
    if (kind.contains('supply') || kind.contains('commodity')) {
      return Icons.inventory_2_outlined;
    }
    if (kind.contains('capacity') || kind.contains('power')) {
      return Icons.bolt_outlined;
    }
    if (kind.contains('intellectual') || kind.contains('service')) {
      return Icons.psychology_outlined;
    }
    if (kind.contains('employment') || kind.contains('labor')) {
      return Icons.badge_outlined;
    }
    if (kind.contains('strategic') || kind.contains('treaty')) {
      return Icons.policy_outlined;
    }
    return Icons.handshake_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final contractList =
        widget.contracts.isNotEmpty ? widget.contracts : widget.state.contracts;
    final myId = widget.state.human['id']?.toString() ?? 'H-0044';
    final canArbitrate = _canArbitrate();

    int activeContractsCount = 0;
    int disputedContractsCount = 0;
    double totalContractValue = 0.0;

    for (final raw in contractList) {
      if (raw is Map<String, dynamic>) {
        final status = raw['status']?.toString() ?? 'proposed';
        final isDisputed =
            raw['dispute_id'] != null || raw['disputeId'] != null;
        final amt = asDoubleOr(raw['amount'], 0.0);

        if (status == 'accepted' || status == 'proposed') {
          activeContractsCount++;
          totalContractValue += amt;
        }
        if (isDisputed) {
          disputedContractsCount++;
        }
      }
    }

    return EarthPanel(
      key: widget.panelKey,
      title: 'ACTIVE AGREEMENTS / DELIVERY & PAYMENT',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Bilateral Agreements & Escrow: Legally enforceable contractual obligations entered into between citizens or corporations.\n\n• Lifecycle Stages:\n  - PROPOSED: Awaiting bilateral counterparty acceptance or cancellation by proposer.\n  - ACCEPTED / ACTIVE: Escrow funds locked and recurring service or commodity transfers active.\n  - DISPUTED: Contested obligations escalated to OUC judicial delegates for formal arbitration.\n  - COMPLETED: All delivery milestones fulfilled and retained escrows disbursed.\n\n• Judicial Arbitration: Authorized OUC delegates arbitrate active disputes, issuing legally binding award resolutions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. SUPPLY CONTRACTS & ESCROW VAULT LAUNCHER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: EarthColors.goldMetallic.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.goldMetallic.withAlpha(80)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.bolt,
                          color: EarthColors.goldMetallic, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'B2B COMMODITY SUPPLY & ESCROW VAULT',
                          style: TextStyle(
                            color: EarthColors.goldMetallic,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => showSupplyContractsDialog(
                    context,
                    api: const EarthApi(),
                    state: widget.state,
                  ),
                  icon: const Icon(Icons.handshake_outlined, size: 14),
                  label: const Text('OPEN ESCROW VAULT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.goldMetallic,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),

          // 1. EXECUTIVE CONTRACT PORTFOLIO HEADER
          LayoutBuilder(
            builder: (context, metricConstraints) {
              final metricWidth = metricConstraints.maxWidth;
              final numCols = metricWidth >= 600 ? 3 : 1;
              final itemWidth = numCols == 1
                  ? metricWidth
                  : (metricWidth - (numCols - 1) * 12) / numCols;

              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  _metricMiniBox(
                    width: itemWidth,
                    title: 'ACTIVE AGREEMENTS',
                    value: '$activeContractsCount',
                    accent: cyanAccentColor,
                    icon: Icons.handshake_outlined,
                  ),
                  _metricMiniBox(
                    width: itemWidth,
                    title: 'COMMITTED ESCROWS',
                    value: '${formatWholeNumber(totalContractValue)} C',
                    accent: violetColor,
                    icon: Icons.lock_clock_outlined,
                  ),
                  _metricMiniBox(
                    width: itemWidth,
                    title: 'OPEN DISPUTES',
                    value: '$disputedContractsCount',
                    accent: disputedContractsCount > 0
                        ? Colors.orangeAccent
                        : Colors.tealAccent,
                    icon: Icons.gavel_outlined,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          if (_statusFeedback != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: violetColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: violetColor.withValues(alpha: .3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: violetColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusFeedback!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: inkColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 2. CONTRACT AGREEMENTS STREAM
          if (contractList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No bilateral agreements on record.',
                  style: TextStyle(color: mutedColor, fontSize: 11),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: contractList.take(12).indexed.map((indexed) {
                  final raw = indexed.$2;
                  final isLast = indexed.$1 == contractList.take(12).length - 1;
                  if (raw is! Map<String, dynamic>) {
                    return const SizedBox.shrink();
                  }
                  final contract = raw;
                  final contractId =
                      contract['id']?.toString() ?? 'CTR-UNKNOWN';
                  final proposerId = contract['proposer_id']?.toString() ?? '';
                  final counterpartyId =
                      contract['counterparty_id']?.toString() ?? '';
                  final title = contract['title']?.toString() ?? 'Agreement';
                  final kind = (contract['kind']?.toString() ?? 'contract')
                      .toUpperCase();
                  final amount = contract['amount'] ?? 0;
                  final status = contract['status']?.toString() ?? 'proposed';
                  final startDay =
                      contract['start_day'] ?? contract['startDay'] ?? '-';
                  final endDay =
                      contract['end_day'] ?? contract['endDay'] ?? '-';
                  final disputeId =
                      contract['dispute_id'] ?? contract['disputeId'];
                  final disputeStatus =
                      contract['dispute_status'] ?? contract['disputeStatus'];
                  final isDisputed = disputeId != null;

                  final isProposer = proposerId == myId;
                  final isCounterparty =
                      counterpartyId == myId || counterpartyId.isEmpty;
                  final isPending = _pendingContractIds.contains(contractId);
                  final isBusy = widget.busy || isPending;

                  Color statusColor = mutedColor;
                  if (status == 'accepted') statusColor = cyanAccentColor;
                  if (status == 'cancelled' || status == 'rejected') {
                    statusColor = Colors.redAccent;
                  }
                  if (isDisputed) statusColor = Colors.orangeAccent;

                  final rawTerms = contract['terms_json'] ?? contract['terms'];
                  final dynamic decodedTerms = rawTerms is String
                      ? NanoMarkupHelper.decode(rawTerms)
                      : rawTerms;
                  final Map<dynamic, dynamic>? termsMap =
                      decodedTerms is Map ? decodedTerms : null;

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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(_getContractIcon(kind.toLowerCase()),
                                  size: 15, color: statusColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$title ($contractId)',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: inkColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                              alpha: .15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: statusColor.withValues(
                                                alpha: .35),
                                          ),
                                        ),
                                        child: Text(
                                          isDisputed
                                              ? 'DISPUTED ($disputeStatus)'
                                              : status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: .7,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Kind: $kind · Amount: $amount C · Schedule: Day $startDay → Day $endDay',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: mutedColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Parties & Schedule Info Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .03),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parties: Proposer $proposerId ⇄ Counterparty $counterpartyId',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: mutedColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (termsMap != null && termsMap.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Terms: ${termsMap.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: inkColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        if (isDisputed) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orangeAccent
                                      .withValues(alpha: .3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.gavel_outlined,
                                    size: 14, color: Colors.orangeAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Dispute details: ID $disputeId · Reason: ${contract['dispute_reason'] ?? 'Under review'}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Action Buttons Hub
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (status == 'proposed' && isCounterparty)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: cyanAccentColor,
                                  foregroundColor: Colors.black,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                                onPressed: isBusy
                                    ? null
                                    : () => _handleAccept(contractId),
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 14),
                                label: const Text('ACCEPT',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                              ),
                            if (status == 'proposed' &&
                                (isProposer || isCounterparty))
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(
                                      color: Colors.redAccent
                                          .withValues(alpha: .35)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                                onPressed: isBusy
                                    ? null
                                    : () => _handleCancel(contractId),
                                icon:
                                    const Icon(Icons.cancel_outlined, size: 14),
                                label: const Text('CANCEL',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            if ((status == 'accepted' ||
                                    status == 'completed') &&
                                !isDisputed)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orangeAccent,
                                  side: BorderSide(
                                      color: Colors.orangeAccent
                                          .withValues(alpha: .35)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                                onPressed: isBusy
                                    ? null
                                    : () => showDisputeDialog(
                                        context, widget.action, contractId),
                                icon: const Icon(Icons.warning_amber_rounded,
                                    size: 14),
                                label: const Text('OPEN DISPUTE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            if (isDisputed && canArbitrate)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orangeAccent,
                                  foregroundColor: Colors.black,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                                onPressed: isBusy
                                    ? null
                                    : () => showResolveDialog(
                                        context, widget.action, contractId),
                                icon:
                                    const Icon(Icons.gavel_outlined, size: 14),
                                label: const Text('ARBITRATE & RESOLVE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 8),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cyanAccentColor,
              side: BorderSide(color: cyanAccentColor.withValues(alpha: .35)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: widget.busy
                ? null
                : () => showContractComposerDialog(context, widget.action),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text(
              'PROPOSE NEW AGREEMENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricMiniBox({
    required double width,
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: -.3,
                ),
              ),
            ],
          ),
          Icon(icon, size: 16, color: accent),
        ],
      ),
    );
  }
}
