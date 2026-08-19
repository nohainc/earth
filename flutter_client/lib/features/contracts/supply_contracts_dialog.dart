import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

void showSupplyContractsDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String? initialContractId,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => SupplyContractsDialog(
      api: api,
      state: state,
      initialContractId: initialContractId,
    ),
  );
}

class SupplyContractsDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialContractId;
  final bool isPageMode;
  final ValueChanged<String>? onNavigate;

  const SupplyContractsDialog({
    super.key,
    required this.api,
    this.state,
    this.initialContractId,
    this.isPageMode = false,
    this.onNavigate,
  });

  @override
  State<SupplyContractsDialog> createState() => _SupplyContractsDialogState();
}

class _SupplyContractsDialogState extends State<SupplyContractsDialog> {
  int _activeTab = 0; // 0: Active, 1: Proposals, 2: New Proposal
  bool _loading = true;
  String? _error;
  String? _successMessage;

  List<Map<String, dynamic>> _contracts = [];
  Map<String, dynamic>? _selectedContract;
  List<Map<String, dynamic>> _selectedContractTicks = [];
  bool _loadingTicks = false;

  // Proposal Form State
  final _recipientController = TextEditingController(text: 'H-0012');
  final _titleController = TextEditingController();
  String _proposerRole = 'buyer';
  String _resourceType = 'energy';
  double _dailyQuantity = 50.0;
  double _unitPrice = 14.50;
  int _totalDays = 30;
  double _penaltyPerDefault = 100.0;
  bool _submittingProposal = false;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadContracts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await widget.api.supplyContracts();
      final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      Map<String, dynamic>? initial;
      if (widget.initialContractId != null) {
        initial = list.firstWhere(
          (c) => c['contract_id'] == widget.initialContractId,
          orElse: () => list.isNotEmpty ? list.first : {},
        );
      } else if (list.isNotEmpty) {
        initial = list.first;
      }

      if (mounted) {
        setState(() {
          _contracts = list;
          _selectedContract =
              initial != null && initial.isNotEmpty ? initial : null;
          _loading = false;
        });

        if (_selectedContract != null) {
          _loadContractTicks(_selectedContract!['contract_id'].toString());
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadContractTicks(String contractId) async {
    setState(() => _loadingTicks = true);
    try {
      final rawTicks = await widget.api.contractDeliveryTicks(contractId);
      final list =
          rawTicks.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _selectedContractTicks = list;
          _loadingTicks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTicks = false);
    }
  }

  Future<void> _acceptContract(String contractId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.acceptContract(contractId);
      if (mounted) {
        setState(() {
          _successMessage = 'Supply agreement accepted! Escrow vault locked.';
        });
        await _loadContracts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancelContract(String contractId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.cancelContract(contractId);
      if (mounted) {
        setState(() {
          _successMessage =
              'Agreement cancelled and remaining escrow refunded.';
        });
        await _loadContracts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitProposal() async {
    if (_recipientController.text.trim().isEmpty) {
      setState(() => _error = 'Counterparty ID or name is required');
      return;
    }

    setState(() {
      _submittingProposal = true;
      _error = null;
    });

    try {
      final res = await widget.api.proposeSupplyContract(
        counterpartyId: _recipientController.text.trim(),
        proposerRole: _proposerRole,
        resourceType: _resourceType,
        dailyQuantity: _dailyQuantity,
        unitPrice: _unitPrice,
        totalDays: _totalDays,
        penaltyPerDefault: _penaltyPerDefault,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
      );

      if (mounted) {
        setState(() {
          _submittingProposal = false;
          _successMessage =
              'Supply tender submitted! Awaiting counterparty acceptance.';
          _activeTab = 0;
        });
        await _loadContracts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submittingProposal = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeContracts =
        _contracts.where((c) => c['status'] == 'accepted').toList();
    final proposedContracts =
        _contracts.where((c) => c['status'] == 'proposed').toList();
    final historyContracts = _contracts
        .where((c) => c['status'] == 'completed' || c['status'] == 'cancelled')
        .toList();

    Widget content = Container(
      width: widget.isPageMode ? double.infinity : 1040,
      height: widget.isPageMode ? 740 : 720,
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : canvasColor,
        borderRadius: widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
        border: widget.isPageMode
            ? null
            : Border.all(color: EarthColors.borderSubtle),
        boxShadow: widget.isPageMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(200),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
        child: Column(
          children: [
            _buildTopBar(activeContracts.length, proposedContracts.length),
            if (_error != null) _buildAlertBanner(_error!, isError: true),
            if (_successMessage != null)
              _buildAlertBanner(_successMessage!, isError: false),
            Expanded(
              child: _loading && _contracts.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: EarthColors.cyanAccent))
                  : _buildTabBody(
                      activeContracts, proposedContracts, historyContracts),
            ),
          ],
        ),
      ),
    );

    if (widget.isPageMode) {
      return content;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: content,
    );
  }

  Widget _buildTopBar(int activeCount, int proposedCount) {
    return Container(
      padding: widget.isPageMode
          ? const EdgeInsets.only(bottom: 10)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : EarthColors.cardSurface,
        border: widget.isPageMode
            ? null
            : const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.handshake_outlined,
            color: widget.isPageMode
                ? EarthColors.textMuted
                : EarthColors.goldMetallic,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUTOMATED SUPPLY CONTRACTS & ESCROW VAULT',
                  style: TextStyle(
                    color: widget.isPageMode
                        ? EarthColors.textMuted
                        : EarthColors.goldMetallic,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  'B2B commodity flow agreements, automated daily settlements & guaranteed escrow reserves.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _topTabButton(
                    0, 'ACTIVE ($activeCount)', Icons.check_circle_outline),
                const SizedBox(width: 2),
                _topTabButton(
                    1, 'PROPOSALS ($proposedCount)', Icons.inbox_outlined,
                    badge: proposedCount),
                const SizedBox(width: 2),
                _topTabButton(2, 'NEW TENDER', Icons.add_circle_outline),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (widget.isPageMode)
            InkWell(
              onTap: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!('command');
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EarthColors.goldMetallic.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: EarthColors.goldMetallic.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back,
                        size: 11, color: EarthColors.goldMetallic),
                    SizedBox(width: 4),
                    Text(
                      'RETURN TO COMMAND',
                      style: TextStyle(
                        color: EarthColors.goldMetallic,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.close,
                  color: EarthColors.textMuted, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _topTabButton(int tabIndex, String label, IconData icon,
      {int badge = 0}) {
    final isSelected = _activeTab == tabIndex;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tabIndex;
          if (tabIndex == 0) {
            final active =
                _contracts.where((c) => c['status'] == 'accepted').toList();
            _selectedContract = active.isNotEmpty ? active.first : null;
          } else if (tabIndex == 1) {
            final proposed =
                _contracts.where((c) => c['status'] == 'proposed').toList();
            _selectedContract = proposed.isNotEmpty ? proposed.first : null;
          }
        });
        if (_selectedContract != null) {
          _loadContractTicks(_selectedContract!['contract_id'].toString());
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? EarthColors.goldMetallic : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.black : EarthColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final color = isError ? Colors.redAccent : EarthColors.cyanAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon:
                const Icon(Icons.close, size: 14, color: EarthColors.textMuted),
            onPressed: () => setState(() {
              _error = null;
              _successMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody(
    List<Map<String, dynamic>> activeList,
    List<Map<String, dynamic>> proposedList,
    List<Map<String, dynamic>> historyList,
  ) {
    if (_activeTab == 2) {
      return _buildProposalWizard();
    }

    final targetList = _activeTab == 0 ? activeList : proposedList;

    if (targetList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _activeTab == 0
                  ? Icons.inventory_2_outlined
                  : Icons.mark_email_read_outlined,
              size: 48,
              color: EarthColors.textMuted.withAlpha(100),
            ),
            const SizedBox(height: 12),
            Text(
              _activeTab == 0
                  ? 'No Active Supply Agreements'
                  : 'No Pending Supply Proposals',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _activeTab == 0
                  ? 'Propose a new recurring supply contract with automatic escrow settlement.'
                  : 'All incoming and outgoing proposals have been resolved.',
              style:
                  const TextStyle(color: EarthColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_activeTab == 0)
              ElevatedButton.icon(
                onPressed: () => setState(() => _activeTab = 2),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('PROPOSE SUPPLY CONTRACT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EarthColors.goldMetallic,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Left Column: Contract List
        Container(
          width: 380,
          decoration: const BoxDecoration(
            color: EarthColors.cardSurface,
            border: Border(right: BorderSide(color: EarthColors.borderSubtle)),
          ),
          child: ListView.builder(
            itemCount: targetList.length,
            itemBuilder: (ctx, i) {
              final item = targetList[i];
              final isSelected =
                  _selectedContract?['contract_id'] == item['contract_id'];
              return _buildContractListCard(item, isSelected);
            },
          ),
        ),

        // Right Column: Detail & Escrow Vault Inspector
        Expanded(
          child: _selectedContract != null
              ? _buildContractInspector(_selectedContract!)
              : const Center(
                  child: Text(
                      'Select an agreement to view details & escrow vault.',
                      style: TextStyle(color: EarthColors.textMuted)),
                ),
        ),
      ],
    );
  }

  Widget _buildContractListCard(Map<String, dynamic> item, bool isSelected) {
    final contractId = item['contract_id'] ?? '';
    final title = item['title'] ?? 'Supply Agreement';
    final resourceType = (item['resource_type'] ?? 'energy').toString();
    final dailyQty = _parseNum(item['daily_quantity']);
    final unitPrice = _parseNum(item['unit_price']);
    final totalDays = _parseInt(item['total_days']);
    final deliveredDays = _parseInt(item['delivered_days']);
    final totalEscrow = _parseNum(item['escrow_total']);
    final status = (item['status'] ?? 'proposed').toString();

    final progress =
        totalDays > 0 ? (deliveredDays / totalDays).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: () {
        setState(() => _selectedContract = item);
        _loadContractTicks(contractId);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? EarthColors.panelSurface : Colors.transparent,
          border: Border(
            bottom: const BorderSide(color: EarthColors.borderSubtle),
            left: BorderSide(
              color: isSelected ? EarthColors.goldMetallic : Colors.transparent,
              width: 3.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildCommodityBadge(resourceType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Rate: ${dailyQty.toStringAsFixed(1)} / day @ ${unitPrice.toStringAsFixed(2)} CR',
                    style: const TextStyle(
                        color: EarthColors.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${totalEscrow.toStringAsFixed(0)} CR Escrow',
                  style: const TextStyle(
                      color: EarthColors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
                ),
              ],
            ),
            if (status == 'accepted') ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      EarthColors.cyanAccent),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$deliveredDays / $totalDays Days Delivered',
                      style: const TextStyle(
                          color: EarthColors.textMuted, fontSize: 9.5)),
                  Text('${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: EarthColors.cyanAccent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContractInspector(Map<String, dynamic> c) {
    final contractId = c['contract_id'] ?? '';
    final title = c['title'] ?? 'Supply Agreement';
    final status = (c['status'] ?? 'proposed').toString();
    final resourceType = (c['resource_type'] ?? 'energy').toString();
    final dailyQty = _parseNum(c['daily_quantity']);
    final unitPrice = _parseNum(c['unit_price']);
    final totalDays = _parseInt(c['total_days']);
    final deliveredDays = _parseInt(c['delivered_days']);
    final defaultDays = _parseInt(c['default_days']);
    final consecutiveDefaults = _parseInt(c['consecutive_defaults']);
    final maxConsecutive =
        _parseInt(c['max_consecutive_defaults'], fallback: 3);
    final totalEscrow = _parseNum(c['escrow_total']);
    final remainingEscrow = _parseNum(c['escrow_remaining']);
    final penaltyPerDefault = _parseNum(c['penalty_per_default']);
    final proposerName =
        c['proposer_display_name'] ?? c['proposer_id'] ?? 'Proposer';
    final counterpartyName = c['counterparty_display_name'] ??
        c['counterparty_id'] ??
        'Counterparty';

    final progress =
        totalDays > 0 ? (deliveredDays / totalDays).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      color: EarthColors.panelSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildCommodityBadge(resourceType),
                        const SizedBox(width: 8),
                        Text(
                          contractId,
                          style: const TextStyle(
                              color: EarthColors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ],
                    ),
                    _buildStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: EarthColors.textMuted),
                    const SizedBox(width: 4),
                    Text('Proposer: $proposerName',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 16),
                    const Icon(Icons.handshake_outlined,
                        size: 14, color: EarthColors.textMuted),
                    const SizedBox(width: 4),
                    Text('Recipient: $counterpartyName',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Escrow Vault & Progress Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.cyanAccent.withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 16, color: EarthColors.cyanAccent),
                    SizedBox(width: 6),
                    Text(
                      'ESCROW VAULT METRICS',
                      style: TextStyle(
                        color: EarthColors.cyanAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.black45,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        EarthColors.cyanAccent),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    _buildMetricStat(
                        'Total Locked', '${totalEscrow.toStringAsFixed(2)} CR'),
                    _buildMetricStat('Delivered Progress',
                        '$deliveredDays / $totalDays Days (${(progress * 100).toStringAsFixed(0)}%)'),
                    _buildMetricStat('Remaining in Vault',
                        '${remainingEscrow.toStringAsFixed(2)} CR'),
                    _buildMetricStat('Default Penalty',
                        '${penaltyPerDefault.toStringAsFixed(0)} CR / tick'),
                  ],
                ),
                if (defaultDays > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ Warning: $defaultDays default(s) recorded. Consecutive defaults: $consecutiveDefaults / $maxConsecutive max before termination.',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Settlement Ticks Timeline
          const Text(
            'SETTLEMENT TICKS & DELIVERY AUDIT LOG',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EarthColors.borderSubtle),
              ),
              child: _loadingTicks
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: EarthColors.cyanAccent))
                  : (_selectedContractTicks.isEmpty
                      ? const Center(
                          child: Text(
                            'No delivery ticks recorded yet. First settlement occurs on the next game day.',
                            style: TextStyle(
                                color: EarthColors.textMuted, fontSize: 11),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _selectedContractTicks.length,
                          itemBuilder: (ctx, i) {
                            final tick = _selectedContractTicks[i];
                            final day = tick['game_day'] ?? 1;
                            final tickStatus =
                                (tick['status'] ?? 'delivered').toString();
                            final qtyDelivered =
                                _parseNum(tick['quantity_delivered']);
                            final creditsPaid =
                                _parseNum(tick['credits_transferred']);
                            final penaltyCharged =
                                _parseNum(tick['penalty_charged']);
                            final isDelivered = tickStatus == 'delivered';

                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Colors.white10)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isDelivered
                                        ? Icons.check_circle
                                        : Icons.warning_amber_rounded,
                                    size: 14,
                                    color: isDelivered
                                        ? EarthColors.cyanAccent
                                        : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Day $day',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      isDelivered
                                          ? 'Delivered ${qtyDelivered.toStringAsFixed(1)} $resourceType · ${creditsPaid.toStringAsFixed(2)} CR released'
                                          : 'Stockout Default · ${penaltyCharged.toStringAsFixed(2)} CR penalty transferred',
                                      style: TextStyle(
                                        color: isDelivered
                                            ? Colors.white70
                                            : Colors.redAccent.shade100,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDelivered
                                          ? EarthColors.cyanAccent.withAlpha(20)
                                          : Colors.redAccent.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tickStatus.toUpperCase(),
                                      style: TextStyle(
                                        color: isDelivered
                                            ? EarthColors.cyanAccent
                                            : Colors.redAccent,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )),
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (status == 'proposed') ...[
                OutlinedButton(
                  onPressed: () => _cancelContract(contractId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  child: const Text('DECLINE TENDER'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _acceptContract(contractId),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('ACCEPT AGREEMENT & LOCK ESCROW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.cyanAccent,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ] else if (status == 'accepted') ...[
                ElevatedButton.icon(
                  onPressed: () => _cancelContract(contractId),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('TERMINATE & REFUND REMAINING ESCROW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProposalWizard() {
    final totalCents = (_dailyQuantity * _unitPrice * _totalDays);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: EarthColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EarthColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TRANSMIT BINDING SUPPLY AGREEMENT TENDER',
                style: TextStyle(
                  color: EarthColors.goldMetallic,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Configure recurring daily resource deliveries and escrow funding parameters.',
                style: TextStyle(color: EarthColors.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 20),

              // Proposer Role & Recipient
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _proposerRole,
                      isExpanded: true,
                      dropdownColor: EarthColors.cardSurface,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Your Agreement Role',
                        filled: true,
                        fillColor: EarthColors.panelSurface,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'buyer',
                            child: Text('I am BUYER (Locking Escrow)')),
                        DropdownMenuItem(
                            value: 'seller',
                            child: Text('I am SELLER (Delivering Commodity)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _proposerRole = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _recipientController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Counterparty ID / Name',
                        hintText: 'e.g. H-0012',
                        filled: true,
                        fillColor: EarthColors.panelSurface,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title (Optional)
              TextField(
                controller: _titleController,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Custom Agreement Title (Optional)',
                  hintText: 'e.g. Neo-Tokyo Primary Quantum Core Energy Supply',
                  filled: true,
                  fillColor: EarthColors.panelSurface,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Commodity Resource Picker
              const Text(
                'SELECT COMMODITY RESOURCE',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _commodityOption('energy', 'Energy (kW)', Icons.bolt,
                      EarthResourceColors.energy),
                  const SizedBox(width: 8),
                  _commodityOption(
                      'food', 'Food (kg)', Icons.eco, EarthResourceColors.food),
                  const SizedBox(width: 8),
                  _commodityOption('material', 'Material (t)', Icons.layers,
                      EarthResourceColors.materials),
                  const SizedBox(width: 8),
                  _commodityOption('compute', 'Compute (FLOP)', Icons.memory,
                      EarthResourceColors.compute),
                ],
              ),
              const SizedBox(height: 16),

              // Daily Quantity & Unit Price Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Daily Quantity: ${_dailyQuantity.toStringAsFixed(0)} units',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5)),
                        Slider(
                          value: _dailyQuantity,
                          min: 5,
                          max: 500,
                          divisions: 99,
                          activeColor: EarthColors.cyanAccent,
                          onChanged: (v) => setState(() => _dailyQuantity = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Unit Price: ${_unitPrice.toStringAsFixed(2)} CR / unit',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5)),
                        Slider(
                          value: _unitPrice,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          activeColor: EarthColors.goldMetallic,
                          onChanged: (v) => setState(() => _unitPrice = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Duration & Penalty Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Agreement Duration: $_totalDays Game Days',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5)),
                        Slider(
                          value: _totalDays.toDouble(),
                          min: 7,
                          max: 180,
                          divisions: 173,
                          activeColor: EarthColors.cyanAccent,
                          onChanged: (v) =>
                              setState(() => _totalDays = v.toInt()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Breach Penalty / Default: ${_penaltyPerDefault.toStringAsFixed(0)} CR',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5)),
                        Slider(
                          value: _penaltyPerDefault,
                          min: 0,
                          max: 1000,
                          divisions: 100,
                          activeColor: Colors.redAccent,
                          onChanged: (v) =>
                              setState(() => _penaltyPerDefault = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EarthColors.panelSurface,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: EarthColors.cyanAccent.withAlpha(80)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Escrow Requirement:',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          '${totalCents.toStringAsFixed(2)} CREDITS',
                          style: const TextStyle(
                              color: EarthColors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Locked in Escrow Vault upon acceptance. Transferred at ${(_dailyQuantity * _unitPrice).toStringAsFixed(2)} CR/day for $_totalDays consecutive days.',
                      style: const TextStyle(
                          color: EarthColors.textMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Transmit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submittingProposal ? null : _submitProposal,
                  icon: _submittingProposal
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send, size: 16),
                  label: Text(_submittingProposal
                      ? 'TRANSMITTING TENDER...'
                      : 'TRANSMIT BINDING SUPPLY TENDER'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.goldMetallic,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _commodityOption(
      String type, String label, IconData icon, Color color) {
    final isSelected = _resourceType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _resourceType = type),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(30) : EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: isSelected ? color : EarthColors.borderSubtle),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? color : EarthColors.textMuted, size: 18),
              const SizedBox(height: 4),
              Text(
                type.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? color : EarthColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: EarthColors.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCommodityBadge(String resource) {
    Color color = EarthResourceColors.energy;
    IconData icon = Icons.bolt;
    if (resource == 'food') {
      color = EarthResourceColors.food;
      icon = Icons.eco;
    } else if (resource == 'material') {
      color = EarthResourceColors.materials;
      icon = Icons.layers;
    } else if (resource == 'compute') {
      color = EarthResourceColors.compute;
      icon = Icons.memory;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(resource.toUpperCase(),
              style: const TextStyle(
                  color: EarthColors.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'accepted') color = EarthColors.cyanAccent;
    if (status == 'proposed') color = EarthColors.goldMetallic;
    if (status == 'completed') color = Colors.greenAccent;
    if (status == 'cancelled') color = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        status.toUpperCase(),
        style:
            TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static int _parseInt(dynamic val, {int fallback = 0}) {
    if (val is num) return val.toInt();
    if (val is String)
      return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
    return fallback;
  }
}
