import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'derivatives_dialog.dart';

Widget _marketTopicHeading(BuildContext context, String title,
    {required String description}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Flexible(
        child: Text(title,
            style: const TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      ),
      const SizedBox(width: 5),
      IconButton(
        tooltip: 'About $title',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(Icons.info_outline,
            size: 14, color: mutedColor.withValues(alpha: .8)),
        onPressed: () => showEarthInfoDialog(context,
            title: title, description: description),
      ),
    ]),
  );
}

/// Commodity configuration mapping symbol codes and themes.
class CommodityMeta {
  final String key;
  final String name;
  final String symbol;
  final String description;
  final Color color;
  final IconData icon;

  const CommodityMeta({
    required this.key,
    required this.name,
    required this.symbol,
    required this.description,
    required this.color,
    required this.icon,
  });

  static const all = [
    CommodityMeta(
      key: 'food',
      name: 'FOOD & NUTRITION',
      symbol: 'FOOD',
      description:
          'Vertical farm harvest & bio-nutrients for human metabolic survival.',
      color: EarthResourceColors.food,
      icon: Icons.eco_outlined,
    ),
    CommodityMeta(
      key: 'material',
      name: 'MATERIALS',
      symbol: 'MATR',
      description:
          'Raw industrial base feedstock for manufacturing and construction.',
      color: EarthResourceColors.materials,
      icon: Icons.view_in_ar_outlined,
    ),
    CommodityMeta(
      key: 'components',
      name: 'COMPONENTS',
      symbol: 'FABR',
      description:
          'Precision mechanical sub-assemblies required to maintain and build machines.',
      color: EarthResourceColors.components,
      icon: Icons.settings_outlined,
    ),
    CommodityMeta(
      key: 'energy',
      name: 'ENERGY',
      symbol: 'ENGY',
      description:
          'Electrical power units consumed per production and municipal cycle.',
      color: EarthResourceColors.energy,
      icon: Icons.bolt_outlined,
    ),
    CommodityMeta(
      key: 'compute',
      name: 'COMPUTE',
      symbol: 'INFO',
      description:
          'Quantum processing and algorithmic research compute capacity.',
      color: EarthResourceColors.compute,
      icon: Icons.memory_outlined,
    ),
  ];

  static CommodityMeta forProduct(String product) {
    return all.firstWhere(
      (m) => m.key.toLowerCase() == product.toLowerCase(),
      orElse: () => CommodityMeta(
        key: product.toLowerCase(),
        name: product.toUpperCase(),
        symbol: product
            .toUpperCase()
            .substring(0, product.length >= 4 ? 4 : product.length),
        description: 'Standardized economic commodity asset.',
        color: cyanAccentColor,
        icon: Icons.grain_outlined,
      ),
    );
  }
}

Future<void> showPlaceOrderDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  required String initialProduct,
  required double initialPrice,
  required double feeRate,
  String initialSide = 'buy',
}) async {
  String selectedProduct = initialProduct;
  String side = initialSide;
  final qtyController = TextEditingController(text: '10');
  final priceController = TextEditingController(
      text: initialPrice > 0 ? initialPrice.toStringAsFixed(2) : '50.00');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final qty = int.tryParse(qtyController.text.trim()) ?? 0;
        final price = double.tryParse(priceController.text.trim()) ?? 0.0;
        final baseTotal = qty * price;
        final fee = side == 'buy' ? baseTotal * feeRate : 0.0;
        final grandTotal = side == 'buy' ? baseTotal + fee : baseTotal;
        final meta = CommodityMeta.forProduct(selectedProduct);

        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Row(
            children: [
              Icon(meta.icon, size: 18, color: meta.color),
              const SizedBox(width: 8),
              Text(
                'PLACE ${side.toUpperCase()} ORDER · ${meta.symbol}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: inkColor,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'buy', label: Text('BUY')),
                          ButtonSegment(value: 'sell', label: Text('SELL')),
                        ],
                        selected: {side},
                        onSelectionChanged: (set) =>
                            setDialogState(() => side = set.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedProduct,
                  decoration: const InputDecoration(labelText: 'COMMODITY'),
                  items: CommodityMeta.all
                      .map((m) => DropdownMenuItem(
                            value: m.key,
                            child: Text('${m.name} (${m.symbol})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedProduct = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'QUANTITY (UNITS)',
                    hintText: 'e.g. 10',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'LIMIT PRICE (CREDITS / UNIT)',
                    hintText: 'e.g. 45.00',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Base value:',
                              style:
                                  TextStyle(fontSize: 11, color: mutedColor)),
                          Text('${baseTotal.toStringAsFixed(2)} C',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (side == 'buy' && feeRate > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Exchange fee (${(feeRate * 100).toStringAsFixed(2)}%):',
                              style: const TextStyle(
                                  fontSize: 11, color: mutedColor),
                            ),
                            Text('${fee.toStringAsFixed(2)} C',
                                style: const TextStyle(
                                    fontSize: 11, color: mutedColor)),
                          ],
                        ),
                      ],
                      const Divider(height: 14, color: Colors.white12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            side == 'buy'
                                ? 'Total required escrow:'
                                : 'Expected gross proceeds:',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${grandTotal.toStringAsFixed(2)} C',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: side == 'buy'
                                  ? cyanAccentColor
                                  : Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: qty <= 0 || price <= 0
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await action(() => const EarthApi().submitOrder(
                            selectedProduct,
                            price,
                            side: side,
                            quantity: qty,
                          ));
                    },
              child: const Text('SUBMIT ORDER'),
            ),
          ],
        );
      },
    ),
  );

  qtyController.dispose();
  priceController.dispose();
}

class MarketSignalsPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;
  final Map<String, dynamic> priceHistory;

  const MarketSignalsPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
    this.priceHistory = const {},
  });

  @override
  State<MarketSignalsPanel> createState() => _MarketSignalsPanelState();
}

class _MarketSignalsPanelState extends State<MarketSignalsPanel> {
  String _selectedCommodity = 'material';
  String _orderSide = 'buy';
  String _buyQty = '10';
  String _buyPrice = '';
  String _sellQty = '10';
  String _sellPrice = '';

  final TextEditingController _qtyController =
      TextEditingController(text: '10');
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initDefaultCommodity();
    _qtyController.addListener(() {
      if (_orderSide == 'buy') {
        _buyQty = _qtyController.text;
      } else {
        _sellQty = _qtyController.text;
      }
    });
    _priceController.addListener(() {
      if (_orderSide == 'buy') {
        _buyPrice = _priceController.text;
      } else {
        _sellPrice = _priceController.text;
      }
    });
  }

  void _initDefaultCommodity() {
    final firstKey = widget.state.market.keys.firstOrNull ?? 'material';
    _selectedCommodity = firstKey;
    final productData = widget.state.market[firstKey] as Map<String, dynamic>?;
    final price = asDouble(productData?['price']) ?? 50.0;
    final pStr = price.toStringAsFixed(2);
    _buyPrice = pStr;
    _sellPrice = pStr;
    _priceController.text = pStr;
  }

  void _selectCommodity(String key) {
    setState(() {
      _selectedCommodity = key;
      final productData = widget.state.market[key] as Map<String, dynamic>?;
      final price = asDouble(productData?['price']) ?? 50.0;
      final pStr = price.toStringAsFixed(2);
      _buyPrice = pStr;
      _sellPrice = pStr;
      _priceController.text = pStr;
    });
  }

  void _onSideChanged(String newSide) {
    if (newSide == _orderSide) return;
    setState(() {
      if (_orderSide == 'buy') {
        _buyQty = _qtyController.text;
        _buyPrice = _priceController.text;
      } else {
        _sellQty = _qtyController.text;
        _sellPrice = _priceController.text;
      }

      _orderSide = newSide;

      if (_orderSide == 'buy') {
        _qtyController.text = _buyQty;
        _priceController.text = _buyPrice;
      } else {
        _qtyController.text = _sellQty;
        _priceController.text = _sellPrice;
      }
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = CommodityMeta.forProduct(_selectedCommodity);
    final productData =
        (widget.state.market[_selectedCommodity] as Map<String, dynamic>?) ??
            {};
    final currentPrice = asDouble(productData['price']) ?? 50.0;
    final supply = asInt(productData['supply']) ?? 0;
    final demand = asInt(productData['demand']) ?? 0;
    final history = widget.priceHistory[_selectedCommodity];

    final userCredits = asDouble(widget.state.human['credits']) ?? 0.0;
    final userStock = asInt(widget.state.resources[_selectedCommodity]) ?? 0;

    final historyList = (history is Map && history['history'] is List)
        ? (history['history'] as List).whereType<Map>().toList()
        : <Map>[];

    final prices = historyList
        .map((p) => asDouble(p['price']))
        .whereType<double>()
        .toList();

    double minPrice = prices.isNotEmpty
        ? prices.reduce((a, b) => a < b ? a : b)
        : currentPrice * 0.9;
    double maxPrice = prices.isNotEmpty
        ? prices.reduce((a, b) => a > b ? a : b)
        : currentPrice * 1.1;
    if (minPrice == maxPrice) {
      minPrice *= 0.95;
      maxPrice *= 1.05;
    }

    final totalPressure = (supply + demand).clamp(1, 999999);
    final demandPct = (demand / totalPressure).clamp(0.05, 0.95);

    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final limitPrice = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final baseTotal = qty * limitPrice;
    final fee =
        _orderSide == 'buy' ? baseTotal * widget.state.marketFeeRate : 0.0;
    final totalEscrow = _orderSide == 'buy' ? baseTotal + fee : baseTotal;

    final maxAffordableUnits = limitPrice > 0
        ? (userCredits / (limitPrice * (1 + widget.state.marketFeeRate)))
            .floor()
        : 0;
    final maxSellableUnits = userStock;

    final isBuy = _orderSide == 'buy';
    final sideColor = isBuy ? cyanAccentColor : Colors.orangeAccent;

    final currentDay = asIntOr(widget.state.clock['day'], 1);
    final currentMinute = asIntOr(widget.state.clock['minute'], 0);
    final epochIndex = (currentDay * 6) + (currentMinute ~/ 240);
    final minutesToNextEpoch = 240 - (currentMinute % 240);
    final remHours = minutesToNextEpoch ~/ 60;
    final remMins = minutesToNextEpoch % 60;
    final countdownStr =
        '${remHours.toString().padLeft(2, '0')}:${remMins.toString().padLeft(2, '0')}';

    return EarthPanel(
      key: widget.panelKey,
      title: 'CENTRAL MARKET / LIVE SIGNALS',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Periodic Batch Auction Architecture (Spec §1.10):\n  - Major commodities clear via scheduled Batch Auctions (every 4 simulation hours) rather than continuous front-run order books.\n  - Uniform Price Clearing (P*): All buy orders >= P* and sell orders <= P* fill at the identical market clearing price.\n  - Pro-Rata Shortage Allocation: Excess supply or demand at exact P* is allocated proportionally.\n\n• Commodity Selector: Select between Food, Materials, Energy, Components, and Compute to view spot clearing price, 24h price delta, and market liquidity.\n\n• Liquidity Pressure Gauge: Real-time ratio comparing total aggregated sell volume against buy volume.\n\n• Execution Terminal: Submit limit Buy or Sell orders with explicit quantity and unit price controls.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marketTopicHeading(
            context,
            'CENTRAL MARKET / LIVE SIGNALS',
            description:
                '• Periodic Batch Auction Architecture: major commodities clear every 4 simulation hours at one uniform price.\n\n• Commodity Selector: choose Food, Materials, Energy, Components, or Compute to review price, change, and liquidity.\n\n• Liquidity Pressure Gauge: compares aggregated sell volume against buy volume.\n\n• Execution Terminal: submit limit buy or sell orders with explicit quantity and price controls.',
          ),
          // 0. BATCH AUCTION CLEARING BANNER
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cyanAccentColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.layers_outlined,
                      size: 16, color: cyanAccentColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const Text(
                            'PERIODIC BATCH AUCTION',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                              color: inkColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cyanAccentColor.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: cyanAccentColor.withValues(alpha: .3)),
                            ),
                            child: Text(
                              'EPOCH #$epochIndex',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: cyanAccentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Next batch clearing in $countdownStr · Uniform Clearing Price (P*) · Zero Slippage',
                        style:
                            const TextStyle(fontSize: 9.5, color: mutedColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      key: const Key('btn-open-derivatives-dialog'),
                      onPressed: () => showDerivativesDialog(
                        context,
                        api: const EarthApi(),
                        state: widget.state,
                        initialCommodity: _selectedCommodity,
                      ),
                      icon: const Icon(Icons.show_chart, size: 13),
                      label: const Text('FUTURES & CHARTS'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyanAccentColor.withAlpha(40),
                        foregroundColor: cyanAccentColor,
                        side: BorderSide(color: cyanAccentColor.withAlpha(120)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cyanAccentColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: cyanAccentColor.withValues(alpha: .3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_outlined,
                              size: 11, color: cyanAccentColor),
                          SizedBox(width: 4),
                          Text(
                            'POOLING ORDERS',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .6,
                              color: cyanAccentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 1. TOP COMMODITY SELECTOR MATRIX
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final numCols = availableWidth >= 800 ? 4 : 2;
              final itemWidth = (availableWidth - (numCols - 1) * 12) / numCols;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: widget.state.market.entries.map((entry) {
                  final key = entry.key;
                  final c = CommodityMeta.forProduct(key);
                  final data = (entry.value as Map<String, dynamic>?) ?? {};
                  final s = asInt(data['supply']) ?? 0;
                  final d = asInt(data['demand']) ?? 0;
                  final userOwned = widget.state.resources[key] ?? 0;
                  final isSelected = key == _selectedCommodity;

                  return InkWell(
                    onTap: () => _selectCommodity(key),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: itemWidth,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? c.color.withValues(alpha: .12)
                            : surfaceColor.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? c.color.withValues(alpha: .7)
                              : Colors.white10,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(c.icon, size: 14, color: c.color),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        key.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1,
                                          color: c.color,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              _MiniTrendBadge(
                                  history: widget.priceHistory[key]),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${data['price']} C',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.3,
                              color: inkColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'S $s  ·  D $d  ·  Owned $userOwned',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: mutedColor,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _PriceTrendText(history: widget.priceHistory[key]),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),

          // 2. INLINE COMMODITY GRAPH & BUY/SELL TRADING CONTROLS (NO EXTRA SUBWIDGET CONTAINER)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              final chartAndDepthSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${meta.name} (${meta.symbol})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: inkColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta.description,
                              style: const TextStyle(
                                  fontSize: 10, color: mutedColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'P* ${currentPrice.toStringAsFixed(2)} C',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: meta.color,
                              letterSpacing: -.5,
                            ),
                          ),
                          const Text(
                            'UNIFORM CLEARING PRICE',
                            style: TextStyle(
                                fontSize: 8.5,
                                color: mutedColor,
                                letterSpacing: .8),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Area Price Trend Chart
                  Container(
                    height: 140,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: prices.length >= 2
                        ? CustomPaint(
                            painter: _PriceAreaChartPainter(
                              prices: prices,
                              minPrice: minPrice,
                              maxPrice: maxPrice,
                              lineColor: meta.color,
                            ),
                          )
                        : Center(
                            child: Text(
                              'Aggregating periodic batch clearing history…',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: mutedColor.withValues(alpha: .7)),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Supply vs Demand Pressure Bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final demandLabel =
                              'BUY DEMAND: $demand UNITS (${(demandPct * 100).toStringAsFixed(0)}%)';
                          final supplyLabel =
                              'SELL SUPPLY: $supply UNITS (${((1 - demandPct) * 100).toStringAsFixed(0)}%)';
                          final demandText = Text(demandLabel,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: cyanAccentColor));
                          final supplyText = Text(supplyLabel,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orangeAccent));
                          if (constraints.maxWidth < 520) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                demandText,
                                const SizedBox(height: 3),
                                supplyText
                              ],
                            );
                          }
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [demandText, supplyText],
                          );
                        },
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              Expanded(
                                flex: (demandPct * 100).round(),
                                child: Container(color: cyanAccentColor),
                              ),
                              Expanded(
                                flex: ((1 - demandPct) * 100).round(),
                                child: Container(color: Colors.orangeAccent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );

              final tradeTerminalSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Buy / Sell Selector
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _onSideChanged('buy'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isBuy
                                  ? cyanAccentColor.withValues(alpha: .2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isBuy ? cyanAccentColor : Colors.white12,
                              ),
                            ),
                            child: Text(
                              'BUY ${meta.symbol}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: isBuy ? cyanAccentColor : mutedColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => _onSideChanged('sell'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: !isBuy
                                  ? Colors.orangeAccent.withValues(alpha: .2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !isBuy
                                    ? Colors.orangeAccent
                                    : Colors.white12,
                              ),
                            ),
                            child: Text(
                              'SELL ${meta.symbol}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color:
                                    !isBuy ? Colors.orangeAccent : mutedColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Available balance tag
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final label = Text(
                        isBuy ? 'AVAILABLE CREDITS' : 'AVAILABLE INVENTORY',
                        style: const TextStyle(
                            fontSize: 9, color: mutedColor, letterSpacing: .8),
                      );
                      final value = Text(
                        isBuy
                            ? '${formatCreditsAmount(userCredits)} (max ~$maxAffordableUnits u)'
                            : '$userStock ${meta.symbol}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isBuy ? violetColor : meta.color),
                      );
                      if (constraints.maxWidth < 360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 3), value],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [label, value],
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Quantity Field + Preset Chips
                  TextField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'ORDER QUANTITY (UNITS)',
                      labelStyle:
                          const TextStyle(fontSize: 10, letterSpacing: 1.1),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixText: meta.symbol,
                      suffixStyle: TextStyle(
                          fontSize: 10,
                          color: meta.color,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _presetChip('25%', () {
                        final maxU =
                            isBuy ? maxAffordableUnits : maxSellableUnits;
                        _qtyController.text =
                            (maxU * 0.25).clamp(1, 99999).round().toString();
                      }),
                      const SizedBox(width: 4),
                      _presetChip('50%', () {
                        final maxU =
                            isBuy ? maxAffordableUnits : maxSellableUnits;
                        _qtyController.text =
                            (maxU * 0.50).clamp(1, 99999).round().toString();
                      }),
                      const SizedBox(width: 4),
                      _presetChip('75%', () {
                        final maxU =
                            isBuy ? maxAffordableUnits : maxSellableUnits;
                        _qtyController.text =
                            (maxU * 0.75).clamp(1, 99999).round().toString();
                      }),
                      const SizedBox(width: 4),
                      _presetChip('MAX', () {
                        final maxU =
                            isBuy ? maxAffordableUnits : maxSellableUnits;
                        _qtyController.text = maxU.clamp(1, 99999).toString();
                      }),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Limit Price Field + Prefill button
                  TextField(
                    controller: _priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'LIMIT PRICE (C / UNIT)',
                      labelStyle:
                          const TextStyle(fontSize: 10, letterSpacing: 1.1),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _priceController.text =
                            currentPrice.toStringAsFixed(2),
                        child: Text('SPOT',
                            style: TextStyle(fontSize: 9.5, color: meta.color)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cost Summary Box
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Base value:',
                                style:
                                    TextStyle(fontSize: 10, color: mutedColor)),
                            Text('${baseTotal.toStringAsFixed(2)} C',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (isBuy && widget.state.marketFeeRate > 0) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  'Exchange fee (${(widget.state.marketFeeRate * 100).toStringAsFixed(1)}%):',
                                  style: const TextStyle(
                                      fontSize: 10, color: mutedColor)),
                              Text('${fee.toStringAsFixed(2)} C',
                                  style: const TextStyle(
                                      fontSize: 10, color: mutedColor)),
                            ],
                          ),
                        ],
                        const Divider(height: 10, color: Colors.white10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isBuy ? 'Escrow Hold:' : 'Gross Proceeds:',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${totalEscrow.toStringAsFixed(2)} C',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: sideColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Submit Action Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.busy || qty <= 0 || limitPrice <= 0
                          ? null
                          : () async {
                              await widget
                                  .action(() => const EarthApi().submitOrder(
                                        _selectedCommodity,
                                        limitPrice,
                                        side: _orderSide,
                                        quantity: qty,
                                      ));
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: sideColor.withValues(alpha: .85),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        'PLACE ${_orderSide.toUpperCase()} ORDER',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: chartAndDepthSection),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: tradeTerminalSection),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chartAndDepthSection,
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),
                  tradeTerminalSection,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600, color: mutedColor),
            ),
          ),
        ),
      );
}

class _MiniTrendBadge extends StatelessWidget {
  final dynamic history;

  const _MiniTrendBadge({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history is! Map || history['history'] is! List) {
      return const SizedBox.shrink();
    }
    final points = (history['history'] as List).whereType<Map>().toList();
    if (points.length < 2) return const SizedBox.shrink();
    final latest = asDouble(points.first['price']);
    final oldest = asDouble(points.last['price']);
    if (latest == null || oldest == null || oldest == 0)
      return const SizedBox.shrink();
    final change = latest - oldest;
    final pct = (change / oldest) * 100;
    final isPos = change >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (isPos ? Colors.tealAccent : Colors.orangeAccent)
            .withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isPos ? '+' : ''}${pct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isPos ? Colors.tealAccent : Colors.orangeAccent,
        ),
      ),
    );
  }
}

class _PriceTrendText extends StatelessWidget {
  final dynamic history;

  const _PriceTrendText({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history is! Map || history['history'] is! List) {
      return const SizedBox.shrink();
    }
    final points = (history['history'] as List).whereType<Map>().toList();
    if (points.length < 2) return const SizedBox.shrink();
    final latest = asDouble(points.first['price']);
    final oldest = asDouble(points.last['price']);
    if (latest == null || oldest == null) return const SizedBox.shrink();
    final change = latest - oldest;
    return Text(
      '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(2)} C / ${points.length}d',
      style: TextStyle(
        fontSize: 10,
        color: change >= 0 ? Colors.tealAccent : Colors.orangeAccent,
      ),
    );
  }
}

class _PriceAreaChartPainter extends CustomPainter {
  final List<double> prices;
  final double minPrice;
  final double maxPrice;
  final Color lineColor;

  _PriceAreaChartPainter({
    required this.prices,
    required this.minPrice,
    required this.maxPrice,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;

    final range = (maxPrice - minPrice).clamp(0.01, 999999.0);
    final dx = size.width / (prices.length - 1);

    final linePath = Path();
    final fillPath = Path();

    for (int i = 0; i < prices.length; i++) {
      final x = i * dx;
      final normalized = (prices[i] - minPrice) / range;
      final y = size.height - (normalized * size.height);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * dx;
        final prevNorm = (prices[i - 1] - minPrice) / range;
        final prevY = size.height - (prevNorm * size.height);

        final midX = (prevX + x) / 2;
        linePath.cubicTo(midX, prevY, midX, y, x, y);
        fillPath.cubicTo(midX, prevY, midX, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: .25),
          lineColor.withValues(alpha: .0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(linePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _PriceAreaChartPainter oldDelegate) => true;
}

class MarketOrderBookPanel extends StatelessWidget {
  final EarthState state;

  const MarketOrderBookPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final book = state.marketBook;

    return EarthPanel(
      title: 'CENTRAL MARKET / ORDER BOOK',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Aggregated Order Depth: Displays open buy bids and sell asks grouped by commodity and best price tiers, showing total volume waiting for batch execution.\n\n• Order Count & Liquidity: Number of discrete market participants contributing liquidity to each price tier.\n\n• Central Clearing Settlement: Orders do not execute via continuous match; all qualifying bids and asks cross simultaneously at the uniform clearing price when the batch clears.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _marketTopicHeading(context, 'CENTRAL MARKET / ORDER BOOK',
              description:
                  '• Review aggregated buy bids, sell asks, order counts, and available liquidity.'),
          if (book.isEmpty)
            const Text(
              'No open orders. The market is waiting for a new signal.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: book.map((raw) {
                final row = raw as Map<String, dynamic>;
                final product = row['product']?.toString() ?? 'material';
                final meta = CommodityMeta.forProduct(product);
                final openQty = asInt(row['open_quantity']) ?? 0;
                final bestPrice = asDouble(row['best_price']) ?? 0.0;
                final orderCount = asInt(row['order_count']) ?? 1;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(meta.icon, size: 14, color: meta.color),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.name,
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: inkColor),
                          ),
                          Text(
                            '$openQty units · ${bestPrice.toStringAsFixed(2)} C ($orderCount orders)',
                            style: const TextStyle(
                                fontSize: 9.5, color: mutedColor),
                          ),
                        ],
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

class MyMarketOrdersPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const MyMarketOrdersPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<MyMarketOrdersPanel> createState() => _MyMarketOrdersPanelState();
}

class _MyMarketOrdersPanelState extends State<MyMarketOrdersPanel> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final allOrders = widget.state.marketOrders;

    final filtered = allOrders.where((raw) {
      if (raw is! Map) return false;
      final status = (raw['status']?.toString() ?? 'open').toLowerCase();
      if (_filter == 'active') return status == 'open' || status == 'partial';
      if (_filter == 'filled') return status == 'filled';
      if (_filter == 'cancelled')
        return status == 'cancelled' ||
            status == 'refunded' ||
            status == 'rejected';
      return true;
    }).toList();

    return EarthPanel(
      title: 'MY MARKET ORDERS / LIFECYCLE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Order Status Categorization: Filter across All, Active (Open / Partially Filled), Completed (Filled), and Cancelled limit orders.\n\n• Order Lifecycle Indicators: Tracks submitted quantity, filled volume progress, limit price per unit, and locked escrow reserves.\n\n• Escrow & Cancellation: Active limit buy orders securely lock credits in escrow; active sell orders lock inventory units. Cancelling an order instantly unlocks and restores escrowed assets.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marketTopicHeading(context, 'MY MARKET ORDERS / LIFECYCLE',
              description:
                  '• Track active, filled, and cancelled orders, including escrow and execution progress.'),
          // Filter Tabs
          Row(
            children: [
              _tabButton('ALL (${allOrders.length})', 'all'),
              const SizedBox(width: 6),
              _tabButton('ACTIVE ORDERS', 'active'),
              const SizedBox(width: 6),
              _tabButton('FILLED ORDERS', 'filled'),
              const SizedBox(width: 6),
              _tabButton('CANCELLED ORDERS', 'cancelled'),
            ],
          ),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            const Text(
              'No market orders on record.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...filtered.map((raw) {
              final order = raw as Map<String, dynamic>;
              final id = order['id']?.toString() ?? '';
              final side = (order['side']?.toString() ?? 'buy').toUpperCase();
              final product =
                  (order['product']?.toString() ?? '').toUpperCase();
              final quantity = asInt(order['quantity']) ?? 1;
              final filledQty = asInt(order['filled_quantity']) ??
                  asInt(order['filled']) ??
                  0;
              final remaining = (quantity - filledQty).clamp(0, quantity);
              final limitPrice = asDouble(order['limit_price']) ??
                  asDouble(order['limitPrice']) ??
                  0.0;
              final settlementPrice = asDouble(order['settlement_price']) ??
                  asDouble(order['clearing_price']) ??
                  asDouble(order['price']);
              final status =
                  (order['status']?.toString() ?? 'open').toLowerCase();
              final reservedCredits = asDouble(order['reserved_credits']) ??
                  asDouble(order['reservedCredits']) ??
                  (side == 'BUY' && (status == 'open' || status == 'partial')
                      ? remaining * limitPrice
                      : 0.0);
              final releasedEscrow = asDouble(order['released_escrow']) ??
                  asDouble(order['releasedEscrow']) ??
                  (status == 'cancelled' || status == 'refunded'
                      ? remaining * limitPrice
                      : 0.0);
              final fee = asDouble(order['fee']) ?? 0.0;
              final totalValue = filledQty > 0
                  ? filledQty * (settlementPrice ?? limitPrice)
                  : quantity * limitPrice;

              final isBuy = side == 'BUY';
              final fillProgress =
                  quantity > 0 ? (filledQty / quantity).clamp(0.0, 1.0) : 0.0;
              final canCancel =
                  (status == 'open' || status == 'partial') && !widget.busy;

              Color statusColor = mutedColor;
              if (status == 'open') statusColor = Colors.lightBlueAccent;
              if (status == 'partial') statusColor = Colors.orangeAccent;
              if (status == 'filled') statusColor = cyanAccentColor;
              if (status == 'cancelled' || status == 'rejected')
                statusColor = Colors.redAccent;
              if (status == 'refunded') statusColor = Colors.tealAccent;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                (isBuy ? cyanAccentColor : Colors.orangeAccent)
                                    .withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            side,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color:
                                  isBuy ? cyanAccentColor : Colors.orangeAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$side $product · $quantity units @ ${limitPrice.toStringAsFixed(2)} C',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: inkColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Filled: $filledQty / $quantity ($remaining remaining) · Total: ${totalValue.toStringAsFixed(2)} C',
                                style: const TextStyle(
                                    fontSize: 10, color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: statusColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Fill Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fillProgress,
                        minHeight: 4,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fillProgress >= 1.0 ? cyanAccentColor : violetColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Settlement & Escrow Notes
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (settlementPrice != null && filledQty > 0)
                          Text(
                            'Settlement price: ${settlementPrice.toStringAsFixed(2)} C · Fee paid: ${fee.toStringAsFixed(2)} C',
                            style: const TextStyle(
                                fontSize: 9.5, color: cyanAccentColor),
                          ),
                        if (reservedCredits > 0)
                          Text(
                            'Reserved Credits in escrow: ${reservedCredits.toStringAsFixed(2)} C',
                            style: const TextStyle(
                                fontSize: 9.5, color: Colors.lightBlueAccent),
                          ),
                        if (releasedEscrow > 0)
                          Text(
                            'Released escrow refund: ${releasedEscrow.toStringAsFixed(2)} C',
                            style: const TextStyle(
                                fontSize: 9.5, color: Colors.tealAccent),
                          ),
                      ],
                    ),

                    if (canCancel) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                          ),
                          onPressed: () => widget
                              .action(() => const EarthApi().cancelOrder(id)),
                          child: const Text('CANCEL ORDER',
                              style: TextStyle(fontSize: 9.5)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _tabButton(String label, String key) {
    final isSel = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel
              ? violetColor.withValues(alpha: .2)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSel ? violetColor : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? inkColor : mutedColor,
            letterSpacing: .8,
          ),
        ),
      ),
    );
  }
}
