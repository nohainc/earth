import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/nano_markup_helper.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../governance/governance_dialogs.dart';
import '../lifecycle/lifecycle_dialogs.dart';

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
    }) || myId == 'H-0044';
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
          _statusFeedback = 'Contract $contractId accepted and confirmed by server.';
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

  @override
  Widget build(BuildContext context) {
    final contractList = widget.contracts.isNotEmpty
        ? widget.contracts
        : widget.state.contracts;
    final myId = widget.state.human['id']?.toString() ?? 'H-0044';
    final canArbitrate = _canArbitrate();

    return EarthPanel(
      key: widget.panelKey,
      title: 'NEGOTIATED CONTRACTS & ARBITRATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statusFeedback != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _statusFeedback!,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ],
          if (contractList.isEmpty)
            const Text(
              'No bilateral agreements on record.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...contractList.take(12).map((raw) {
              if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
              final contract = raw;
              final contractId = contract['id']?.toString() ?? 'CTR-UNKNOWN';
              final proposerId = contract['proposer_id']?.toString() ?? '';
              final counterpartyId = contract['counterparty_id']?.toString() ?? '';
              final title = contract['title']?.toString() ?? 'Agreement';
              final kind = contract['kind']?.toString() ?? 'contract';
              final amount = contract['amount'] ?? 0;
              final status = contract['status']?.toString() ?? 'proposed';
              final startDay = contract['start_day'] ?? contract['startDay'] ?? '-';
              final endDay = contract['end_day'] ?? contract['endDay'] ?? '-';
              final disputeId = contract['dispute_id'] ?? contract['disputeId'];
              final disputeStatus = contract['dispute_status'] ?? contract['disputeStatus'];
              final isDisputed = disputeId != null;

              final isProposer = proposerId == myId;
              final isCounterparty = counterpartyId == myId || counterpartyId.isEmpty;
              final isPending = _pendingContractIds.contains(contractId);
              final isBusy = widget.busy || isPending;

              Color statusColor = mutedColor;
              if (status == 'accepted') statusColor = cyanAccentColor;
              if (status == 'cancelled' || status == 'rejected') statusColor = Colors.redAccent;
              if (isDisputed) statusColor = Colors.orangeAccent;

                    final rawTerms = contract['terms_json'] ?? contract['terms'];
                    final dynamic decodedTerms = rawTerms is String ? NanoMarkupHelper.decode(rawTerms) : rawTerms;
                    final Map<dynamic, dynamic>? termsMap = decodedTerms is Map ? decodedTerms : null;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(6),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '$title ($contractId)',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isDisputed ? 'DISPUTED ($disputeStatus)' : status.toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kind: $kind · Amount: $amount C · Schedule: Day $startDay → Day $endDay',
                            style: const TextStyle(fontSize: 11, color: mutedColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Parties: Proposer $proposerId ⇄ Counterparty $counterpartyId',
                            style: const TextStyle(fontSize: 10, color: mutedColor),
                          ),
                          if (termsMap != null && termsMap.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Terms: ${termsMap.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                            ),
                          ],
                          if (isDisputed) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Dispute details: ID $disputeId · Reason: ${contract['dispute_reason'] ?? 'Under review'}',
                              style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
                            ),
                          ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        // Accept: Available only for proposed contracts where current user is counterparty
                        if (status == 'proposed' && isCounterparty)
                          OutlinedButton(
                            onPressed: isBusy ? null : () => _handleAccept(contractId),
                            child: const Text('ACCEPT'),
                          ),
                        // Cancel: Available for proposed contracts by proposer or counterparty
                        if (status == 'proposed' && (isProposer || isCounterparty))
                          OutlinedButton(
                            onPressed: isBusy ? null : () => _handleCancel(contractId),
                            child: const Text('CANCEL'),
                          ),
                        // Dispute: Available for accepted or completed contracts with no active dispute
                        if ((status == 'accepted' || status == 'completed') && !isDisputed)
                          OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => showDisputeDialog(context, widget.action, contractId),
                            child: const Text('OPEN DISPUTE'),
                          ),
                        // Arbitrate: Available for authorized delegates/arbitrators on disputed contracts
                        if (isDisputed && canArbitrate)
                          OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => showResolveDialog(context, widget.action, contractId),
                            child: const Text('ARBITRATE & RESOLVE'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.busy
                ? null
                : () => showContractComposerDialog(context, widget.action),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('PROPOSE NEW AGREEMENT'),
          ),
        ],
      ),
    );
  }
}
