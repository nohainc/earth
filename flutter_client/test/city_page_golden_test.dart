import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  const state = EarthState({
    'human': {'id': 'H-01'},
    'membership': {'city_id': 'CITY-01'},
    'institutions': {'city': {'id': 'CITY-01', 'name': 'New Kyoto', 'residents': 80, 'housing_capacity': 120, 'energy_capacity': 100}},
    'world': {'serviceRatios': {'housing': .75, 'energy': .90, 'connectivity': .82, 'health': .95}},
    'cityMembers': [{'id': 'H-01', 'standing': 840}],
  });
  for (final viewport in [const Size(375, 812), const Size(768, 1024), const Size(1440, 900)]) {
    testWidgets('Tier 2 city golden ${viewport.width.toInt()}px', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        theme: createEarthTheme(),
        home: Scaffold(body: InstitutionsCapacityPanel(state: state, busy: false, action: (_) async {})),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/city_${viewport.width.toInt()}.png'));
    });
  }
}
