import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/world/world_conditions_panel.dart';

void main() {
  testWidgets('World Conditions distinguishes unavailable from stable',
      (tester) async {
    const unavailable = EarthState({
      'clock': {'day': 10}
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WorldConditionsPanel(state: unavailable)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('CONDITIONS UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('No baseline or normal-state claims'),
        findsOneWidget);
    expect(find.textContaining('1.00'), findsNothing);
  });

  testWidgets(
      'World Conditions renders canonical stable snapshot and percentages',
      (tester) async {
    const state = EarthState({
      'worldConditions': {
        'status': 'AVAILABLE',
        'snapshotGameDay': 1842,
        'rulesVersion': 'world-conditions-v1',
        'worldState': 'ACTIVE_CONDITIONS',
        'activeConditions': [
          {
            'title': 'Grid stress',
            'severity': 'HIGH',
            'impact': 'ADVERSE',
            'scope': {'type': 'WORLD'},
            'effect': {'target': 'ENERGY', 'modifierBps': 500},
            'source': {'type': 'SYSTEM'},
            'effectiveFromGameDay': 1840,
            'effectiveToGameDay': 1845,
          },
        ],
        'playerExposure': {
          'territoryName': 'Bratislava',
          'activeConditionCount': 1
        },
      },
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WorldConditionsPanel(state: state)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('GRID STRESS'), findsOneWidget);
    expect(find.text('ENERGY +5%'), findsOneWidget);
    expect(find.text('Bratislava'), findsOneWidget);
    expect(find.text('ACTIVE CONDITIONS'), findsWidgets);
  });
}
