import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';

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
    expect(find.text('DAILY INCOME'), findsOneWidget);
    expect(find.text('Private buildings'), findsOneWidget);
    expect(find.text('Investment dividend'), findsOneWidget);
    expect(find.text('FROM PRIVATE BUILDINGS'), findsOneWidget);
    expect(find.text('LIFE MAINTENANCE'), findsOneWidget);
    expect(find.text('ESTIMATED TAX ON THIS INCOME'), findsOneWidget);
    expect(find.text('Basic income tax'), findsOneWidget);
    expect(find.text('YOUR DAILY RESULT'), findsOneWidget);
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
    expect(find.text('LIFE MAINTENANCE'), findsOneWidget);
    expect(find.text('YOUR DAILY RESULT'), findsOneWidget);
    expect(find.text('ON TRACK'), findsOneWidget);
    expect(find.textContaining('Protected reserve: 100 C'), findsOneWidget);
  });
}
