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

    bool actionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalFinancePanel(
            state: state,
            busy: false,
            personalFinanceData: financeData,
            action: (cb) async {
              actionTriggered = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('PERSONAL FINANCE & TAXATION'), findsOneWidget);
    expect(find.text('18420 C'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.textContaining('Income stream: 760 C / day'), findsOneWidget);
    expect(find.textContaining('Assessed tax obligations: 48 C'), findsOneWidget);
    expect(find.textContaining('Protected minimum reserve: 100 C'), findsOneWidget);
    expect(find.text('SETTLE TAXES'), findsOneWidget);
    expect(find.text('INSOLVENCY RESTRUCTURING'), findsOneWidget);

    // Open settle taxes dialog
    await tester.tap(find.text('SETTLE TAXES'));
    await tester.pumpAndSettle();

    expect(find.text('Settle Tax Obligations'), findsOneWidget);
    expect(find.text('CONFIRM SETTLEMENT'), findsOneWidget);

    await tester.tap(find.text('CONFIRM SETTLEMENT'));
    await tester.pumpAndSettle();

    expect(actionTriggered, isTrue);
  });
}
