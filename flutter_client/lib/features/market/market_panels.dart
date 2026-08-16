import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

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
          Text(
            'Settlement fee: ${(state.marketFeeRate * 100).toStringAsFixed(2)}% · buyer total includes the disclosed fee',
            style: const TextStyle(color: mutedColor, fontSize: 10),
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
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi().submitOrder(
                                entry.key,
                                (product['price'] as num).toDouble(),
                              )),
                      child: const Text('BUY 1'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi().submitOrder(
                                entry.key,
                                (product['price'] as num).toDouble(),
                                side: 'sell',
                              )),
                      child: const Text('SELL 1'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() =>
                              const EarthApi().settleMarket(entry.key)),
                      child: const Text('SETTLE'),
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
