import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/business_panel.dart';

void main() {
  testWidgets('BusinessPanel renders financial statements, profit, and distributes dividends',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {
        'id': 'B-1048',
        'name': 'Kline Works',
        'policy': 'reliability',
        'status': 'active',
        'condition': 96,
      },
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool dividendTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessPanel(
              state: state,
              busy: false,
              businessOwnership: const {
                'controllingHumanId': 'H-0044',
                'totalIssuedShares': 1000,
                'holders': [
                  {'display_name': 'Amara Kline', 'percentage': 75, 'shares': 750},
                ],
              },
              businessFinancials: const {
                'business': {
                  'revenue': 1240.0,
                  'operating_costs': 820.0,
                  'profit': 420.0,
                  'taxed_revenue': 1240.0,
                  'last_game_day': 184,
                },
              },
              businessProfile: const {},
              action: (cb) async {
                dividendTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('BUSINESS / KLINE WORKS'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('FINANCIAL STATEMENT (PERIOD ACTUALS)'), findsOneWidget);
    expect(find.text('Operating Revenue: 1240.00 C'), findsOneWidget);
    expect(find.text('Operating Costs: 820.00 C'), findsOneWidget);
    expect(find.text('+420.00 C'), findsOneWidget);
    expect(find.textContaining('Amara Kline: 75% (750 shares)'), findsOneWidget);

    // Distribute dividends
    expect(find.text('DISTRIBUTE DIVIDENDS'), findsOneWidget);
    await tester.tap(find.text('DISTRIBUTE DIVIDENDS'));
    await tester.pumpAndSettle();

    expect(find.text('Distribute dividends'), findsOneWidget);
    expect(find.text('DISTRIBUTE'), findsOneWidget);

    await tester.tap(find.text('DISTRIBUTE'));
    await tester.pumpAndSettle();

    expect(dividendTriggered, isTrue);
  });

  testWidgets('BusinessPanel displays distress warnings and enables liquidation',
      (tester) async {
    const distressedState = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {
        'id': 'B-1048',
        'name': 'Kline Works',
        'policy': 'reliability',
        'status': 'distressed',
        'condition': 40,
      },
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool liquidationTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessPanel(
              state: distressedState,
              busy: false,
              businessOwnership: const {},
              businessFinancials: const {
                'business': {
                  'revenue': 200.0,
                  'operating_costs': 600.0,
                  'profit': -400.0,
                  'taxed_revenue': 200.0,
                  'last_game_day': 184,
                },
              },
              businessProfile: const {},
              action: (cb) async {
                liquidationTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('DISTRESSED'), findsOneWidget);
    expect(find.text('-400.00 C'), findsOneWidget);
    expect(find.text('WARNING: FINANCIAL DISTRESS'), findsOneWidget);
    expect(find.text('LIQUIDATE BUSINESS'), findsOneWidget);

    await tester.ensureVisible(find.text('LIQUIDATE BUSINESS'));
    await tester.tap(find.text('LIQUIDATE BUSINESS'));
    await tester.pumpAndSettle();

    expect(find.text('Liquidate business?'), findsOneWidget);
    expect(find.text('LIQUIDATE'), findsOneWidget);

    await tester.tap(find.text('LIQUIDATE'));
    await tester.pumpAndSettle();

    expect(liquidationTriggered, isTrue);
  });
}
