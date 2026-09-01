import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';

void main() {
  const state = EarthState({
    'human': {'id': 'H-0044', 'credits': 50000},
    'buildings': [],
    'investmentShares': [],
    'finance': {},
  });

  final personalFinanceData = {
    'protectedMinimum': {'credits': 100},
    'lifeMaintenance': {
      'unpaidTotal': 0.0,
      'lastSettlement': {
        'food_used': 1.0,
        'energy_used': 1.5,
        'compute_used': 0.5,
      },
    },
    'dailyProfile': {
      'status': 'clean',
      'credits_delta': 450.0,
      'food_delta': -1.0,
      'energy_delta': -1.5,
      'compute_delta': -0.5,
    },
    'taxes': {
      'rules': [
        {'category': 'basic_income', 'rate': 0.05},
      ],
    },
  };

  for (final viewport in [const Size(375, 812), const Size(768, 1024), const Size(1440, 900)]) {
    testWidgets('Personal Finance page golden ${viewport.width.toInt()}px', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        theme: createEarthTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalFinancePanel(
              state: state,
              busy: false,
              personalFinanceData: personalFinanceData,
              action: (_) async {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/qa/finance_${viewport.width.toInt()}.png'),
      );
    });
  }
}
