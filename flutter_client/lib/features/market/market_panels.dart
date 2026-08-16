import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

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
  final priceController =
      TextEditingController(text: initialPrice > 0 ? initialPrice.toString() : '50');

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
          title: Text('PLACE ${side.toUpperCase()} ORDER · ${selectedProduct.toUpperCase()}'),
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
                    DropdownMenuItem(value: 'material', child: Text('MATERIALS (MATR)')),
                    DropdownMenuItem(value: 'components', child: Text('COMPONENTS (FABR)')),
                    DropdownMenuItem(value: 'energy', child: Text('ENERGY (ENGY)')),
                    DropdownMenuItem(value: 'compute', child: Text('COMPUTE (INFO)')),
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
                          style: const TextStyle(fontSize: 11, color: mutedColor),
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

  const MarketSignalsPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
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
                          initialProduct: state.market.keys.firstOrNull ?? 'material',
                          initialPrice: (state.market.values.firstOrNull?['price'] as num?)?.toDouble() ?? 50.0,
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().submitOrder(
                                      entry.key,
                                      (product['price'] as num).toDouble(),
                                    )),
                            child: const Text('BUY 1'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().submitOrder(
                                      entry.key,
                                      (product['price'] as num).toDouble(),
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
                                      initialPrice: (product['price'] as num).toDouble(),
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
    return EarthPanel(
      title: 'MY OPEN MARKET ORDERS',
      child: state.marketOrders.isEmpty
          ? const Text('No open orders.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.marketOrders.map((raw) {
                final order = raw as Map<String, dynamic>;
                final remaining = (order['quantity'] as num) -
                    (order['filled_quantity'] as num);
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${order['side']} ${order['product']} · $remaining remaining · ${order['limit_price']} C',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .cancelOrder(order['id'] as String)),
                      child: const Text('CANCEL'),
                    ),
                  ],
                );
              }).toList(),
            ),
    );
  }
}
