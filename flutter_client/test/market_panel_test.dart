import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/market/market_panels.dart';

class _MarketQuoteTransport extends EarthApiTransport {
  @override
  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    if (path.contains('/book')) {
      return {
        'bids': [
          {
            'id': 'bid-1',
            'side': 'buy',
            'status': 'OPEN',
            'remainingQuantity': '3.000000',
            'limitPrice': '12.00'
          },
          {
            'id': 'bid-2',
            'side': 'buy',
            'status': 'OPEN',
            'remainingQuantity': '2.000000',
            'limitPrice': '12.00'
          },
        ],
        'asks': [
          {
            'id': 'ask-1',
            'side': 'sell',
            'status': 'OPEN',
            'remainingQuantity': '4.000000',
            'limitPrice': '13.00'
          },
        ],
      };
    }
    return const {
      'ok': true,
      'baseValueUnits': '12500',
      'feeUnits': '250',
      'totalEscrowUnits': '12750',
      'feeBps': 200,
    };
  }
}

class _MarketPositionTransport extends EarthApiTransport {
  @override
  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    if (path == '/api/market/positions') {
      return {
        'positions': [
          {
            'product': 'energy',
            'currentQuantity': '20.000000',
            'reservedQuantity': '0.000000',
            'availableQuantity': '20.000000'
          },
          {
            'product': 'food',
            'currentQuantity': '0.000000',
            'reservedQuantity': '0.000000',
            'availableQuantity': '0.000000'
          },
          {
            'product': 'material',
            'currentQuantity': '80.000000',
            'reservedQuantity': '0.000000',
            'availableQuantity': '80.000000'
          },
          {
            'product': 'components',
            'currentQuantity': '50.000000',
            'reservedQuantity': '0.000000',
            'availableQuantity': '50.000000'
          },
          {
            'product': 'compute',
            'currentQuantity': '4.000000',
            'reservedQuantity': '0.000000',
            'availableQuantity': '4.000000'
          },
        ],
      };
    }
    return _MarketQuoteTransport().request(path, method: method, body: body);
  }
}

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
              api: EarthApi(transport: _MarketQuoteTransport()),
              action: (callback) async {
                executedAction = 'called';
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('TRADE'), findsOneWidget);
    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('12.50 C'), findsOneWidget);
    expect(find.text('OPEN SELL HIGH'), findsOneWidget);
    expect(find.text('PLACE BUY ORDER'), findsOneWidget);
    expect(find.text('TREND'), findsOneWidget);
    expect(find.text('CANDLES'), findsOneWidget);
    expect(find.text('VIEW DEPTH'), findsOneWidget);

    await tester.tap(find.text('VIEW DEPTH'));
    await tester.pumpAndSettle();
    expect(find.text('BATCH-AUCTION DEPTH'), findsOneWidget);
    expect(find.text('5.000000'), findsOneWidget);
    expect(find.textContaining('not a continuous matching order book'),
        findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Decide whether to buy'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('PLACE BUY ORDER'));
    await tester.tap(find.text('PLACE BUY ORDER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM ORDER'));
    await tester.pumpAndSettle();
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
              api: EarthApi(transport: _MarketPositionTransport()),
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
    await tester.ensureVisible(find.text('SELL NRG'));
    await tester.tap(find.text('SELL NRG'));
    await tester.pumpAndSettle();

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    await tester.tap(find.text('50%'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(qtyField).controller!.text, '10');

    // Change sell qty to 7 and price to 20.00
    await tester.enterText(qtyField, '7');
    await tester.enterText(priceField, '20.00');
    await tester.pumpAndSettle();

    // Switch back to BUY
    await tester.tap(find.text('BUY NRG'));
    await tester.pumpAndSettle();

    // Verify BUY restored 42 and 15.00
    expect(tester.widget<TextField>(qtyField).controller!.text, '42');
    expect(tester.widget<TextField>(priceField).controller!.text, '15.00');

    // Switch back to SELL
    await tester.tap(find.text('SELL NRG'));
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
            'quantity': '10.000000',
            'filledQuantity': '4.000000',
            'remainingQuantity': '6.000000',
            'limitPrice': '120.00',
            'averageFillPrice': '118.00',
            'status': 'partial',
            'reservedEscrow': '720.00',
            'releasedEscrow': '0.00',
            'feesPaid': '14.16',
            'grossValue': '472.00',
          },
          {
            'id': 'ORD-02',
            'side': 'buy',
            'product': 'material',
            'quantity': '50.000000',
            'filledQuantity': '50.000000',
            'remainingQuantity': '0.000000',
            'limitPrice': '30.00',
            'averageFillPrice': '28.50',
            'status': 'filled',
            'reservedEscrow': '0.00',
            'releasedEscrow': '0.00',
            'feesPaid': '28.50',
            'grossValue': '1425.00',
          },
          {
            'id': 'ORD-03',
            'side': 'buy',
            'product': 'energy',
            'quantity': '100.000000',
            'filledQuantity': '0.000000',
            'remainingQuantity': '100.000000',
            'limitPrice': '0.85',
            'status': 'cancelled',
            'reservedEscrow': '0.00',
            'releasedEscrow': '85.00',
            'feesPaid': '0.00',
            'grossValue': '0.00',
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

    expect(find.text('MY ORDERS'), findsOneWidget);
    expect(find.textContaining('BUY COMPONENTS · 10.000000 units @ 120.00 C'),
        findsOneWidget);
    expect(find.text('PARTIAL'), findsOneWidget);
    expect(
        find.textContaining(
            'Filled: 4.000000 / 10.000000 (6.000000 remaining)'),
        findsOneWidget);
    expect(
        find.textContaining('Weighted fill price: 118.00 C'), findsOneWidget);
    expect(find.textContaining('Reserved escrow: 720.00'), findsOneWidget);

    expect(find.text('FILLED'), findsOneWidget);
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.textContaining('Released escrow: 85.00'), findsOneWidget);

    // Cancel order button appears only for the open/partial order
    expect(find.text('CANCEL ORDER'), findsOneWidget);
    await tester.tap(find.text('CANCEL ORDER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL ORDER').last);
    await tester.pumpAndSettle();

    expect(cancelledOrderId, 'ORD-01');
  });

  testWidgets(
      'SuppliesTodayPanel shows available stock and market decision context',
      (tester) async {
    const state = EarthState({
      'human': {},
      'resources': {
        'energy': 20,
        'food': 0,
        'material': 80,
        'components': 50,
        'compute': 4
      },
      'market': {
        'products': {
          'energy': {'price': 8.0},
          'food': {'price': 12.0},
          'material': {'price': 20.0},
          'components': {'price': 40.0},
          'compute': {'price': 30.0},
        },
        'orders': [],
      },
      'contracts': [],
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SuppliesTodayPanel(
              state: state,
              api: EarthApi(transport: _MarketPositionTransport()),
              action: (fn) async {})),
    ));
    await tester.pumpAndSettle();

    expect(find.text('STOCK & SHORTAGES'), findsOneWidget);
    expect(
        find.textContaining('No immediate commodity shortage'), findsOneWidget);
    expect(find.text('0.000000 available · 0.000000 reserved'), findsOneWidget);
    expect(find.textContaining('Buildings and businesses drive demand'),
        findsOneWidget);
  });
}
