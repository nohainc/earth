import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

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
      description: 'Vertical farm harvest & bio-nutrients for human metabolic survival.',
      color: Colors.lightGreenAccent,
      icon: Icons.eco_outlined,
    ),
    CommodityMeta(
      key: 'material',
      name: 'MATERIALS',
      symbol: 'MATR',
      description: 'Raw industrial base feedstock for manufacturing and construction.',
      color: Colors.tealAccent,
      icon: Icons.view_in_ar_outlined,
    ),
    CommodityMeta(
      key: 'components',
      name: 'COMPONENTS',
      symbol: 'FABR',
      description: 'Precision mechanical sub-assemblies required to maintain and build machines.',
      color: cyanAccentColor,
      icon: Icons.settings_outlined,
    ),
    CommodityMeta(
      key: 'energy',
      name: 'ENERGY',
      symbol: 'ENGY',
      description: 'Electrical power units consumed per production and municipal cycle.',
      color: Colors.amberAccent,
      icon: Icons.bolt_outlined,
    ),
    CommodityMeta(
      key: 'compute',
      name: 'COMPUTE',
      symbol: 'INFO',
      description: 'Quantum processing and algorithmic research compute capacity.',
      color: violetColor,
      icon: Icons.memory_outlined,
    ),
  ];

  static CommodityMeta forProduct(String product) {
    return all.firstWhere(
      (m) => m.key.toLowerCase() == product.toLowerCase(),
      orElse: () => CommodityMeta(
        key: product.toLowerCase(),
        name: product.toUpperCase(),
        symbol: product.toUpperCase().substring(0, product.length >= 4 ? 4 : product.length),
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
                              style: TextStyle(fontSize: 11, color: mutedColor)),
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
  final TextEditingController _qtyController = TextEditingController(text: '10');
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initDefaultCommodity();
  }

  void _initDefaultCommodity() {
    final firstKey = widget.state.market.keys.firstOrNull ?? 'material';
    _selectedCommodity = firstKey;
    final productData = widget.state.market[firstKey] as Map<String, dynamic>?;
    final price = asDouble(productData?['price']) ?? 50.0;
    _priceController.text = price.toStringAsFixed(2);
  }

  void _selectCommodity(String key) {
    setState(() {
      _selectedCommodity = key;
      final productData = widget.state.market[key] as Map<String, dynamic>?;
      final price = asDouble(productData?['price']) ?? 50.0;
      _priceController.text = price.toStringAsFixed(2);
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
    final productData = (widget.state.market[_selectedCommodity] as Map<String, dynamic>?) ?? {};
    final currentPrice = asDouble(productData['price']) ?? 50.0;
    final supply = asInt(productData['supply']) ?? 0;
    final demand = asInt(productData['demand']) ?? 0;
    final history = widget.priceHistory[_selectedCommodity];

    final userCredits = asDouble(widget.state.human['credits']) ?? 0.0;
    final userStock = asInt(widget.state.resources[_selectedCommodity]) ?? 0;

    return EarthPanel(
      key: widget.panelKey,
      title: 'CENTRAL MARKET / LIVE SIGNALS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP COMMODITY SELECTOR MATRIX
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final numCols = availableWidth >= 1100
                  ? 5
                  : availableWidth >= 680
                      ? 3
                      : 2;
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              _MiniTrendBadge(history: widget.priceHistory[key]),
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

          // 2. COMBINED COMMODITY GRAPH & TRADING TERMINAL HUB
          _UnifiedCommodityTradeHub(
            meta: meta,
            currentPrice: currentPrice,
            rawPrice: productData['price']?.toString() ?? currentPrice.toString(),
            supply: supply,
            demand: demand,
            history: history,
            feeRate: widget.state.marketFeeRate,
            busy: widget.busy,
            side: _orderSide,
            onSideChanged: (s) => setState(() => _orderSide = s),
            qtyController: _qtyController,
            priceController: _priceController,
            userCredits: userCredits,
            userStockpile: userStock,
            onSubmit: () async {
              final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
              final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
              if (qty > 0 && price > 0) {
                await widget.action(() => const EarthApi().submitOrder(
                      _selectedCommodity,
                      price,
                      side: _orderSide,
                      quantity: qty,
                    ));
              }
            },
          ),
        ],
      ),
    );
  }
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
    if (latest == null || oldest == null || oldest == 0) return const SizedBox.shrink();
    final change = latest - oldest;
    final pct = (change / oldest) * 100;
    final isPos = change >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (isPos ? Colors.tealAccent : Colors.orangeAccent).withValues(alpha: .15),
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

class _UnifiedCommodityTradeHub extends StatelessWidget {
  final CommodityMeta meta;
  final double currentPrice;
  final String rawPrice;
  final int supply;
  final int demand;
  final dynamic history;
  final double feeRate;
  final bool busy;
  final String side;
  final ValueChanged<String> onSideChanged;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final double userCredits;
  final int userStockpile;
  final VoidCallback onSubmit;

  const _UnifiedCommodityTradeHub({
    required this.meta,
    required this.currentPrice,
    required this.rawPrice,
    required this.supply,
    required this.demand,
    required this.history,
    required this.feeRate,
    required this.busy,
    required this.side,
    required this.onSideChanged,
    required this.qtyController,
    required this.priceController,
    required this.userCredits,
    required this.userStockpile,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final historyList = (history is Map && history['history'] is List)
        ? (history['history'] as List).whereType<Map>().toList()
        : <Map>[];

    final prices = historyList
        .map((p) => asDouble(p['price']))
        .whereType<double>()
        .toList();

    double minPrice = prices.isNotEmpty ? prices.reduce((a, b) => a < b ? a : b) : currentPrice * 0.9;
    double maxPrice = prices.isNotEmpty ? prices.reduce((a, b) => a > b ? a : b) : currentPrice * 1.1;
    if (minPrice == maxPrice) {
      minPrice *= 0.95;
      maxPrice *= 1.05;
    }

    final totalPressure = (supply + demand).clamp(1, 999999);
    final demandPct = (demand / totalPressure).clamp(0.05, 0.95);

    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
    final limitPrice = double.tryParse(priceController.text.trim()) ?? 0.0;
    final baseTotal = qty * limitPrice;
    final fee = side == 'buy' ? baseTotal * feeRate : 0.0;
    final totalEscrow = side == 'buy' ? baseTotal + fee : baseTotal;

    final maxAffordableUnits = limitPrice > 0 ? (userCredits / (limitPrice * (1 + feeRate))).floor() : 0;
    final maxSellableUnits = userStockpile;

    final isBuy = side == 'buy';
    final sideColor = isBuy ? cyanAccentColor : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: LayoutBuilder(
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
                          style: const TextStyle(fontSize: 10, color: mutedColor),
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
                        style: TextStyle(fontSize: 8.5, color: mutedColor, letterSpacing: .8),
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
                          style: TextStyle(fontSize: 10.5, color: mutedColor.withValues(alpha: .7)),
                        ),
                      ),
              ),
              const SizedBox(height: 12),

              // Supply vs Demand Pressure Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BUY DEMAND: $demand UNITS (${(demandPct * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: cyanAccentColor),
                      ),
                      Text(
                        'SELL SUPPLY: $supply UNITS (${((1 - demandPct) * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.orangeAccent),
                      ),
                    ],
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
                      onTap: () => onSideChanged('buy'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isBuy ? cyanAccentColor.withValues(alpha: .2) : Colors.transparent,
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
                      onTap: () => onSideChanged('sell'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !isBuy ? Colors.orangeAccent.withValues(alpha: .2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !isBuy ? Colors.orangeAccent : Colors.white12,
                          ),
                        ),
                        child: Text(
                          'SELL ${meta.symbol}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: !isBuy ? Colors.orangeAccent : mutedColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Available balance tag
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isBuy ? 'AVAILABLE CREDITS' : 'AVAILABLE INVENTORY',
                    style: const TextStyle(fontSize: 9, color: mutedColor, letterSpacing: .8),
                  ),
                  Text(
                    isBuy
                        ? '${formatCreditsAmount(userCredits)} (max ~$maxAffordableUnits u)'
                        : '$userStockpile ${meta.symbol}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isBuy ? violetColor : meta.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Quantity Field + Preset Chips
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'ORDER QUANTITY (UNITS)',
                  labelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.1),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixText: meta.symbol,
                  suffixStyle: TextStyle(fontSize: 10, color: meta.color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _presetChip('25%', () {
                    final maxU = isBuy ? maxAffordableUnits : maxSellableUnits;
                    qtyController.text = (maxU * 0.25).clamp(1, 99999).round().toString();
                  }),
                  const SizedBox(width: 4),
                  _presetChip('50%', () {
                    final maxU = isBuy ? maxAffordableUnits : maxSellableUnits;
                    qtyController.text = (maxU * 0.50).clamp(1, 99999).round().toString();
                  }),
                  const SizedBox(width: 4),
                  _presetChip('75%', () {
                    final maxU = isBuy ? maxAffordableUnits : maxSellableUnits;
                    qtyController.text = (maxU * 0.75).clamp(1, 99999).round().toString();
                  }),
                  const SizedBox(width: 4),
                  _presetChip('MAX', () {
                    final maxU = isBuy ? maxAffordableUnits : maxSellableUnits;
                    qtyController.text = maxU.clamp(1, 99999).toString();
                  }),
                ],
              ),
              const SizedBox(height: 10),

              // Limit Price Field + Prefill button
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'LIMIT PRICE (C / UNIT)',
                  labelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.1),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => priceController.text = currentPrice.toStringAsFixed(2),
                    child: Text('SPOT', style: TextStyle(fontSize: 9.5, color: meta.color)),
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
                        const Text('Base value:', style: TextStyle(fontSize: 10, color: mutedColor)),
                        Text('${baseTotal.toStringAsFixed(2)} C', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    if (isBuy && feeRate > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Exchange fee (${(feeRate * 100).toStringAsFixed(1)}%):', style: const TextStyle(fontSize: 10, color: mutedColor)),
                          Text('${fee.toStringAsFixed(2)} C', style: const TextStyle(fontSize: 10, color: mutedColor)),
                        ],
                      ),
                    ],
                    const Divider(height: 10, color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isBuy ? 'Escrow Hold:' : 'Gross Proceeds:',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
                  onPressed: busy || qty <= 0 || limitPrice <= 0 ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: sideColor.withValues(alpha: .85),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'PLACE ${side.toUpperCase()} ORDER',
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
                Container(
                  width: 1,
                  height: 360,
                  color: Colors.white12,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                ),
                Expanded(flex: 2, child: tradeTerminalSection),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chartAndDepthSection,
              const Divider(height: 28, color: Colors.white12),
              tradeTerminalSection,
            ],
          );
        },
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
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: mutedColor),
            ),
          ),
        ),
      );
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
      child: book.isEmpty
          ? const Text(
              'No open orders. The market is waiting for a new signal.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      width: 200,
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${meta.name} (${meta.symbol})',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: meta.color,
                                ),
                              ),
                              Text(
                                '$orderCount orders',
                                style: const TextStyle(fontSize: 9, color: mutedColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Pending volume:', style: TextStyle(fontSize: 10, color: mutedColor)),
                              Text('$openQty units', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Best limit price:', style: TextStyle(fontSize: 10, color: mutedColor)),
                              Text('${bestPrice.toStringAsFixed(2)} C', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: inkColor)),
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
      if (_filter == 'cancelled') return status == 'cancelled' || status == 'refunded' || status == 'rejected';
      return true;
    }).toList();

    return EarthPanel(
      title: 'MY MARKET ORDERS / LIFECYCLE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              final product = (order['product']?.toString() ?? '').toUpperCase();
              final quantity = asInt(order['quantity']) ?? 1;
              final filledQty = asInt(order['filled_quantity']) ?? asInt(order['filled']) ?? 0;
              final remaining = (quantity - filledQty).clamp(0, quantity);
              final limitPrice = asDouble(order['limit_price']) ?? asDouble(order['limitPrice']) ?? 0.0;
              final settlementPrice = asDouble(order['settlement_price']) ?? asDouble(order['clearing_price']) ?? asDouble(order['price']);
              final status = (order['status']?.toString() ?? 'open').toLowerCase();
              final reservedCredits = asDouble(order['reserved_credits']) ?? asDouble(order['reservedCredits']) ?? (side == 'BUY' && (status == 'open' || status == 'partial') ? remaining * limitPrice : 0.0);
              final releasedEscrow = asDouble(order['released_escrow']) ?? asDouble(order['releasedEscrow']) ?? (status == 'cancelled' || status == 'refunded' ? remaining * limitPrice : 0.0);
              final fee = asDouble(order['fee']) ?? 0.0;
              final totalValue = filledQty > 0 ? filledQty * (settlementPrice ?? limitPrice) : quantity * limitPrice;

              final isBuy = side == 'BUY';
              final fillProgress = quantity > 0 ? (filledQty / quantity).clamp(0.0, 1.0) : 0.0;
              final canCancel = (status == 'open' || status == 'partial') && !widget.busy;

              Color statusColor = mutedColor;
              if (status == 'open') statusColor = Colors.lightBlueAccent;
              if (status == 'partial') statusColor = Colors.orangeAccent;
              if (status == 'filled') statusColor = cyanAccentColor;
              if (status == 'cancelled' || status == 'rejected') statusColor = Colors.redAccent;
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isBuy ? cyanAccentColor : Colors.orangeAccent).withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            side,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isBuy ? cyanAccentColor : Colors.orangeAccent,
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
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: inkColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Filled: $filledQty / $quantity ($remaining remaining) · Total: ${totalValue.toStringAsFixed(2)} C',
                                style: const TextStyle(fontSize: 10, color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor),
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
                            style: const TextStyle(fontSize: 9.5, color: cyanAccentColor),
                          ),
                        if (reservedCredits > 0)
                          Text(
                            'Reserved Credits in escrow: ${reservedCredits.toStringAsFixed(2)} C',
                            style: const TextStyle(fontSize: 9.5, color: Colors.lightBlueAccent),
                          ),
                        if (releasedEscrow > 0)
                          Text(
                            'Released escrow refund: ${releasedEscrow.toStringAsFixed(2)} C',
                            style: const TextStyle(fontSize: 9.5, color: Colors.tealAccent),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          ),
                          onPressed: () => widget.action(() => const EarthApi().cancelOrder(id)),
                          child: const Text('CANCEL ORDER', style: TextStyle(fontSize: 9.5)),
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
          color: isSel ? violetColor.withValues(alpha: .2) : Colors.white.withValues(alpha: .04),
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
