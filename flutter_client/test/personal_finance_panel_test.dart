import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';
import 'package:earth_client/shared/design_system/design_system.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  testWidgets('Personal Finance shows real life maintenance and automatic tax', (tester) async {
    const state = EarthState({
      'human': {'id': 'H-0044', 'credits': 18420},
      'buildings': [
        {
          'owner_id': 'H-0044',
          'ownership_class': 'private',
          'status': 'active',
          'resource_output_type': 'energy',
          'resource_output_amount': 15,
          'daily_operating_credits': 0,
          'operating_policy': 'balanced',
        }
      ],
    });
    final data = {
      'account': {'balance': 18420, 'currency': 'CREDIT'},
      'protectedMinimum': {'credits': 100},
      'lifeMaintenance': {
        'unpaidTotal': 0,
        'lastSettlement': {
          'food_used': 1,
          'energy_used': 1,
          'compute_used': 0.25,
          'credits_for_resources': 0,
        },
      },
      'dailyProfile': {
        'status': 'clean',
        'credits_delta': 120.0,
        'energy_delta': 15.0,
        'food_delta': -1.0,
      },
      'basicLevy': {
        'rate': 0.02,
        'source': 'Earth',
        'estimatedDailyLevy': 2,
      },
      'taxes': {
        'rules': [
          {'category': 'basic_income', 'rate': 0.02},
        ],
      },
      'assetIncome': {
        'businessProfit': 120,
        'civicDividends': 6,
        'privateBuildings': [
          {
            'resource_output_type': 'energy',
            'resource_output_amount': 15,
            'daily_operating_credits': 0,
            'operating_policy': 'balanced'
          },
        ],
      },
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PersonalFinancePanel(
            state: state,
            busy: false,
            personalFinanceData: data,
            action: (_) async {},
          ),
        ),
      ),
    ));

    expect(find.text('PERSONAL FINANCE'), findsOneWidget);
    expect(find.text('Available Credits'), findsNothing);
    expect(find.text('GROSS CREDIT INCOME'), findsOneWidget);
    expect(find.text('Private buildings'), findsOneWidget);
    expect(find.text('Investment dividend'), findsOneWidget);
    expect(find.text('FROM PRIVATE BUILDINGS'), findsNothing);
    expect(find.text('NET CREDIT INCOME'), findsOneWidget);
    expect(find.text('Basic income tax'), findsOneWidget);
    expect(find.text('DAILY INCOME'), findsOneWidget);
    expect(find.text('YOUR DAILY RESULT'), findsNothing);
    expect(find.text('ON TRACK'), findsOneWidget);
    expect(find.textContaining('Protected reserve: 100 C'), findsOneWidget);
  });

  testWidgets('Personal Finance handles empty/unavailable living-cost breakdown gracefully on mobile', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const state = EarthState({
      'human': {'id': 'H-0044', 'credits': 500},
      'buildings': [],
    });

    // Empty personal finance data
    final emptyData = <String, dynamic>{};

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PersonalFinancePanel(
            state: state,
            busy: false,
            personalFinanceData: emptyData,
            action: (_) async {},
          ),
        ),
      ),
    ));

    expect(find.text('PERSONAL FINANCE'), findsOneWidget);
    expect(find.text('DAILY INCOME'), findsOneWidget);
    expect(find.text('GROSS CREDIT INCOME'), findsOneWidget);
    expect(find.text('NET CREDIT INCOME'), findsOneWidget);
    expect(find.text('YOUR DAILY RESULT'), findsNothing);
    expect(find.text('ON TRACK'), findsOneWidget);
    expect(find.text('GLOBAL CORPORATE BANK'), findsOneWidget);
    expect(find.text('No active deposits. Deposit credits to earn potential interest over a selected term.'), findsOneWidget);
    expect(find.text('MAKE DEPOSIT'), findsOneWidget);
    expect(find.text('30 d'), findsOneWidget);
  });

  testWidgets('Global Corporate Bank card renders deposits, calculates maturity, and supports actions', (tester) async {
    const state = EarthState({
      'clock': {'day': 15, 'minute': 120},
      'human': {'id': 'H-0044', 'credits': 1200},
      'buildings': [],
    });

    final bankData = {
      'bank': {
        'deposits': [
          {
            'id': 'DEP-1',
            'principal': 500,
            'accrued_interest': 5.25,
            'start_game_day': 10,
            'start_game_minute': 90,
            'maturity_game_day': 14, // Matured
            'maturity_game_minute': 90,
            'status': 'active',
          },
          {
            'id': 'DEP-2',
            'principal': 300,
            'accrued_interest': 1.50,
            'start_game_day': 12,
            'start_game_minute': 90,
            'maturity_game_day': 42, // Active
            'maturity_game_minute': 90,
            'status': 'active',
          },
        ],
      },
    };

    var actionInvoked = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PersonalFinancePanel(
            state: state,
            busy: false,
            personalFinanceData: bankData,
            action: (fn) async {
              actionInvoked = true;
            },
          ),
        ),
      ),
    ));

    expect(find.text('GLOBAL CORPORATE BANK'), findsOneWidget);
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('DEPOSIT FUNDS'), findsOneWidget);
    expect(find.text('MY DEPOSITS'), findsOneWidget);
    expect(find.text('Liquid credits'), findsOneWidget);
    expect(find.text('Deposited principal'), findsOneWidget);
    expect(find.text('Accrued interest'), findsWidgets);
    expect(find.text('Active deposits'), findsOneWidget);

    // Verify deposits rendered
    expect(find.text('500 C'), findsOneWidget);
    expect(find.text('300 C'), findsOneWidget);
    expect(find.text('Matured'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('WITHDRAW'), findsNWidgets(2));
    expect(find.text(formatGameDateTime(10, 90)), findsOneWidget);
    expect(find.text(formatGameDateTime(14, 90)), findsOneWidget);

    // Test deposit review dialog
    final makeDepositBtn = find.text('MAKE DEPOSIT');
    expect(makeDepositBtn, findsOneWidget);
    await tester.ensureVisible(makeDepositBtn);
    await tester.pumpAndSettle();
    await tester.tap(makeDepositBtn);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Bank Deposit'), findsOneWidget);
    expect(find.text('Review your deposit terms carefully. Deposited credits cannot be withdrawn before maturity.'), findsOneWidget);
    expect(find.text('Current game time'), findsOneWidget);
    expect(find.text(formatGameDateTime(15, 120)), findsOneWidget);
    expect(find.text('Maturity'), findsOneWidget);
    expect(find.text(formatGameDateTime(45, 120)), findsOneWidget);
    expect(find.text('CONFIRM DEPOSIT'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Bank Deposit'), findsNothing);

    // Test withdraw button for matured deposit
    final withdrawButtons = find.widgetWithText(EarthButton, 'WITHDRAW');
    // First withdraw button is enabled (matured), second is disabled (not reached maturity)
    final firstWithdraw = tester.widget<EarthButton>(withdrawButtons.first);
    final secondWithdraw = tester.widget<EarthButton>(withdrawButtons.at(1));
    expect(firstWithdraw.onPressed, isNotNull);
    expect(secondWithdraw.onPressed, isNull);

    // Tap first withdraw to open confirmation dialog
    await tester.ensureVisible(withdrawButtons.first);
    await tester.pumpAndSettle();
    await tester.tap(withdrawButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Withdraw Matured Deposit'), findsOneWidget);
    expect(find.text('Total Liquid Credit Payout'), findsOneWidget);
    expect(find.text('505.25 C'), findsOneWidget);

    // Confirm withdrawal
    await tester.tap(find.text('WITHDRAW FUNDS'));
    await tester.pumpAndSettle();
    expect(actionInvoked, isTrue);
  });

  testWidgets('withdrawn deposits hide the withdrawal action and progress bar', (tester) async {
    const state = EarthState({
      'clock': {'day': 20, 'minute': 0},
      'human': {'id': 'H-0044', 'credits': 1200},
      'buildings': [],
    });
    final data = {
      'bank': {
        'deposits': [
          {
            'id': 'DEP-WITHDRAWN',
            'principal': 500,
            'accrued_interest': 5,
            'start_game_day': 10,
            'start_game_minute': 0,
            'maturity_game_day': 14,
            'maturity_game_minute': 0,
            'status': 'withdrawn',
          },
        ],
      },
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PersonalFinancePanel(
            state: state,
            busy: false,
            personalFinanceData: data,
            action: (_) async {},
          ),
        ),
      ),
    ));

    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.widgetWithText(EarthButton, 'WITHDRAW'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
