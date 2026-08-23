import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/nano_markup_helper.dart';
import '../../shared/design_system/design_system.dart';
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
    var expectedProfit = 0.0;
    var profitKnown = false;
    final counterparties = <String>{};
    var riskyCounterparties = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final amount =
          asDouble(raw['amount'] ?? raw['value'] ?? raw['total']) ?? 0;
      final cost = asDouble(
          raw['cost'] ?? raw['estimated_cost'] ?? raw['delivery_cost']);
      if (cost != null) {
        expectedProfit += amount - cost;
        profitKnown = true;
      }
      final status = (raw['status']?.toString() ?? 'proposed').toLowerCase();
      final kind = (raw['kind']?.toString() ?? raw['type']?.toString() ?? '')
          .toLowerCase();
      final counterparty = (raw['counterparty_name'] ??
              raw['counterparty'] ??
              raw['counterparty_id'])
          ?.toString();
      if (counterparty != null && counterparty.isNotEmpty) {
        counterparties.add(counterparty);
      }
      final reliability =
          asDouble(raw['counterparty_reliability'] ?? raw['reliability']);
      if (reliability != null && reliability < 50) riskyCounterparties++;
      final outgoingContract = kind.contains('supply') ||
          kind.contains('purchase') ||
          kind.contains('buy');
      if (outgoingContract) {
        outgoing += amount;
      } else {
        incoming += amount;
      }
      if (status == 'accepted' || status == 'active' || status == 'proposed') {
        active++;
      }
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

    return EarthSection(
      title: 'REVENUE & COMMITMENTS',
      showSurface: false,
      infoBulletPoints: const [
        'Revenue shows what your agreements may earn; commitments show what you must deliver or pay.',
        'A contract value is not profit. Review resources, staff, machines, taxes, and delivery risk before accepting.',
        'Supply agreements belong here operationally; Trade & Supplies remains the place for open-market orders.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'EXPECTED INCOMING',
                value: '${formatWholeNumber(incoming)} C',
                icon: Icons.trending_up_outlined,
                accentColor: context.successColor,
              ),
              EarthMetricTile(
                label: 'COMMITTED OUTGOING',
                value: '${formatWholeNumber(outgoing)} C',
                icon: Icons.trending_down_outlined,
                accentColor: context.warningColor,
              ),
              EarthMetricTile(
                label: 'ACTIVE AGREEMENTS',
                value: '$active',
                icon: Icons.handshake_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'VALUE AT RISK',
                value: '${formatWholeNumber(atRisk)} C',
                subtitle: '$disputed issue${disputed == 1 ? '' : 's'}',
                icon: Icons.warning_amber_outlined,
                accentColor: disputed == 0 ? context.successColor : context.warningColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),
          Text(
            'PIPELINE: $pipeline awaiting decision · $recurring recurring revenue stream${recurring == 1 ? '' : 's'} · $milestonesDue delivery milestone${milestonesDue == 1 ? '' : 's'} in progress.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 4),
          Text(
            profitKnown
                ? 'EXPECTED PROFIT: ${formatWholeNumber(expectedProfit)} C after recorded delivery costs.'
                : 'PROFITABILITY: unavailable until delivery costs are recorded.',
            style: context.widgetFooterStyle.copyWith(
              color: profitKnown && expectedProfit < 0
                  ? context.warningColor
                  : context.mutedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'COUNTERPARTIES: ${counterparties.isEmpty ? 'not itemized' : counterparties.join(' · ')} · ${riskyCounterparties == 0 ? 'no recorded high-risk relationship' : '$riskyCounterparties high-risk relationship${riskyCounterparties == 1 ? '' : 's'}'}',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 6),
          Text(
            'Before accepting: check delivery capacity, required supplies, deadline risk, cancellation penalties, and expected margin.',
            style: context.widgetTitleStyle.copyWith(color: context.inkColor),
          ),
        ],
      ),
    );
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

    return EarthSection(
      key: widget.panelKey,
      title: 'ACTIVE AGREEMENTS / DELIVERY & PAYMENT',
      showSurface: false,
      infoBulletPoints: const [
        'Bilateral Agreements & Escrow: Legally enforceable contractual obligations entered into between citizens or corporations.',
        'Lifecycle Stages: PROPOSED (awaiting counterparty), ACCEPTED (escrows active), DISPUTED (formal arbitration), COMPLETED (disbursed).',
        'Judicial Arbitration: Authorized OUC delegates arbitrate active disputes, issuing legally binding award resolutions.',
      ],
      trailing: EarthButton(
        label: 'PROPOSE NEW AGREEMENT',
        icon: Icons.add_rounded,
        variant: EarthButtonVariant.primary,
        onPressed: widget.busy
            ? null
            : () {
                EarthAudioEngine.instance.playClick();
                showContractComposerDialog(context, widget.action,
                    businesses: widget.state.businesses);
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. SUPPLY CONTRACTS & ESCROW VAULT LAUNCHER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: context.warningColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.warningColor.withValues(alpha: .3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: context.warningColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'B2B COMMODITY SUPPLY & ESCROW VAULT',
                          style: context.widgetTitleStyle.copyWith(
                            color: context.warningColor,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                EarthButton(
                  label: 'OPEN ESCROW VAULT',
                  icon: Icons.handshake_outlined,
                  variant: EarthButtonVariant.warning,
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    showSupplyContractsDialog(
                      context,
                      api: const EarthApi(),
                      state: widget.state,
                    );
                  },
                ),
              ],
            ),
          ),

          // 1. EXECUTIVE CONTRACT PORTFOLIO HEADER
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'ACTIVE AGREEMENTS',
                value: '$activeContractsCount',
                icon: Icons.handshake_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'COMMITTED ESCROWS',
                value: '${formatWholeNumber(totalContractValue)} C',
                icon: Icons.lock_clock_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'OPEN DISPUTES',
                value: '$disputedContractsCount',
                icon: Icons.gavel_outlined,
                accentColor: disputedContractsCount > 0
                    ? context.warningColor
                    : context.successColor,
              ),
            ],
          ),

          if (_statusFeedback != null) ...[
            SizedBox(height: context.spacingControl),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.secondaryColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(context.radiusControl),
                border: Border.all(color: context.secondaryColor.withValues(alpha: .3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.secondaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusFeedback!,
                      style: context.widgetFooterStyle.copyWith(color: context.inkColor),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: context.spacingTopic),

          // 2. CONTRACT AGREEMENTS STREAM
          if (contractList.isEmpty)
            const EarthEmptyState(
              message: 'No bilateral agreements on record.',
              icon: Icons.handshake_outlined,
            )
          else
            EarthDataList(
              children: contractList.take(12).map((raw) {
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
                final amountValue = asDouble(amount);
                final deliveryCost = asDouble(contract['cost'] ??
                    contract['estimated_cost'] ??
                    contract['delivery_cost']);
                final deliveryProgress = asDouble(
                    contract['progress'] ?? contract['delivery_progress']);
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

                EarthBadgeVariant badgeVariant = EarthBadgeVariant.neutral;
                if (status == 'accepted') badgeVariant = EarthBadgeVariant.primary;
                if (status == 'cancelled' || status == 'rejected') badgeVariant = EarthBadgeVariant.danger;
                if (isDisputed) badgeVariant = EarthBadgeVariant.warning;

                final rawTerms = contract['terms_json'] ?? contract['terms'];
                final dynamic decodedTerms = rawTerms is String
                    ? NanoMarkupHelper.decode(rawTerms)
                    : rawTerms;
                final Map<dynamic, dynamic>? termsMap =
                    decodedTerms is Map ? decodedTerms : null;

                return EarthDataRow(
                  title: '$title ($contractId)',
                  subtitle: 'Type: $kind · Value: $amount CR · Schedule: Day $startDay → Day $endDay\nParties: ${contract['proposer_name'] ?? proposerId} ⇄ ${contract['counterparty_name'] ?? counterpartyId}${termsMap != null && termsMap.isNotEmpty ? '\nTerms: ${termsMap.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}' : ''}${deliveryProgress != null ? '\nDelivery: ${deliveryProgress.toStringAsFixed(0)}%' : ''}${deliveryCost != null ? ' · Expected margin: ${formatWholeNumber((amountValue ?? 0) - deliveryCost)} CR' : ''}',
                  leading: Icon(_getContractIcon(kind.toLowerCase()), size: context.iconSize, color: context.primaryColor),
                  badges: [
                    EarthBadge(
                      label: isDisputed ? 'DISPUTED ($disputeStatus)' : status.toUpperCase(),
                      variant: badgeVariant,
                    ),
                  ],
                  trailing: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (status == 'proposed' && isCounterparty)
                        EarthButton(
                          label: 'ACCEPT',
                          icon: Icons.check_circle_outline,
                          variant: EarthButtonVariant.primary,
                          onPressed: isBusy
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  _handleAccept(contractId);
                                },
                        ),
                      if (status == 'proposed' && (isProposer || isCounterparty))
                        EarthButton(
                          label: 'CANCEL',
                          icon: Icons.cancel_outlined,
                          variant: EarthButtonVariant.danger,
                          onPressed: isBusy
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  _handleCancel(contractId);
                                },
                        ),
                      if ((status == 'accepted' || status == 'completed') && !isDisputed)
                        EarthButton(
                          label: 'OPEN DISPUTE',
                          icon: Icons.warning_amber_rounded,
                          variant: EarthButtonVariant.warning,
                          onPressed: isBusy
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  showDisputeDialog(context, widget.action, contractId);
                                },
                        ),
                      if (isDisputed && canArbitrate)
                        EarthButton(
                          label: 'ARBITRATE & RESOLVE',
                          icon: Icons.gavel_outlined,
                          variant: EarthButtonVariant.primary,
                          onPressed: isBusy
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  showResolveDialog(context, widget.action, contractId);
                                },
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
