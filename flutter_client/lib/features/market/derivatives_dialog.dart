import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import 'candlestick_chart_widget.dart';

void showDerivativesDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String initialCommodity = 'energy',
}) {
  EarthAudioEngine.instance.playClick();
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => DerivativesDialog(
      api: api,
      state: state,
      initialCommodity: initialCommodity,
    ),
  );
}

class DerivativesDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String initialCommodity;

  const DerivativesDialog({
    super.key,
    required this.api,
    this.state,
    this.initialCommodity = 'energy',
  });

  @override
  State<DerivativesDialog> createState() => _DerivativesDialogState();
}

class _DerivativesDialogState extends State<DerivativesDialog> {
  late String _selectedCommodity;
  bool _loading = true;
  String? _error;
  String? _successMessage;
  bool _isActionInProgress = false;

  List<Map<String, dynamic>> _ohlc = [];
  List<double?> _ma7 = [];
  List<double?> _ma25 = [];
  List<Map<String, dynamic>> _orderbook = [];
  List<Map<String, dynamic>> _userPositions = [];

  final _sizeCtrl = TextEditingController(text: '100');
  final _strikeCtrl = TextEditingController(text: '30.00');
  final _expiryCtrl = TextEditingController(text: '220');

  final List<String> _commodities = ['energy', 'material', 'compute', 'food'];

  @override
  void initState() {
    super.initState();
    _selectedCommodity = widget.initialCommodity.toLowerCase();
    _loadData();
  }

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _strikeCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.derivativesOverview(commodity: _selectedCommodity);
      final rawOhlc = ((res['ohlc'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawMa7 = ((res['ma7'] as List<dynamic>?) ?? [])
          .map((e) => e != null && e != 'null' ? (e is num ? e.toDouble() : double.tryParse(e.toString())) : null)
          .toList();
      final rawMa25 = ((res['ma25'] as List<dynamic>?) ?? [])
          .map((e) => e != null && e != 'null' ? (e is num ? e.toDouble() : double.tryParse(e.toString())) : null)
          .toList();
      final rawOrderbook = ((res['orderbook'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawPositions = ((res['userPositions'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (mounted) {
        setState(() {
          _ohlc = rawOhlc;
          _ma7 = rawMa7;
          _ma25 = rawMa25;
          _orderbook = rawOrderbook;
          _userPositions = rawPositions;
          _loading = false;
        });
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

  Future<void> _createListing() async {
    final size = double.tryParse(_sizeCtrl.text.trim());
    final strike = double.tryParse(_strikeCtrl.text.trim());
    final expiry = int.tryParse(_expiryCtrl.text.trim());

    if (size == null || size <= 0) {
      setState(() => _error = 'Invalid contract size');
      return;
    }
    if (strike == null || strike <= 0) {
      setState(() => _error = 'Invalid strike price');
      return;
    }
    if (expiry == null || expiry <= 0) {
      setState(() => _error = 'Invalid expiry game day');
      return;
    }

    setState(() {
      _isActionInProgress = true;
      _error = null;
    });

    try {
      await widget.api.createFuturesListing(
        commodity: _selectedCommodity,
        size: size,
        strikePrice: strike,
        expiryGameDay: expiry,
      );
      EarthAudioEngine.instance.playChime();
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _successMessage = 'Forward contract for ${size.toStringAsFixed(0)} ${_selectedCommodity.toUpperCase()} @ ${strike.toStringAsFixed(2)} CR created!';
        });
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _buyContract(String contractId, double totalCost) async {
    setState(() {
      _isActionInProgress = true;
      _error = null;
    });

    try {
      await widget.api.buyFuturesContract(contractId);
      EarthAudioEngine.instance.playTradeExecution();
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _successMessage = 'Futures position purchased for ${totalCost.toStringAsFixed(2)} CR!';
        });
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _cancelContract(String contractId) async {
    setState(() {
      _isActionInProgress = true;
      _error = null;
    });

    try {
      await widget.api.cancelFuturesContract(contractId);
      EarthAudioEngine.instance.playClick();
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _successMessage = 'Futures listing $contractId cancelled and collateral refunded.';
        });
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(1060.0, screenSize.width - 24);
    final dialogHeight = math.min(760.0, screenSize.height - 24);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: canvasColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthColors.cyanAccent.withAlpha(140)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(220),
              blurRadius: 36,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              _buildTopHeader(),
              if (_error != null) _buildAlertBanner(_error!, isError: true),
              if (_successMessage != null) _buildAlertBanner(_successMessage!, isError: false),
              Expanded(
                child: _loading && _ohlc.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: EarthColors.cyanAccent))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Candlestick Chart
                            CandlestickChartWidget(
                              ohlc: _ohlc,
                              ma7: _ma7,
                              ma25: _ma25,
                              commodity: _selectedCommodity,
                              height: 250,
                            ),
                            const SizedBox(height: 16),

                            // 2. Orderbook & Issue Futures Form Grid
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: Open Futures Orderbook
                                Expanded(
                                  flex: 6,
                                  child: _buildOrderbookPanel(),
                                ),
                                const SizedBox(width: 16),
                                // Right: Issue Futures Form
                                Expanded(
                                  flex: 4,
                                  child: _buildIssueFuturesPanel(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 3. User's Active Futures Portfolio
                            _buildUserPositionsPanel(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.show_chart, color: EarthColors.cyanAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'FINANCIAL DERIVATIVES & FUTURES TERMINAL',
                        style: TextStyle(
                          color: EarthColors.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Commodity forward contracts, locked collateral hedging & 30-day candlestick history.',
                        style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Commodity selector pills
              ..._commodities.map((c) {
                final isSelected = _selectedCommodity == c;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c.toUpperCase()),
                    selected: isSelected,
                    selectedColor: EarthColors.cyanAccent,
                    backgroundColor: EarthColors.panelSurface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      if (selected && _selectedCommodity != c) {
                        EarthAudioEngine.instance.playClick();
                        setState(() => _selectedCommodity = c);
                        _loadData();
                      }
                    },
                  ),
                );
              }),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  EarthAudioEngine.instance.playClick();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final color = isError ? Colors.redAccent : EarthColors.cyanAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: EarthColors.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() {
              _error = null;
              _successMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderbookPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'OPEN FORWARD CONTRACTS (${_selectedCommodity.toUpperCase()})',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_orderbook.length} Available',
                style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_orderbook.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No open forward listings for this commodity. Create one on the right to hedge price risk.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _orderbook.length,
              itemBuilder: (context, index) {
                final contract = _orderbook[index];
                final id = contract['id']?.toString() ?? '';
                final size = _parseNum(contract['contract_size']);
                final strike = _parseNum(contract['strike_price']);
                final expiry = contract['expiry_game_day'] ?? 200;
                final total = size * strike;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${size.toStringAsFixed(0)} ${_selectedCommodity.toUpperCase()}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '@ ${strike.toStringAsFixed(2)} CR',
                                  style: const TextStyle(color: EarthColors.goldMetallic, fontWeight: FontWeight.bold, fontSize: 11.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Settles Day $expiry • Total Cost: ${total.toStringAsFixed(2)} CR',
                              style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        key: Key('btn-buy-futures-$id'),
                        onPressed: _isActionInProgress ? null : () => _buyContract(id, total),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: EarthColors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                        ),
                        child: const Text('MATCH / BUY'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIssueFuturesPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ISSUE FORWARD CONTRACT',
            style: TextStyle(color: EarthColors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Lock inventory collateral to guarantee future delivery at a fixed strike price.',
            style: TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _sizeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Contract Size (${_selectedCommodity.toUpperCase()})',
              labelStyle: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _strikeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Strike Price per Unit (CR)',
              labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _expiryCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Settlement Day (e.g. Day 220)',
              labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('btn-create-futures-listing'),
              onPressed: _isActionInProgress ? null : _createListing,
              style: ElevatedButton.styleFrom(
                backgroundColor: EarthColors.goldMetallic,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              child: Text(_isActionInProgress ? 'LOCKING COLLATERAL...' : 'LOCK COLLATERAL & ISSUE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPositionsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MY DERIVATIVES & FUTURES PORTFOLIO',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_userPositions.length} Positions Active',
                style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_userPositions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No active forward positions held. Buy contracts from the orderbook or issue listings above.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _userPositions.length,
              itemBuilder: (context, index) {
                final pos = _userPositions[index];
                final id = pos['id']?.toString() ?? '';
                final c = (pos['commodity']?.toString() ?? 'energy').toUpperCase();
                final size = _parseNum(pos['contract_size']);
                final strike = _parseNum(pos['strike_price']);
                final expiry = pos['expiry_game_day'] ?? 200;
                final status = pos['status']?.toString() ?? 'open';
                final isSeller = pos['seller_human_id'] == 'H-0044';

                final statusColor = status == 'matched'
                    ? EarthColors.cyanAccent
                    : (status == 'settled' ? const Color(0xFF00E676) : EarthColors.goldMetallic);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSeller ? Colors.purpleAccent.withAlpha(30) : EarthColors.cyanAccent.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isSeller ? Colors.purpleAccent : EarthColors.cyanAccent),
                        ),
                        child: Text(
                          isSeller ? 'SELLER' : 'BUYER',
                          style: TextStyle(
                            color: isSeller ? Colors.purpleAccent : EarthColors.cyanAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${size.toStringAsFixed(0)} $c @ ${strike.toStringAsFixed(2)} CR',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Expiry: Day $expiry • ID: $id',
                              style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor.withAlpha(100)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (status == 'open' && isSeller) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          key: Key('btn-cancel-futures-$id'),
                          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                          tooltip: 'Cancel Listing',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _isActionInProgress ? null : () => _cancelContract(id),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }
}
