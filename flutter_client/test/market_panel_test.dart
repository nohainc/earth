import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/market/market_panels.dart';

void main() {
  testWidgets('MarketSignalsPanel renders product prices and action buttons',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 1, 'minute': 100},
      'human': {'credits': 500, 'standing': 10, 'legacy': 0},
      'world': {'health': 100},
      'resources': {'energy': 100},
      'business': {'policy': 'reliability'},
      'technology': {
        'research': {'progress': 10}
      },
      'governance': {'proposals': []},
      'institutions': {
        'city': {'name': 'New Carthage'},
        'corporation': {'name': 'United Corps'}
      },
      'life': {'status': 'active', 'ageYears': 30, 'estatePeriodDays': 14},
      'market': {
        'products': {
          'energy': {
            'price': 12.5,
            'supply': 100,
            'demand': 80,
          },
        },
        'feeRate': 0.02,
        'book': [],
        'trades': [],
        'orders': [],
      },
    });

    String? executedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketSignalsPanel(
              state: state,
              busy: false,
              priceHistory: const {
                'energy': {
                  'history': [
                    {'gameDay': 10, 'price': 12.5},
                    {'gameDay': 9, 'price': 10.0},
                  ],
                },
              },
              action: (callback) async {
                executedAction = 'called';
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('MARKET ACTION / BUY & SELL'), findsOneWidget);
    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('12.50 C'), findsOneWidget);
    expect(find.text('SUPPLY HIGH'), findsOneWidget);
    expect(find.text('PLACE BUY ORDER'), findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Decide whether to buy'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('PLACE BUY ORDER'));
    await tester.tap(find.text('PLACE BUY ORDER'));
    expect(executedAction, 'called');
  });

  testWidgets(
      'MarketSignalsPanel preserves and restores quantity and price when switching buy and sell',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 10, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 1500},
      'world': {'health': 100},
      'resources': {'energy': 25},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'market': {
        'products': {
          'energy': {'price': 12.5, 'supply': 100, 'demand': 80},
        },
        'feeRate': 0.02,
        'book': [],
        'trades': [],
        'orders': [],
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketSignalsPanel(
              state: state,
              busy: false,
              priceHistory: const {},
              action: (callback) async {},
            ),
          ),
        ),
      ),
    );

    // Initial buy side: qty 10, price 12.50
    final qtyField = find.byType(TextField).at(0);
    final priceField = find.byType(TextField).at(1);

    expect(tester.widget<TextField>(qtyField).controller!.text, '10');
    expect(tester.widget<TextField>(priceField).controller!.text, '12.50');

    // Change buy qty to 42 and price to 15.00
    await tester.enterText(qtyField, '42');
    await tester.enterText(priceField, '15.00');
    await tester.pumpAndSettle();

    // Switch to SELL
    await tester.ensureVisible(find.text('SELL ENGY'));
    await tester.tap(find.text('SELL ENGY'));
    await tester.pumpAndSettle();

    // Change sell qty to 7 and price to 20.00
    await tester.enterText(qtyField, '7');
    await tester.enterText(priceField, '20.00');
    await tester.pumpAndSettle();

    // Switch back to BUY
    await tester.tap(find.text('BUY ENGY'));
    await tester.pumpAndSettle();

    // Verify BUY restored 42 and 15.00
    expect(tester.widget<TextField>(qtyField).controller!.text, '42');
    expect(tester.widget<TextField>(priceField).controller!.text, '15.00');

    // Switch back to SELL
    await tester.tap(find.text('SELL ENGY'));
    await tester.pumpAndSettle();

    // Verify SELL restored 7 and 20.00
    expect(tester.widget<TextField>(qtyField).controller!.text, '7');
    expect(tester.widget<TextField>(priceField).controller!.text, '20.00');
  });

  testWidgets(
      'MyMarketOrdersPanel renders complete lifecycle, reserved escrow, and allows cancellation',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 18420},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {
        'orders': [
          {
            'id': 'ORD-01',
            'side': 'buy',
            'product': 'components',
            'quantity': 10,
            'filled_quantity': 4,
            'limit_price': 120.0,
            'settlement_price': 118.0,
            'status': 'partial',
            'reserved_credits': 720.0,
            'fee': 14.16,
          },
          {
            'id': 'ORD-02',
            'side': 'buy',
            'product': 'material',
            'quantity': 50,
            'filled_quantity': 50,
            'limit_price': 30.0,
            'settlement_price': 28.5,
            'status': 'filled',
            'fee': 28.5,
          },
          {
            'id': 'ORD-03',
            'side': 'buy',
            'product': 'energy',
            'quantity': 100,
            'filled_quantity': 0,
            'limit_price': 0.85,
            'status': 'cancelled',
            'released_escrow': 85.0,
          },
        ],
      },
    });

    String? cancelledOrderId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyMarketOrdersPanel(
              state: state,
              busy: false,
              action: (cb) async {
                cancelledOrderId = 'ORD-01';
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('MY MARKET ORDERS / LIFECYCLE'), findsOneWidget);
    expect(find.textContaining('BUY COMPONENTS · 10 units @ 120.00 C'),
        findsOneWidget);
    expect(find.text('PARTIAL'), findsOneWidget);
    expect(find.textContaining('Filled: 4 / 10 (6 remaining)'), findsOneWidget);
    expect(find.textContaining('Settlement price: 118.00 C'), findsOneWidget);
    expect(find.textContaining('Reserved Credits in escrow: 720.00 C'),
        findsOneWidget);

    expect(find.text('FILLED'), findsOneWidget);
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(
        find.textContaining('Released escrow refund: 85.00 C'), findsOneWidget);

    // Cancel order button appears only for the open/partial order
    expect(find.text('CANCEL ORDER'), findsOneWidget);
    await tester.tap(find.text('CANCEL ORDER'));
    await tester.pumpAndSettle();

    expect(cancelledOrderId, 'ORD-01');
  });

  testWidgets(
      'SuppliesTodayPanel shows available stock and market decision context',
      (tester) async {
    const state = EarthState({
      'human': {},
      'resources': {'food': 0, 'energy': 20, 'material': 80, 'compute': 4},
      'market': {
        'products': {
          'food': {'price': 12.0},
          'energy': {'price': 8.0},
          'material': {'price': 20.0},
          'compute': {'price': 30.0},
        },
        'orders': [],
      },
      'contracts': [],
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SuppliesTodayPanel(state: state)),
    ));

    expect(find.text('SUPPLIES TODAY'), findsOneWidget);
    expect(find.textContaining('Needs attention'), findsOneWidget);
    expect(find.text('0 available'), findsOneWidget);
    expect(find.textContaining('sign a supply contract'), findsOneWidget);
  });
}
