import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/market_models.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'candlestick_chart_widget.dart';

class SuppliesTodayPanel extends StatefulWidget {
  final EarthState state;
  final Future<void> Function(Future<EarthState> Function()) action;
  final EarthApi api;

  const SuppliesTodayPanel({
    super.key,
    required this.state,
    required this.action,
    this.api = const EarthApi(),
  });

  static const _products = [
    'energy',
    'food',
    'material',
    'components',
    'compute'
  ];

  @override
  State<SuppliesTodayPanel> createState() => _SuppliesTodayPanelState();
}

class _SuppliesTodayPanelState extends State<SuppliesTodayPanel> {
  Map<String, HouseCommodityPosition> _positions = const {};
  bool _loadingPositions = false;

  static const _products = SuppliesTodayPanel._products;

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  @override
  void didUpdateWidget(covariant SuppliesTodayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.api != widget.api) {
      _loadPositions();
    }
  }

  Future<void> _loadPositions() async {
    if (_loadingPositions) return;
    _loadingPositions = true;
    try {
      final response = await widget.api.marketHousePositions();
      if (!mounted) return;
      final positions = <String, HouseCommodityPosition>{};
      for (final position in response) {
        final product = position.product.toLowerCase();
        if (product.isNotEmpty) positions[product] = position;
      }
      setState(() => _positions = positions);
    } catch (_) {
      // A missing read-model response is not permission to fall back to raw
      // world balances; keep the position explicitly unavailable.
      if (mounted) setState(() => _positions = const {});
    } finally {
      _loadingPositions = false;
    }
  }

  HouseCommodityPosition? _position(String product) => _positions[product];

  double? _displayQuantity(String? value) =>
      value == null ? null : double.tryParse(value);

  @override
  Widget build(BuildContext context) {
    final shortages = <String>[];
    final watchlist = <String>[];
    final cards = <Widget>[];
    final flowMap = widget.state.json['resourceFlows'] is Map
        ? Map<String, dynamic>.from(widget.state.json['resourceFlows'] as Map)
        : const <String, dynamic>{};
    double? netFlow(String product) {
      final raw = flowMap[product];
      if (raw is! Map) return null;
      return asDouble(raw['net'] ?? raw['netPerGameDay']);
    }

    for (final product in _products) {
      final position = _position(product);
      final availableLabel = position?.availableQuantity;
      final reservedLabel = position?.reservedQuantity ?? '0';
      final available = _displayQuantity(availableLabel);
      final net = netFlow(product);
      final market = widget.state.market[product] is Map
          ? Map<String, dynamic>.from(widget.state.market[product] as Map)
          : const <String, dynamic>{};
      final price = asDouble(market['price']);
      final runway = available == null || net == null || net >= 0
          ? null
          : available / net.abs();
      final lowStock = runway != null && runway <= 3;
      if (available != null && available <= 0 && net != null && net < 0) {
        shortages.add(product);
      }
      if (available != null && available > 0 && lowStock) {
        watchlist.add(product);
      }
      final meta = CommodityMeta.forProduct(product);
      cards.add(Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (available != null && available <= 0
                      ? context.warningColor
                      : meta.color)
                  .withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(meta.icon,
                  size: 16,
                  color: available != null && available <= 0
                      ? context.warningColor
                      : meta.color),
              const SizedBox(width: 7),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(meta.name.toUpperCase(),
                        style: const TextStyle(
                            color: mutedColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                        availableLabel == null
                            ? 'Quantity unavailable'
                            : '$availableLabel available · $reservedLabel reserved',
                        style: TextStyle(
                            color: available != null && available <= 0
                                ? context.warningColor
                                : inkColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    Text(
                        net == null || net == 0
                            ? 'Flow unavailable'
                            : net > 0
                                ? '+${net.toStringAsFixed(1)} / game day'
                                : available == null
                                    ? '${net.toStringAsFixed(1)} / game day'
                                    : '${net.toStringAsFixed(1)} / game day · ~${runway!.floor()} game days',
                        style: TextStyle(
                            color: net != null && net < 0
                                ? context.warningColor
                                : mutedColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                    Text(
                        price == null
                            ? 'Price unavailable'
                            : '${price.toStringAsFixed(2)} Credits / unit',
                        style:
                            const TextStyle(color: mutedColor, fontSize: 9.5)),
                  ])),
            ]),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: price == null || available == null
                    ? null
                    : () => showPlaceOrderDialog(
                          context,
                          widget.action,
                          initialProduct: product,
                          initialPrice: price.toStringAsFixed(2),
                          initialSide: net != null && net < 0 && lowStock
                              ? 'buy'
                              : 'sell',
                          buyerFeeRate: widget.state.marketFeeRate.toString(),
                          api: widget.api,
                        ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 22),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                    net != null && net < 0 && lowStock ? 'BUY' : 'TRADE',
                    style: const TextStyle(fontSize: 9)),
              ),
            ),
          ],
        ),
      ));
    }
    final marketEntries = widget.state.market.entries
        .map((entry) => entry.value is Map
            ? Map<String, dynamic>.from(entry.value as Map)
            : const <String, dynamic>{})
        .toList();
    final marketStatus = marketEntries.map((item) {
      final product = item['product']?.toString() ?? 'resource';
      final supply = asInt(item['supply']);
      final demand = asInt(item['demand']);
      final condition = supply == null || demand == null
          ? 'OPEN INTEREST UNAVAILABLE'
          : demand > supply * 1.15
              ? 'OPEN BUY INTEREST HIGH'
              : supply > demand * 1.15
                  ? 'OPEN SELL INTEREST HIGH'
                  : 'OPEN INTEREST BALANCED';
      return '${CommodityMeta.forProduct(product).name}: $condition';
    }).join(' · ');
    final activeOrders =
        widget.state.marketOrders.whereType<Map>().where((order) {
      final status = order['status']?.toString().toLowerCase();
      return status == 'open' || status == 'partial';
    }).length;
    return EarthPanel(
      title: 'STOCK & SHORTAGES',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Available stock after currently reserved quantities.\n\n• A shortage can be handled by buying, producing, or reducing consumption.\n\n• Open orders may fill fully, partially, or later at the next market clearing.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cyanAccentColor.withValues(alpha: .22)),
          ),
          child: Wrap(
            spacing: 18,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _overviewMetric('MARKET CONDITIONS', marketStatus),
              _overviewMetric(
                  'HOUSE FLOW',
                  watchlist.isEmpty
                      ? 'No low-runway resources'
                      : '${watchlist.length} need attention'),
              _overviewMetric('OPEN ORDERS', '$activeOrders'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
            shortages.isEmpty
                ? (watchlist.isEmpty
                    ? 'No immediate commodity shortage is visible.'
                    : 'Watch closely: ${watchlist.map((p) => CommodityMeta.forProduct(p).name).join(' · ')} may run low soon.')
                : 'Needs attention: ${shortages.map((p) => CommodityMeta.forProduct(p).name).join(' · ')}',
            style: TextStyle(
                color: shortages.isEmpty && watchlist.isEmpty
                    ? context.successColor
                    : context.warningColor,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Reserved stock is excluded from available quantities.',
            style: TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: cards),
        const SizedBox(height: 12),
        const Text(
            'Buildings and businesses drive demand. Before trading, check the flow, runway, and price trend for the selected resource.',
            style: TextStyle(color: mutedColor, fontSize: 10.5)),
      ]),
    );
  }

  Widget _overviewMetric(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: mutedColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: inkColor, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class MarketWorkspace extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final EarthApi api;

  const MarketWorkspace({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.api = const EarthApi(),
  });

  @override
  State<MarketWorkspace> createState() => _MarketWorkspaceState();
}

class _MarketWorkspaceState extends State<MarketWorkspace> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final activeOrders =
        widget.state.marketOrders.whereType<Map>().where((order) {
      final status = order['status']?.toString().toLowerCase();
      return status == 'open' || status == 'partial';
    }).length;
    final feePercent = (widget.state.marketFeeRate * 100).toStringAsFixed(1);

    final cockpit = EarthPageCockpit(
      status: 'COMMODITY EXCHANGE',
      statusColor: context.primaryColor,
      infoTitle: 'PLANETARY COMMODITY EXCHANGE ARCHITECTURE',
      infoDescription:
          '• Batch-clearing commodity exchange for planetary resources (Energy, Food, Materials, Components, Compute).\n\n• Exchange Transaction Fee: Standard clearance and order matching fee rate applied on executed trade volumes.\n\n• Supply Contracts & Order Telemetry: Active limit orders and forward supply agreements protecting against macroeconomic volatility.',
      title: 'COMMODITY EXCHANGE',
      subtitle:
          'Batch-clearing commodity order books, resource flows, and trade settlement across Earth',
      metrics: [
        CockpitMetric(
          label: 'Trading Fee',
          value: '$feePercent%',
          icon: Icons.percent_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'My Orders',
          value: '$activeOrders',
          icon: Icons.receipt_outlined,
          color: context.secondaryColor,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cockpit,
        const SizedBox(height: 24),
        Container(
          margin: EdgeInsets.only(bottom: context.spacingControl),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  context,
                  title: 'OVERVIEW',
                  icon: Icons.dashboard_outlined,
                  isSelected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  context,
                  title: 'TRADE',
                  icon: Icons.swap_horiz_outlined,
                  isSelected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  context,
                  title: 'ORDERS',
                  icon: Icons.receipt_long_outlined,
                  isSelected: _selectedTab == 2,
                  onTap: () => setState(() => _selectedTab = 2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_selectedTab == 0)
          SuppliesTodayPanel(
              state: widget.state, action: widget.action, api: widget.api)
        else if (_selectedTab == 1)
          MarketSignalsPanel(
            state: widget.state,
            busy: widget.busy,
            api: widget.api,
            action: widget.action,
          )
        else
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'ORDERS & ADVANCED DATA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: mutedColor,
                ),
              ),
              subtitle: const Text(
                'Track your orders first; inspect market depth and liquidity when needed.',
                style: TextStyle(fontSize: 11, color: mutedColor),
              ),
              children: [
                const SizedBox(height: 12),
                MyMarketOrdersPanel(
                  state: widget.state,
                  busy: widget.busy,
                  action: widget.action,
                  api: widget.api,
                ),
                const SizedBox(height: 24),
                MarketOrderBookPanel(state: widget.state),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: .15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: context.primaryColor.withValues(alpha: .4))
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? context.primaryColor : context.mutedColor,
              ),
              const SizedBox(width: 6),
              Text(
                subtitle != null ? '$title ($subtitle)' : title,
                maxLines: 1,
                style: context.controlStyle.copyWith(
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      key: 'energy',
      name: 'ENERGY',
      symbol: 'NRG',
      description:
          'Electrical power units and grid wattage consumed per cycle.',
      color: EarthResourceColors.energy,
      icon: Icons.bolt_rounded,
    ),
    CommodityMeta(
      key: 'food',
      name: 'FOOD',
      symbol: 'BIO',
      description:
          'Vertical farm harvest & bio-nutrients for human metabolic survival.',
      color: EarthResourceColors.food,
      icon: Icons.eco_outlined,
    ),
    CommodityMeta(
      key: 'material',
      name: 'MATERIALS',
      symbol: 'ORE',
      description:
          'Raw industrial base mineral feedstock from planetary extractions.',
      color: EarthResourceColors.materials,
      icon: Icons.terrain_outlined,
    ),
    CommodityMeta(
      key: 'components',
      name: 'COMPONENTS',
      symbol: 'MAT',
      description:
          'Precision mechanical sub-assemblies and fabricated structural modules.',
      color: EarthResourceColors.components,
      icon: Icons.precision_manufacturing_outlined,
    ),
    CommodityMeta(
      key: 'compute',
      name: 'COMPUTE',
      symbol: 'DAT',
      description:
          'Quantum processing, telemetry feeds, and algorithmic compute capacity.',
      color: EarthResourceColors.compute,
      icon: Icons.memory_rounded,
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

BigInt? _parseFixedDecimal(String value, int decimals) {
  final text = value.trim();
  if (text.isEmpty || text.startsWith('-')) return null;
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = BigInt.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals || !RegExp(r'^\d*$').hasMatch(fraction)) {
    return null;
  }
  return whole * BigInt.from(10).pow(decimals) +
      BigInt.parse(fraction.padRight(decimals, '0').isEmpty
          ? '0'
          : fraction.padRight(decimals, '0'));
}

BigInt _roundDivide(BigInt numerator, BigInt denominator) =>
    (numerator + denominator ~/ BigInt.from(2)) ~/ denominator;

BigInt? _estimatedQuoteUnits(String quantity, String price) {
  final quantityUnits = _parseFixedDecimal(quantity, 6);
  final priceUnits = _parseFixedDecimal(price, 2);
  if (quantityUnits == null ||
      priceUnits == null ||
      quantityUnits <= BigInt.zero ||
      priceUnits <= BigInt.zero) {
    return null;
  }
  return _roundDivide(quantityUnits * priceUnits, BigInt.from(1000000));
}

BigInt? _estimatedFeeUnits(BigInt? quoteUnits, String feeRate) {
  final rateUnits = _parseFixedDecimal(feeRate, 6);
  if (quoteUnits == null || rateUnits == null) return null;
  return _roundDivide(quoteUnits * rateUnits, BigInt.from(1000000));
}

Future<void> showPlaceOrderDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action, {
  required String initialProduct,
  required String initialPrice,
  String initialSide = 'buy',
  String buyerFeeRate = '0',
  EarthApi api = const EarthApi(),
}) async {
  String selectedProduct = initialProduct;
  String side = initialSide;
  MarketQuote serverQuote = MarketQuote.failure('');
  bool quoteLoading = false;
  bool reviewed = false;
  final qtyController = TextEditingController(text: '10');
  final priceController = TextEditingController(text: initialPrice.trim());

  Future<void> refreshQuote(
      void Function(void Function()) setDialogState) async {
    final quantity = qtyController.text.trim();
    final price = priceController.text.trim();
    final parsedQuantity = double.tryParse(quantity);
    final parsedPrice = double.tryParse(price);
    if (parsedQuantity == null ||
        parsedQuantity <= 0 ||
        parsedPrice == null ||
        parsedPrice <= 0) {
      setDialogState(() => serverQuote = MarketQuote.failure(''));
      return;
    }
    setDialogState(() => quoteLoading = true);
    try {
      final quote = await api.quoteOrder(
        product: selectedProduct,
        quantity: quantity,
        limitPrice: price,
        side: side,
      );
      setDialogState(() {
        serverQuote = quote;
        quoteLoading = false;
      });
    } catch (_) {
      setDialogState(() {
        serverQuote = MarketQuote.failure('Market quote unavailable');
        quoteLoading = false;
      });
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final quantityText = qtyController.text.trim();
        final priceText = priceController.text.trim();
        final qty = double.tryParse(quantityText) ?? 0.0;
        final price = double.tryParse(priceText) ?? 0.0;
        final quoteOk = serverQuote.ok;
        final estimateBaseUnits = _estimatedQuoteUnits(quantityText, priceText);
        final estimateFeeUnits = side == 'buy'
            ? _estimatedFeeUnits(estimateBaseUnits, buyerFeeRate)
            : BigInt.zero;
        final estimateTotalUnits =
            estimateBaseUnits == null || estimateFeeUnits == null
                ? null
                : estimateBaseUnits + estimateFeeUnits;
        final meta = CommodityMeta.forProduct(selectedProduct);

        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.subtleBorderColor),
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
                        onSelectionChanged: (set) {
                          setDialogState(() {
                            side = set.first;
                            reviewed = false;
                            serverQuote = MarketQuote.failure('');
                          });
                        },
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
                      setDialogState(() {
                        selectedProduct = value;
                        reviewed = false;
                        serverQuote = MarketQuote.failure('');
                      });
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
                  onChanged: (_) {
                    setDialogState(() {
                      reviewed = false;
                      serverQuote = MarketQuote.failure('');
                    });
                  },
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
                  onChanged: (_) {
                    setDialogState(() {
                      reviewed = false;
                      serverQuote = MarketQuote.failure('');
                    });
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.inkColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('EST. base value:',
                              style:
                                  TextStyle(fontSize: 11, color: mutedColor)),
                          Text(
                              estimateBaseUnits == null
                                  ? 'Enter valid values'
                                  : formatCreditUnits(
                                      estimateBaseUnits.toString()),
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (estimateFeeUnits != null &&
                          estimateFeeUnits > BigInt.zero) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'EST. buyer fee:',
                              style: TextStyle(fontSize: 11, color: mutedColor),
                            ),
                            Text(formatCreditUnits(estimateFeeUnits.toString()),
                                style: const TextStyle(
                                    fontSize: 11, color: mutedColor)),
                          ],
                        ),
                      ],
                      Divider(height: 14, color: context.subtleBorderColor),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            side == 'buy'
                                ? 'EST. total escrow:'
                                : 'EST. gross proceeds:',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            estimateTotalUnits == null
                                ? 'Enter valid values'
                                : formatCreditUnits(
                                    estimateTotalUnits.toString()),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: side == 'buy'
                                  ? cyanAccentColor
                                  : context.warningColor,
                            ),
                          ),
                        ],
                      ),
                      if (quoteOk) ...[
                        Divider(height: 14, color: context.subtleBorderColor),
                        const Text('AUTHORITATIVE SERVER QUOTE',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: cyanAccentColor)),
                        Text(
                            'Base value: ${formatCreditUnits(serverQuote.baseValueUnits)}'),
                        Text(
                            'Buyer fee (${serverQuote.feeBps} bps): ${formatCreditUnits(serverQuote.feeUnits)}'),
                        Text(
                            'Total escrow: ${formatCreditUnits(serverQuote.totalEscrowUnits)}'),
                      ],
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
              onPressed: qty <= 0 || price <= 0 || quoteLoading
                  ? null
                  : () async {
                      if (!reviewed || !quoteOk) {
                        await refreshQuote(setDialogState);
                        if (serverQuote.ok) {
                          setDialogState(() => reviewed = true);
                        }
                        return;
                      }
                      Navigator.pop(dialogContext);
                      await action(() => api.submitOrder(
                            selectedProduct,
                            priceText,
                            side: side,
                            quantity: quantityText,
                          ));
                    },
              child:
                  Text(reviewed && quoteOk ? 'SUBMIT ORDER' : 'REVIEW ORDER'),
            ),
          ],
        );
      },
    ),
  );

  qtyController.dispose();
  priceController.dispose();
}

class _DepthLevel {
  final String price;
  final String quantity;
  final int orderCount;

  const _DepthLevel({
    required this.price,
    required this.quantity,
    required this.orderCount,
  });
}

class MarketSignalsPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;
  final EarthApi api;

  const MarketSignalsPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
    this.api = const EarthApi(),
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
  final FocusNode _qtyFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  Map<String, HouseCommodityPosition> _positions = const {};
  final Map<String, List<MarketCandle>> _hourlyCandles = {};
  final Map<String, List<MarketCandle>> _dailyCandles = {};
  final Map<String, MarketBook> _books = {};
  MarketCandleInterval _candleInterval = MarketCandleInterval.hourly;
  bool _loadingCandles = false;
  bool _loadingPositions = false;
  bool _showDepth = false;
  bool _loadingDepth = false;
  String? _depthError;

  Color get _groupSurface => EarthThemeController.instance.cardSurface;

  @override
  void initState() {
    super.initState();
    _initDefaultCommodity();
    _loadPositions();
    _loadCandles(_selectedCommodity, _candleInterval);
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

  String _instrumentFor(String product) => 'SPOT-${product.toUpperCase()}';

  List<MarketCandle> _candlesFor(String product) =>
      (_candleInterval == MarketCandleInterval.hourly
          ? _hourlyCandles[product]
          : _dailyCandles[product]) ??
      const [];

  Future<void> _loadCandles(
      String product, MarketCandleInterval interval) async {
    if (_loadingCandles || _candlesFor(product).isNotEmpty) return;
    _loadingCandles = true;
    try {
      final candles = await widget.api.marketCandles(
        _instrumentFor(product),
        interval: interval,
      );
      if (!mounted) return;
      setState(() {
        if (interval == MarketCandleInterval.hourly) {
          _hourlyCandles[product] = candles;
        } else {
          _dailyCandles[product] = candles;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (interval == MarketCandleInterval.hourly) {
            _hourlyCandles[product] = const [];
          } else {
            _dailyCandles[product] = const [];
          }
        });
      }
    } finally {
      _loadingCandles = false;
    }
  }

  void _setCandleInterval(MarketCandleInterval interval) {
    if (_candleInterval == interval) return;
    setState(() => _candleInterval = interval);
    _loadCandles(_selectedCommodity, interval);
  }

  Future<void> _loadPositions() async {
    if (_loadingPositions) return;
    _loadingPositions = true;
    try {
      final response = await widget.api.marketHousePositions();
      if (!mounted) return;
      final positions = <String, HouseCommodityPosition>{};
      for (final position in response) {
        final product = position.product.toLowerCase();
        if (product.isNotEmpty) positions[product] = position;
      }
      setState(() => _positions = positions);
    } catch (_) {
      if (mounted) setState(() => _positions = const {});
    } finally {
      _loadingPositions = false;
    }
  }

  @override
  void didUpdateWidget(covariant MarketSignalsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.api != widget.api) {
      _loadPositions();
    }
  }

  HouseCommodityPosition? _position(String product) => _positions[product];

  double? _availableQuantity(String product) =>
      double.tryParse(_position(product)?.availableQuantity ?? '');

  double? _reservedQuantity(String product) =>
      double.tryParse(_position(product)?.reservedQuantity ?? '');

  String _quantityLabel(double? value) => value == null
      ? 'UNAVAILABLE'
      : value.toString().replaceFirst(RegExp(r'\.0$'), '');

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _qtyFocusNode.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  void _refreshOrderTotals() {
    if (mounted) setState(() {});
  }

  void _setSellQuantityFraction(double fraction) {
    final available = _availableQuantity(_selectedCommodity);
    if (available == null || available <= 0) return;
    _qtyController.text = _quantityLabel(available * fraction);
    _refreshOrderTotals();
  }

  Widget _sellQuantityPreset(String label, double fraction) {
    return OutlinedButton(
      onPressed: () => _setSellQuantityFraction(fraction),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  void _initDefaultCommodity() {
    final firstKey = widget.state.market.keys.firstOrNull ?? 'material';
    _selectedCommodity = firstKey;
    final productData = widget.state.market[firstKey] as Map<String, dynamic>?;
    final price = asDouble(productData?['price']);
    final pStr = price?.toStringAsFixed(2) ?? '';
    _buyPrice = pStr;
    _sellPrice = pStr;
    _priceController.text = pStr;
  }

  void _selectCommodity(String key) {
    setState(() {
      _selectedCommodity = key;
      final productData = widget.state.market[key] as Map<String, dynamic>?;
      final price = asDouble(productData?['price']);
      final pStr = price?.toStringAsFixed(2) ?? '';
      _buyPrice = pStr;
      _sellPrice = pStr;
      _priceController.text = pStr;
    });
    _loadCandles(key, _candleInterval);
    if (_showDepth) _loadDepth(key);
  }

  Future<void> _loadDepth(String product) async {
    if (_loadingDepth || _books.containsKey(product)) return;
    setState(() {
      _loadingDepth = true;
      _depthError = null;
    });
    try {
      final book = await widget.api.marketBook(_instrumentFor(product));
      if (!mounted) return;
      setState(() => _books[product] = book);
    } catch (_) {
      if (mounted) setState(() => _depthError = 'Market depth unavailable.');
    } finally {
      if (mounted) setState(() => _loadingDepth = false);
    }
  }

  Future<void> _toggleDepth() async {
    if (_showDepth) {
      setState(() => _showDepth = false);
      return;
    }
    setState(() => _showDepth = true);
    await _loadDepth(_selectedCommodity);
  }

  BigInt? _parseFixed(String value, int decimals) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final negative = text.startsWith('-');
    final unsigned =
        (negative || text.startsWith('+')) ? text.substring(1) : text;
    final parts = unsigned.split('.');
    if (parts.length > 2 || parts.first.isEmpty) return null;
    final whole = BigInt.tryParse(parts.first);
    final fraction = parts.length == 2 ? parts[1] : '';
    if (whole == null ||
        !RegExp(r'^\d*$').hasMatch(fraction) ||
        fraction.length > decimals) {
      return null;
    }
    final scaled = whole * BigInt.from(10).pow(decimals) +
        BigInt.parse(fraction.padRight(decimals, '0').isEmpty
            ? '0'
            : fraction.padRight(decimals, '0'));
    return negative ? -scaled : scaled;
  }

  String _formatFixed(BigInt value, int decimals) {
    final negative = value < BigInt.zero;
    final magnitude = value.abs();
    final scale = BigInt.from(10).pow(decimals);
    final whole = magnitude ~/ scale;
    final fraction = (magnitude % scale).toString().padLeft(decimals, '0');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  List<_DepthLevel> _aggregateDepth(List<MarketOrder> orders,
      {required bool bids}) {
    final quantities = <BigInt, BigInt>{};
    final counts = <BigInt, int>{};
    for (final order in orders) {
      final price = _parseFixed(order.limitPrice, 2);
      final quantity = _parseFixed(order.remainingQuantity, 6);
      if (price == null || quantity == null || quantity <= BigInt.zero) {
        continue;
      }
      quantities[price] = (quantities[price] ?? BigInt.zero) + quantity;
      counts[price] = (counts[price] ?? 0) + 1;
    }
    final prices = quantities.keys.toList()
      ..sort((a, b) => bids ? b.compareTo(a) : a.compareTo(b));
    return prices
        .map((price) => _DepthLevel(
              price: _formatFixed(price, 2),
              quantity: _formatFixed(quantities[price]!, 6),
              orderCount: counts[price]!,
            ))
        .toList(growable: false);
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

  Future<void> _confirmOrder({
    required BuildContext context,
    required String quantity,
    required String limitPrice,
    required String product,
    required String side,
  }) async {
    final quote = await widget.api.quoteOrder(
      product: product,
      quantity: quantity,
      limitPrice: limitPrice,
      side: side,
    );
    if (!mounted || !context.mounted || !quote.ok) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            '${side.toUpperCase()} ${CommodityMeta.forProduct(product).name}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Orders are evaluated at the next market clearing and may fill partially.',
                style: TextStyle(fontSize: 12, color: mutedColor)),
            const SizedBox(height: 12),
            Text('Quantity: $quantity units',
                style: const TextStyle(fontSize: 12)),
            Text('Limit price: $limitPrice Credits / unit',
                style: const TextStyle(fontSize: 12)),
            if (side == 'buy')
              Text('Buyer fee: ${formatCreditUnits(quote.feeUnits)}',
                  style: const TextStyle(fontSize: 12, color: mutedColor)),
            const SizedBox(height: 6),
            Text(
              side == 'buy'
                  ? 'Total escrow: ${formatCreditUnits(quote.totalEscrowUnits)}'
                  : 'Expected proceeds: ${formatCreditUnits(quote.totalEscrowUnits)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('CONFIRM ORDER')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.action(() => widget.api.submitOrder(
          product,
          limitPrice,
          side: side,
          quantity: quantity,
        ));
    if (mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
            content: Text(
                '${side.toUpperCase()} order submitted for $quantity ${CommodityMeta.forProduct(product).name.toLowerCase()} units.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = CommodityMeta.forProduct(_selectedCommodity);
    final productData =
        (widget.state.market[_selectedCommodity] as Map<String, dynamic>?) ??
            {};
    final currentPrice = asDouble(productData['price']);
    final chartPrice = currentPrice ?? 0.0;
    final supply = asInt(productData['supply']) ?? 0;
    final demand = asInt(productData['demand']) ?? 0;
    final candles = _candlesFor(_selectedCommodity);
    final prices = candles
        .map((candle) => double.tryParse(candle.close))
        .whereType<double>()
        .toList();

    double minPrice = prices.isNotEmpty
        ? prices.reduce((a, b) => a < b ? a : b)
        : (chartPrice > 0 ? chartPrice * 0.9 : 0.0);
    double maxPrice = prices.isNotEmpty
        ? prices.reduce((a, b) => a > b ? a : b)
        : (chartPrice > 0 ? chartPrice * 1.1 : 1.0);
    if (minPrice == maxPrice && maxPrice > 0) {
      minPrice *= 0.95;
      maxPrice *= 1.05;
    }

    final totalPressure = (supply + demand).clamp(1, 999999);
    final demandPct = (demand / totalPressure).clamp(0.0, 1.0);

    final qty = double.tryParse(_qtyController.text.trim()) ?? 0;
    final limitPrice = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final isBuy = _orderSide == 'buy';
    final estimatedBaseUnits =
        _estimatedQuoteUnits(_qtyController.text, _priceController.text);
    final estimatedFeeUnits = isBuy
        ? _estimatedFeeUnits(
            estimatedBaseUnits, widget.state.marketFeeRate.toString())
        : BigInt.zero;
    final estimatedEscrowUnits =
        estimatedBaseUnits == null || estimatedFeeUnits == null
            ? null
            : estimatedBaseUnits + estimatedFeeUnits;
    final availableSellQuantity = _availableQuantity(_selectedCommodity);
    final reservedSellQuantity = _reservedQuantity(_selectedCommodity);

    final sideColor = isBuy ? cyanAccentColor : context.warningColor;
    final canSubmit = !widget.busy && qty > 0 && limitPrice > 0;

    final currentDay = asIntOr(widget.state.clock['day'], 1);
    final currentMinute = asIntOr(widget.state.clock['minute'], 0);
    final market = widget.state.json['market'] is Map
        ? Map<String, dynamic>.from(widget.state.json['market'] as Map)
        : const <String, dynamic>{};
    // Legacy snapshots may not carry the server schedule yet; keep their
    // historical display stable until the next world refresh supplies it.
    final interval = asIntOr(market['clearingIntervalMinutes'], 240);
    final nextMinute = asIntOr(market['nextClearingGameMinute'],
        currentMinute + (interval - (currentMinute % interval)));
    final epochIndex = asIntOr(
        market['epoch'], (currentDay * 6) + (currentMinute ~/ interval));
    final minutesToNextEpoch = (nextMinute - currentMinute).clamp(0, interval);
    final remHours = minutesToNextEpoch ~/ 60;
    final remMins = minutesToNextEpoch % 60;
    final countdownStr =
        '${remHours.toString().padLeft(2, '0')}:${remMins.toString().padLeft(2, '0')}';

    return EarthPanel(
      key: widget.panelKey,
      title: 'TRADE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Buy resources you need, sell what your businesses do not use, or leave an order open for a later fill.\n\n• Compare the current price with your stock and production plans before acting.\n\n• Orders may fill later, partially, or at a market-cleared price.\n\n• The market supports your businesses; it is not the main source of progression.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marketTopicHeading(
            context,
            'TRADE',
            description:
                '• Decide whether to buy, sell, produce internally, or wait. Open orders can fill later.',
          ),
          // 0. BATCH AUCTION CLEARING BANNER
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _groupSurface,
              borderRadius: BorderRadius.circular(8),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            'NEXT MARKET CLEARING',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                              color: inkColor,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Orders may fill fully, partially, or later at the clearing price.',
                        style: TextStyle(fontSize: 9.5, color: mutedColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    _auctionMetric('EPOCH', '#$epochIndex'),
                    _auctionMetric('NEXT CLEARING', countdownStr),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 34),
          _marketTopicHeading(
            context,
            'MARKET PRICES & STOCK',
            description:
                '• Choose a commodity to compare its clearing price, best bid/ask, open buy/sell interest, and your current inventory.',
          ),
          _buildCommodityMarketTable(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _loadingDepth ? null : _toggleDepth,
              icon: Icon(_showDepth ? Icons.expand_less : Icons.unfold_more,
                  size: 15),
              label: Text(_showDepth ? 'HIDE DEPTH' : 'VIEW DEPTH'),
            ),
          ),
          if (_showDepth) _buildDepthPanel(context),
          const SizedBox(height: 34),

          // 2. INLINE COMMODITY GRAPH & BUY/SELL TRADING CONTROLS (NO EXTRA SUBWIDGET CONTAINER)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1000;

              final chartAndDepthSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChartModeToggle(context),
                  const SizedBox(height: 8),
                  // Price trend/candle chart
                  Container(
                    height: _candleInterval == MarketCandleInterval.daily
                        ? 280
                        : 140,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _candleInterval == MarketCandleInterval.daily
                        ? CandlestickChartWidget(
                            candles: candles,
                            ma7: const [],
                            ma25: const [],
                            commodity: meta.name,
                            height: 260,
                          )
                        : prices.length >= 2
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
                                  'No candle data available for this instrument.',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: mutedColor.withValues(alpha: .7)),
                                ),
                              ),
                  ),
                  const SizedBox(height: 12),

                  // Supply and demand
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final demandLabel =
                              'OPEN BUY INTEREST: $demand UNITS (${(demandPct * 100).toStringAsFixed(0)}%)';
                          final supplyLabel =
                              'OPEN SELL INTEREST: $supply UNITS (${((1 - demandPct) * 100).toStringAsFixed(0)}%)';
                          final demandText = Text(demandLabel,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: cyanAccentColor));
                          final supplyText = Text(supplyLabel,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.warningColor));
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
                                child: Container(color: context.warningColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );

              final tradeTerminalSection = Container(
                  decoration: BoxDecoration(
                    color: _groupSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTabController(
                        length: 2,
                        initialIndex: isBuy ? 0 : 1,
                        child: TabBar(
                          onTap: (index) =>
                              _onSideChanged(index == 0 ? 'buy' : 'sell'),
                          indicatorColor:
                              isBuy ? cyanAccentColor : context.warningColor,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicatorWeight: 2.5,
                          dividerColor: EarthColors.borderSubtle,
                          labelColor: inkColor,
                          unselectedLabelColor: mutedColor,
                          labelStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800),
                          tabs: [
                            Tab(text: 'BUY ${meta.symbol}'),
                            Tab(text: 'SELL ${meta.symbol}'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // All order inputs and calculated values stay in one scan line.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _qtyController,
                                    focusNode: _qtyFocusNode,
                                    keyboardType: TextInputType.number,
                                    onEditingComplete: () =>
                                        FocusScope.of(context).unfocus(),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      labelText: 'QUANTITY',
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
                                      suffixIcon: TextButton(
                                        onPressed: () {
                                          if (isBuy) return;
                                          final maxQuantity =
                                              _availableQuantity(
                                                  _selectedCommodity);
                                          if (maxQuantity == null ||
                                              maxQuantity <= 0) {
                                            return;
                                          }
                                          _qtyController.text =
                                              _quantityLabel(maxQuantity);
                                          _refreshOrderTotals();
                                        },
                                        child: const Text('MAX'),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _priceController,
                                    focusNode: _priceFocusNode,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    onEditingComplete: () =>
                                        FocusScope.of(context).unfocus(),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      labelText: 'LIMIT PRICE (CREDITS / UNIT)',
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
                                      suffixIcon: TextButton(
                                        onPressed: currentPrice == null
                                            ? null
                                            : () {
                                                _priceController.text =
                                                    currentPrice
                                                        .toStringAsFixed(2);
                                                _refreshOrderTotals();
                                              },
                                        child: const Text('LAST CLEAR'),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: _orderValue(
                                    'EST. BUYER FEE',
                                    estimatedFeeUnits == null
                                        ? '—'
                                        : formatCreditUnits(
                                            estimatedFeeUnits.toString()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: _orderValue(
                                    isBuy ? 'EST. ESCROW' : 'EST. PROCEEDS',
                                    estimatedEscrowUnits == null
                                        ? '—'
                                        : formatCreditUnits(
                                            estimatedEscrowUnits.toString()),
                                  ),
                                ),
                              ],
                            ),
                            if (!isBuy) ...[
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('SELL PRESET',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: mutedColor)),
                                  _sellQuantityPreset('25%', .25),
                                  _sellQuantityPreset('50%', .50),
                                  _sellQuantityPreset('75%', .75),
                                  _sellQuantityPreset('MAX', 1),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),

                            Text(
                              isBuy
                                  ? 'Available balance and fee are verified by the server during review.'
                                  : 'Sellable: ${_quantityLabel(availableSellQuantity)} units · Reserved: ${_quantityLabel(reservedSellQuantity)} units',
                              style: const TextStyle(
                                  fontSize: 10, color: mutedColor),
                            ),
                            if (!isBuy &&
                                (availableSellQuantity == null ||
                                    qty > availableSellQuantity)) ...[
                              const SizedBox(height: 4),
                              Text(
                                isBuy
                                    ? 'Reduce quantity or price to fit your available Credits.'
                                    : 'Some inventory is already reserved by another sell order.',
                                style: TextStyle(
                                    fontSize: 10, color: context.warningColor),
                              ),
                            ],
                            const SizedBox(height: 12),

                            // Submit Action Button
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: !canSubmit
                                    ? null
                                    : () async {
                                        await _confirmOrder(
                                          context: context,
                                          quantity: _qtyController.text.trim(),
                                          limitPrice:
                                              _priceController.text.trim(),
                                          product: _selectedCommodity,
                                          side: _orderSide,
                                        );
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      sideColor.withValues(alpha: .85),
                                  foregroundColor: context.canvasColor,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
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
                        ),
                      ),
                    ],
                  ));

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
                  const SizedBox(height: 34),
                  tradeTerminalSection,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _auctionMetric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                  color: mutedColor)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800, color: inkColor)),
        ],
      );

  Widget _orderValue(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: .7,
                  color: mutedColor)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: inkColor),
              overflow: TextOverflow.ellipsis),
        ],
      );

  Widget _buildDepthPanel(BuildContext context) {
    final book = _books[_selectedCommodity];
    if (_loadingDepth && book == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Loading batch-auction depth…',
            style: TextStyle(fontSize: 11, color: mutedColor)),
      );
    }
    if (_depthError != null && book == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_depthError!,
            style: TextStyle(fontSize: 11, color: context.warningColor)),
      );
    }
    if (book == null) return const SizedBox.shrink();
    final bids = _aggregateDepth(book.bids, bids: true);
    final asks = _aggregateDepth(book.asks, bids: false);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BATCH-AUCTION DEPTH',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
          const SizedBox(height: 3),
          const Text(
            'Open bids and asks waiting for the next uniform-price clearing; this is not a continuous matching order book.',
            style: TextStyle(fontSize: 10, color: mutedColor),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildDepthSide('BIDS', bids, cyanAccentColor)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildDepthSide('ASKS', asks, context.warningColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepthSide(String title, List<_DepthLevel> levels, Color color) {
    if (levels.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('No open levels',
              style: TextStyle(fontSize: 10, color: mutedColor)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        for (final level in levels.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Expanded(
                    child: Text(level.price,
                        style: const TextStyle(fontSize: 10))),
                Text(level.quantity,
                    style: const TextStyle(fontSize: 10, color: mutedColor)),
                const SizedBox(width: 5),
                Text('(${level.orderCount})',
                    style: const TextStyle(fontSize: 9, color: mutedColor)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCommodityMarketTable() => Container(
        decoration: BoxDecoration(
          color: _groupSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EarthColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Builder(builder: (context) {
          final entries = widget.state.market.entries.toList();
          return Column(
            children: [
              ...entries.indexed.map((indexed) {
                final entry = indexed.$2;
                final key = entry.key;
                final data = (entry.value as Map<String, dynamic>?) ?? {};
                final meta = CommodityMeta.forProduct(key);
                final supply = asInt(data['supply']) ?? 0;
                final demand = asInt(data['demand']) ?? 0;
                final position = _position(key);
                final availableQuantity =
                    position?.availableQuantity ?? 'UNAVAILABLE';
                final reservedQuantity =
                    position?.reservedQuantity ?? 'UNAVAILABLE';
                final selected = key == _selectedCommodity;
                final pressure = _marketPressure(supply, demand);
                final last = indexed.$1 == entries.length - 1;
                return InkWell(
                  onTap: () => _selectCommodity(key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? meta.color.withValues(alpha: .12)
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                            color: selected ? meta.color : Colors.transparent,
                            width: 3),
                        bottom: last
                            ? BorderSide.none
                            : const BorderSide(color: EarthColors.borderSubtle),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(meta.icon, size: 28, color: meta.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            children: [
                              Row(children: [
                                Expanded(child: _commodityName(meta)),
                                _commodityPrice(data),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                Text(
                                    'Available: $availableQuantity · Reserved: $reservedQuantity',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: mutedColor)),
                                const Spacer(),
                                _MiniTrendBadge(
                                    candles: _hourlyCandles[key] ?? const []),
                                const SizedBox(width: 10),
                                _pressureLabel(
                                    context, pressure, supply, demand),
                              ]),
                              const SizedBox(height: 3),
                              Text(
                                'BEST BID ${data['bestBid']?.toString() ?? 'UNAVAILABLE'} · BEST ASK ${data['bestAsk']?.toString() ?? 'UNAVAILABLE'} · OPEN BUY ${data['demand']?.toString() ?? 'UNAVAILABLE'} · OPEN SELL ${data['supply']?.toString() ?? 'UNAVAILABLE'}',
                                style: const TextStyle(
                                    fontSize: 9, color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      );

  Widget _commodityName(CommodityMeta meta) => Text(meta.name,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: inkColor),
      overflow: TextOverflow.ellipsis);

  Widget _commodityPrice(Map<String, dynamic> data) => Text(
        '${asDouble(data['price'])?.toStringAsFixed(2) ?? '—'} C',
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: inkColor),
      );

  String _marketPressure(int supply, int demand) {
    if (demand > supply * 1.15) return 'OPEN BUY HIGH';
    if (supply > demand * 1.15) return 'OPEN SELL HIGH';
    return 'OPEN INTEREST BALANCED';
  }

  Widget _pressureLabel(
      BuildContext context, String pressure, int supply, int demand) {
    final color = pressure == 'OPEN BUY HIGH'
        ? cyanAccentColor
        : pressure == 'OPEN SELL HIGH'
            ? context.warningColor
            : context.mutedColor;
    return Text(pressure,
        style: TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w700, color: color));
  }
}

extension on _MarketSignalsPanelState {
  Widget _buildChartModeToggle(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SegmentedButton<MarketCandleInterval>(
            segments: const [
              ButtonSegment(
                  value: MarketCandleInterval.hourly, label: Text('TREND')),
              ButtonSegment(
                  value: MarketCandleInterval.daily, label: Text('CANDLES')),
            ],
            selected: {_candleInterval},
            onSelectionChanged: (selection) =>
                _setCandleInterval(selection.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

class _MiniTrendBadge extends StatelessWidget {
  final List<MarketCandle> candles;

  const _MiniTrendBadge({required this.candles});

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) return const SizedBox.shrink();
    final latest = double.tryParse(candles.last.close);
    final oldest = double.tryParse(candles.first.close);
    if (latest == null || oldest == null || oldest == 0) {
      return const SizedBox.shrink();
    }
    final change = latest - oldest;
    final pct = (change / oldest) * 100;
    final isPos = change >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (isPos ? context.successColor : context.warningColor)
            .withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isPos ? '+' : ''}${pct.toStringAsFixed(1)}% trend',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isPos ? context.successColor : context.warningColor,
        ),
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
      title: 'PRE-CLEARING ORDER BOOK',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Aggregated Order Depth: Displays open buy bids and sell asks grouped by commodity and best price tiers, showing total volume waiting for batch execution.\n\n• Order Count & Liquidity: Number of discrete market participants contributing liquidity to each price tier.\n\n• Central Clearing Settlement: Orders do not execute via continuous match; all qualifying bids and asks cross simultaneously at the uniform clearing price when the batch clears.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _marketTopicHeading(context, 'PRE-CLEARING ORDER BOOK',
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
                    border: Border.all(color: context.subtleBorderColor),
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
  final EarthApi api;

  const MyMarketOrdersPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.api = const EarthApi(),
  });

  @override
  State<MyMarketOrdersPanel> createState() => _MyMarketOrdersPanelState();
}

class _MyMarketOrdersPanelState extends State<MyMarketOrdersPanel> {
  String _filter = 'all';
  List<MarketOrder> _orders = const [];
  String? _nextCursor;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _orders = _snapshotOrders(widget.state);
    _loadOrders();
  }

  List<MarketOrder> _snapshotOrders(EarthState state) => state.marketOrders
      .whereType<Map>()
      .map((raw) => MarketOrder.fromJson(Map<String, dynamic>.from(raw)))
      .toList();

  @override
  void didUpdateWidget(covariant MyMarketOrdersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.api != widget.api) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders({bool append = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final page = await widget.api.marketOrders(
        cursor: append ? _nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        _orders = append ? [..._orders, ...page.orders] : page.orders;
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      // Keep current/open snapshot orders visible while the complete history
      // read model is temporarily unavailable. No closed order is synthesized.
      if (!mounted || append) return;
      setState(() {
        _orders = _snapshotOrders(widget.state);
        _nextCursor = null;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOrders = _orders;

    final filtered = allOrders.where((order) {
      final status = order.status.toLowerCase();
      if (_filter == 'active') return status == 'open' || status == 'partial';
      if (_filter == 'filled') return status == 'filled';
      if (_filter == 'cancelled') {
        return status == 'cancelled' ||
            status == 'refunded' ||
            status == 'rejected';
      }
      return true;
    }).toList();

    return EarthPanel(
      title: 'MY ORDERS',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Order Status Categorization: Filter across All, Active (Open / Partially Filled), Completed (Filled), and Cancelled limit orders.\n\n• Order Lifecycle Indicators: Tracks submitted quantity, filled volume progress, limit price per unit, and locked escrow reserves.\n\n• Escrow & Cancellation: Active limit buy orders securely lock credits in escrow; active sell orders lock inventory units. Cancelling an order instantly unlocks and restores escrowed assets.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marketTopicHeading(context, 'MY ORDERS',
              description:
                  '• Track active, filled, and cancelled orders, including escrow and execution progress.'),
          // Filter Tabs
          Row(
            children: [
              _tabButton(context, 'ALL (${allOrders.length})', 'all'),
              const SizedBox(width: 6),
              _tabButton(context, 'ACTIVE ORDERS', 'active'),
              const SizedBox(width: 6),
              _tabButton(context, 'FILLED ORDERS', 'filled'),
              const SizedBox(width: 6),
              _tabButton(context, 'CANCELLED ORDERS', 'cancelled'),
            ],
          ),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            const Text(
              'No market orders on record.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...filtered.map((order) {
              final id = order.id;
              final side = order.side.toUpperCase();
              final product = (order.product ?? '').toUpperCase();
              final quantityText = order.quantity;
              final filledText = order.filledQuantity;
              final remainingText = order.remainingQuantity;
              final quantity = double.tryParse(quantityText) ?? 0;
              final filledQty = double.tryParse(filledText) ?? 0;
              final remaining = double.tryParse(remainingText) ?? 0;
              final limitPriceText = order.limitPrice;
              final status = order.status.toLowerCase();
              final reservedEscrow = order.remainingReservation;
              final releasedEscrow = order.releasedEscrow;
              final cancellationRefund = order.cancellationRefund;
              final fee = order.totalFeePaid;
              final totalValue = order.filledGrossValue;
              final settlementPrice = order.weightedAverageFillPrice;

              final isBuy = side == 'BUY';
              final fillProgress =
                  quantity > 0 ? (filledQty / quantity).clamp(0.0, 1.0) : 0.0;
              final canCancel =
                  (status == 'open' || status == 'partial') && !widget.busy;

              Color statusColor = mutedColor;
              if (status == 'open') statusColor = context.primaryColor;
              if (status == 'partial') statusColor = context.warningColor;
              if (status == 'filled') statusColor = cyanAccentColor;
              if (status == 'cancelled' || status == 'rejected') {
                statusColor = context.errorColor;
              }
              if (status == 'refunded') statusColor = context.successColor;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.subtleBorderColor),
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
                                (isBuy ? cyanAccentColor : context.warningColor)
                                    .withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            side,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isBuy
                                  ? cyanAccentColor
                                  : context.warningColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$side $product · $quantityText units @ $limitPriceText C',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: inkColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Filled: $filledText / $quantityText ($remainingText remaining) · Filled gross: $totalValue C',
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
                        backgroundColor: context.subtleBorderColor,
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
                            'Weighted fill price: $settlementPrice C · ${isBuy ? 'Buyer fee paid' : 'Fee paid'}: $fee C',
                            style: const TextStyle(
                                fontSize: 9.5, color: cyanAccentColor),
                          ),
                        if (reservedEscrow != '0' &&
                            reservedEscrow != '0.000000')
                          Text(
                            'Reserved escrow: $reservedEscrow',
                            style: TextStyle(
                                fontSize: 9.5, color: context.primaryColor),
                          ),
                        if (releasedEscrow != '0' &&
                            releasedEscrow != '0.000000')
                          Text(
                            'Released escrow: $releasedEscrow',
                            style: TextStyle(
                                fontSize: 9.5, color: context.successColor),
                          ),
                        if (cancellationRefund != '0' &&
                            cancellationRefund != '0.000000')
                          Text(
                            'Cancellation refund: $cancellationRefund',
                            style: TextStyle(
                                fontSize: 9.5, color: context.successColor),
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
                          onPressed: () async {
                            final shouldCancel = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('CANCEL ORDER?'),
                                content: Text(
                                    '$product · $remaining units remaining\n\nReserved assets will be released back to your House.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('KEEP ORDER'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('CANCEL ORDER'),
                                  ),
                                ],
                              ),
                            );
                            if (shouldCancel != true || !mounted) return;
                            await widget
                                .action(() => widget.api.cancelOrder(id));
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Order cancelled and reserved assets released.'),
                                ),
                              );
                            }
                          },
                          child: const Text('CANCEL ORDER',
                              style: TextStyle(fontSize: 9.5)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          if (_nextCursor != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: OutlinedButton(
                onPressed: _loading ? null : () => _loadOrders(append: true),
                child: Text(_loading ? 'LOADING…' : 'LOAD MORE ORDERS'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, String label, String key) {
    final isSel = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel
              ? context.secondaryColor.withValues(alpha: .2)
              : context.inkColor.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color:
                  isSel ? context.secondaryColor : context.subtleBorderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? context.inkColor : context.mutedColor,
            letterSpacing: .8,
          ),
        ),
      ),
    );
  }
}
