import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/market/market_panels.dart';

void main() {
  testWidgets('MarketOrderBookPanel and MyMarketOrdersPanel render book depth and orders',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {'food': 100, 'energy': 200, 'material': 300, 'compute': 50},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {
        'products': {
          'food': {'price': 12.5, 'change': 0.05, 'volume': 1500},
          'energy': {'price': 8.0, 'change': -0.02, 'volume': 3200},
        },
        'book': [
          {'resource': 'food', 'side': 'buy', 'price': 12.0, 'quantity': 100},
          {'resource': 'food', 'side': 'sell', 'price': 13.0, 'quantity': 50},
        ],
        'trades': [
          {'resource': 'food', 'price': 12.5, 'quantity': 20, 'executedAt': '10:00'},
        ],
        'orders': [
          {
            'id': 'ORD-101',
            'product': 'food',
            'side': 'buy',
            'limit_price': 12.0,
            'quantity': 100,
            'filled_quantity': 0,
            'status': 'open',
          },
        ],
        'feeRate': 0.01,
      },
    });

    bool cancelTriggered = false;

    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const MarketOrderBookPanel(state: state),
                MyMarketOrdersPanel(
                  state: state,
                  busy: false,
                  action: (cb) async {
                    cancelTriggered = true;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('CENTRAL MARKET / ORDER BOOK'), findsOneWidget);
    expect(find.text('MY MARKET ORDERS / LIFECYCLE'), findsOneWidget);
    expect(find.textContaining('BUY FOOD'), findsOneWidget);

    // Cancel order
    final cancelBtn = find.text('CANCEL ORDER');
    if (cancelBtn.evaluate().isNotEmpty) {
      await tester.tap(cancelBtn.first);
      await tester.pumpAndSettle();
      expect(cancelTriggered, isTrue);
    }
  });
}
