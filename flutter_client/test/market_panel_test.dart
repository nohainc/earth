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
          body: MarketSignalsPanel(
            state: state,
            busy: false,
            action: (callback) async {
              executedAction = 'called';
            },
          ),
        ),
      ),
    );

    expect(find.text('CENTRAL MARKET / LIVE SIGNALS'), findsOneWidget);
    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('12.5 C'), findsOneWidget);
    expect(find.text('S 100  ·  D 80'), findsOneWidget);
    expect(find.text('BUY 1'), findsOneWidget);
    expect(find.text('SELL 1'), findsOneWidget);
    expect(find.text('SETTLE'), findsOneWidget);

    await tester.tap(find.text('BUY 1'));
    expect(executedAction, 'called');
  });
}
