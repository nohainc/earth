import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';

void main() {
  testWidgets('PersonalFinancePanel renders credit balance, income, expenses, and tax status',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 18420, 'standing': 742, 'legacy': 31},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
    });

    final financeData = {
      'account': {'balance': 18420, 'currency': 'CREDIT'},
      'state': {
        'income': 760,
        'expenses': 240,
        'tax_obligations': 48,
        'liquidity_status': 'healthy',
        'insolvency_status': 'solvent',
      },
      'protectedMinimum': {'credits': 100, 'basicServiceRobot': true},
    };

    bool taxActionTriggered = false;
    bool insolvencyActionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalFinancePanel(
              state: state,
              busy: false,
              personalFinanceData: financeData,
              action: (cb) async {
                taxActionTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('PERSONAL FINANCE & TAXATION'), findsOneWidget);
    expect(find.text('18420'), findsOneWidget);
    expect(find.text('C'), findsWidgets);
    expect(find.text('HEALTHY LIQUIDITY'), findsOneWidget);
    expect(find.textContaining('STATUTORY PROTECTION SHIELD'), findsOneWidget);
    expect(find.text('DAILY INFLOW'), findsOneWidget);
    expect(find.text('BASELINE OUTFLOW'), findsOneWidget);
    expect(find.text('NET DAILY ACCUMULATION'), findsOneWidget);
    expect(find.text('ASSESSED TAX DUES'), findsOneWidget);
    expect(find.text('+472 C'), findsOneWidget);
    expect(find.text('SETTLE TAXES'), findsOneWidget);
    expect(find.text('INSOLVENCY RESTRUCTURING'), findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Personal Wealth & Solvency Cockpit'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Open settle taxes dialog
    await tester.ensureVisible(find.text('SETTLE TAXES'));
    await tester.tap(find.text('SETTLE TAXES'));
    await tester.pumpAndSettle();

    expect(find.text('Settle Tax Obligations'), findsOneWidget);
    expect(find.text('CONFIRM SETTLEMENT'), findsOneWidget);

    await tester.tap(find.text('CONFIRM SETTLEMENT'));
    await tester.pumpAndSettle();

    expect(taxActionTriggered, isTrue);

    // Test insolvency restructuring dialog
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalFinancePanel(
              state: state,
              busy: false,
              personalFinanceData: financeData,
              action: (cb) async {
                insolvencyActionTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('INSOLVENCY RESTRUCTURING'));
    await tester.tap(find.text('INSOLVENCY RESTRUCTURING'));
    await tester.pumpAndSettle();

    expect(find.text('Declare Personal Insolvency'), findsOneWidget);
    expect(find.text('EXECUTE RESTRUCTURING'), findsOneWidget);

    await tester.tap(find.text('EXECUTE RESTRUCTURING'));
    await tester.pumpAndSettle();

    expect(insolvencyActionTriggered, isTrue);
  });
}
