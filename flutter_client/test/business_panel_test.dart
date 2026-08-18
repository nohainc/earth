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
                  {'human_id': 'H-0044', 'display_name': 'Amara Kline', 'percentage': 75, 'shares': 750},
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

    expect(find.text('ENTERPRISE OPERATIONS / KLINE WORKS'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('OPERATING REVENUE'), findsOneWidget);
    expect(find.text('1240 C'), findsWidgets);
    expect(find.text('820 C'), findsOneWidget);
    expect(find.text('+420 C'), findsOneWidget);
    expect(find.textContaining('Amara Kline (H-0044)'), findsOneWidget);
    expect(find.text('CONTROLLER'), findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Executive Entity Identity'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Distribute dividends
    expect(find.text('DISTRIBUTE DIVIDENDS'), findsOneWidget);
    await tester.ensureVisible(find.text('DISTRIBUTE DIVIDENDS'));
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
    expect(find.text('-400 C'), findsWidgets);
    expect(find.text('WARNING: FINANCIAL DISTRESS'), findsOneWidget);
    expect(find.text('LIQUIDATE ENTERPRISE'), findsWidgets);

    await tester.ensureVisible(find.text('LIQUIDATE ENTERPRISE'));
    await tester.tap(find.text('LIQUIDATE ENTERPRISE'));
    await tester.pumpAndSettle();

    expect(find.text('Liquidate business?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'LIQUIDATE'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'LIQUIDATE'));
    await tester.pumpAndSettle();

    expect(liquidationTriggered, isTrue);
  });

  testWidgets('BusinessPanel opens shareholder resolution and AI assistant config dialogs',
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessPanel(
              state: state,
              busy: false,
              businessOwnership: const {},
              businessFinancials: const {},
              businessProfile: const {},
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    // Shareholder Resolution
    expect(find.text('SHAREHOLDER RESOLUTION (>66.7%)'), findsOneWidget);
    await tester.ensureVisible(find.text('SHAREHOLDER RESOLUTION (>66.7%)'));
    await tester.tap(find.text('SHAREHOLDER RESOLUTION (>66.7%)'));
    await tester.pumpAndSettle();

    expect(find.text('Propose shareholder resolution'), findsOneWidget);
    expect(find.textContaining('>66.7% Supermajority Approval'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    // AI Operational Assistant
    expect(find.text('AI OPERATIONAL ASSISTANT'), findsOneWidget);
    await tester.ensureVisible(find.text('AI OPERATIONAL ASSISTANT'));
    await tester.tap(find.text('AI OPERATIONAL ASSISTANT'));
    await tester.pumpAndSettle();

    expect(find.text('AI Operational Assistant'), findsOneWidget);
    expect(find.text('Automated Machine Maintenance'), findsOneWidget);
    expect(find.text('SAVE AI CONFIG'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });
}
