import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

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
      text: initialPrice > 0 ? initialPrice.toString() : '50');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final qty = int.tryParse(qtyController.text.trim()) ?? 0;
        final price = double.tryParse(priceController.text.trim()) ?? 0.0;
        final baseTotal = qty * price;
        final fee = side == 'buy' ? baseTotal * feeRate : 0.0;
        final grandTotal = side == 'buy' ? baseTotal + fee : baseTotal;

        return AlertDialog(
          title: Text(
              'PLACE ${side.toUpperCase()} ORDER · ${selectedProduct.toUpperCase()}'),
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
                  items: const [
                    DropdownMenuItem(
                        value: 'material', child: Text('MATERIALS (MATR)')),
                    DropdownMenuItem(
                        value: 'components', child: Text('COMPONENTS (FABR)')),
                    DropdownMenuItem(
                        value: 'energy', child: Text('ENERGY (ENGY)')),
                    DropdownMenuItem(
                        value: 'compute', child: Text('COMPUTE (INFO)')),
                  ],
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
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Base value: ${baseTotal.toStringAsFixed(2)} C',
                        style: const TextStyle(fontSize: 11, color: mutedColor),
                      ),
                      if (side == 'buy' && feeRate > 0)
                        Text(
                          'Exchange fee (${(feeRate * 100).toStringAsFixed(2)}%): ${fee.toStringAsFixed(2)} C',
                          style:
                              const TextStyle(fontSize: 11, color: mutedColor),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        side == 'buy'
                            ? 'Total required escrow: ${grandTotal.toStringAsFixed(2)} C'
                            : 'Expected gross proceeds: ${grandTotal.toStringAsFixed(2)} C',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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

class MarketSignalsPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return EarthPanel(
      key: panelKey,
      title: 'CENTRAL MARKET / LIVE SIGNALS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Settlement fee: ${(state.marketFeeRate * 100).toStringAsFixed(2)}% · buyer total includes the disclosed fee',
                style: const TextStyle(color: mutedColor, fontSize: 10),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_shopping_cart, size: 14),
                label: const Text('CUSTOM LIMIT ORDER'),
                onPressed: busy
                    ? null
                    : () => showPlaceOrderDialog(
                          context,
                          action,
                          initialProduct:
                              state.market.keys.firstOrNull ?? 'material',
                          initialPrice: asDouble(
                                  state.market.values.firstOrNull?['price']) ??
                              50.0,
                          feeRate: state.marketFeeRate,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: state.market.entries.map((entry) {
              final product = entry.value as Map<String, dynamic>;
              return SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${product['price']} C',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'S ${product['supply']}  ·  D ${product['demand']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    _PriceTrend(history: priceHistory[entry.key]),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () =>
                                    action(() => const EarthApi().submitOrder(
                                          entry.key,
                                          asDouble(product['price']) ?? 0,
                                        )),
                            child: const Text('BUY 1'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () =>
                                    action(() => const EarthApi().submitOrder(
                                          entry.key,
                                          asDouble(product['price']) ?? 0,
                                          side: 'sell',
                                        )),
                            child: const Text('SELL 1'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => showPlaceOrderDialog(
                                      context,
                                      action,
                                      initialProduct: entry.key,
                                      initialPrice:
                                          asDouble(product['price']) ?? 0,
                                      feeRate: state.marketFeeRate,
                                    ),
                            child: const Text('ORDER…'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() =>
                                    const EarthApi().settleMarket(entry.key)),
                            child: const Text('SETTLE'),
                          ),
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

class _PriceTrend extends StatelessWidget {
  final dynamic history;

  const _PriceTrend({required this.history});

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
        color: change >= 0 ? Colors.teal : Colors.orange,
      ),
    );
  }
}

class MarketOrderBookPanel extends StatelessWidget {
  final EarthState state;

  const MarketOrderBookPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'CENTRAL MARKET / ORDER BOOK',
      child: state.marketBook.isEmpty
          ? const Text(
              'No open orders. The market is waiting for a new signal.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.marketBook.map((raw) {
                final row = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${row['product']}  ·  ${row['open_quantity']} open  ·  best ${row['best_price']} C',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class MyMarketOrdersPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final orders = state.marketOrders;
    return EarthPanel(
      title: 'MY MARKET ORDERS / LIFECYCLE',
      child: orders.isEmpty
          ? const Text('No market orders on record.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: orders.map((raw) {
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

                final canCancel =
                    (status == 'open' || status == 'partial') && !busy;

                Color statusColor = mutedColor;
                if (status == 'open') statusColor = Colors.lightBlueAccent;
                if (status == 'partial') statusColor = Colors.orangeAccent;
                if (status == 'filled') statusColor = cyanAccentColor;
                if (status == 'cancelled' || status == 'rejected') {
                  statusColor = Colors.redAccent;
                }
                if (status == 'refunded') statusColor = Colors.tealAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(6),
                    borderRadius: BorderRadius.circular(6),
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
                              '$side $product · $quantity units @ ${limitPrice.toStringAsFixed(2)} C',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Filled: $filledQty / $quantity ($remaining remaining) · Total: ${totalValue.toStringAsFixed(2)} C',
                        style: const TextStyle(fontSize: 10, color: mutedColor),
                      ),
                      if (settlementPrice != null && filledQty > 0)
                        Text(
                          'Settlement price: ${settlementPrice.toStringAsFixed(2)} C · Fee paid: ${fee.toStringAsFixed(2)} C',
                          style: const TextStyle(
                              fontSize: 10, color: cyanAccentColor),
                        ),
                      if (reservedCredits > 0)
                        Text(
                          'Reserved Credits in escrow: ${reservedCredits.toStringAsFixed(2)} C',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.lightBlueAccent),
                        ),
                      if (releasedEscrow > 0)
                        Text(
                          'Released escrow refund: ${releasedEscrow.toStringAsFixed(2)} C',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.tealAccent),
                        ),
                      if (canCancel) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                            ),
                            onPressed: () =>
                                action(() => const EarthApi().cancelOrder(id)),
                            child: const Text('CANCEL ORDER',
                                style: TextStyle(fontSize: 10)),
                          ),
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
