import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';
import 'package:earth_client/features/market/market_panels.dart';

void main() {
  testWidgets('MacroLiquidityPanel renders UC Monetary Stability Board metrics',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 5, 'minute': 300},
      'human': {'credits': 12000, 'standing': 50, 'legacy': 100},
      'world': {'health': 100},
      'resources': {'food': 50, 'material': 100},
      'business': {},
      'technology': {'research': {}},
      'institutions': {'city': {}, 'corporation': {}},
      'life': {},
      'governance': {},
      'finance': {
        'liquidity': {
          'moneySupply': 155000,
          'target': 150000,
          'status': 'nominal',
          'cpi': 103.5,
          'gini': 0.31,
          'velocity': 2.05,
        }
      },
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MacroLiquidityPanel(state: state),
        ),
      ),
    );

    expect(find.text('UC MONETARY STABILITY BOARD / MACRO BASE'), findsOneWidget);
    expect(find.text('UC PLANETARY MONETARY & STABILITY METRICS'), findsOneWidget);
    expect(find.text('CIRCULATING M0'), findsOneWidget);
    expect(find.text('155000 C'), findsOneWidget);
    expect(find.text('30-DAY CPI'), findsOneWidget);
    expect(find.text('103.5'), findsOneWidget);
    expect(find.text('+3.5% vs Base 100.0'), findsOneWidget);
    expect(find.text('PLANETARY GINI (G)'), findsOneWidget);
    expect(find.text('0.31'), findsOneWidget);
    expect(find.text('MONEY VELOCITY (V)'), findsOneWidget);
    expect(find.text('2.05x'), findsOneWidget);
  });

  testWidgets('MarketSignalsPanel renders Periodic Batch Auction clearing epoch banner',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const state = EarthState({
      'clock': {'day': 2, 'minute': 120},
      'human': {'credits': 8000, 'standing': 20, 'legacy': 10},
      'world': {'health': 100},
      'resources': {'material': 40, 'food': 25, 'energy': 50, 'compute': 10},
      'business': {},
      'technology': {'research': {}},
      'institutions': {'city': {}, 'corporation': {}},
      'life': {},
      'governance': {},
      'market': {
        'products': {
          'material': {'price': 52.0, 'supply': 500, 'demand': 650},
          'food': {'price': 28.0, 'supply': 300, 'demand': 280},
        },
        'feeRate': 0.01,
      },
      'finance': {},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketSignalsPanel(
              state: state,
              busy: false,
              action: (callback) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('PERIODIC BATCH AUCTION'), findsOneWidget);
    expect(find.text('EPOCH #12'), findsOneWidget);
    expect(find.textContaining('Next batch clearing in 02:00'), findsOneWidget);
    expect(find.text('POOLING ORDERS'), findsOneWidget);
  });
}
