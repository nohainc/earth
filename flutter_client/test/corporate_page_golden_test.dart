import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  const corpState = EarthState({
    'human': {'id': 'H-0044'},
    'membership': {
      'corporation_id': 'CORP-001',
      'city_id': 'CITY-0084',
    },
    'institutions': {
      'corporation': {
        'id': 'CORP-001',
        'name': 'Solaris Conglomerate',
        'members': 42,
        'treasury': 8500000.0,
        'capital_city_name': 'New Carthage',
        'rules': {
          'incomeTaxBps': 250,
          'salesTaxBps': 150,
          'corporateTaxBps': 300,
        },
      },
    },
    'roles': [],
    'technology': {'corporationSharedPatents': []},
  });

  for (final viewport in [const Size(375, 812), const Size(768, 1024), const Size(1440, 900)]) {
    testWidgets('Corporate Overview golden ${viewport.width.toInt()}px', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        theme: createEarthTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CorporationOverviewPanel(
              state: corpState,
              busy: false,
              action: (_) async {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/qa/corporation_${viewport.width.toInt()}.png'),
      );
    });
  }
}
