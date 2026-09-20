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
        'authoritativeGameDay': 1842,
        'snapshotVersion': 'world-conditions-v1:1842',
        'rulesVersion': 'world-conditions-v1',
        'globalConditionCount': 1,
        'viewerApplicableConditionCount': 1,
        'worldState': 'ACTIVE_CONDITIONS',
        'activeConditions': [
          {
            'title': 'Grid stress',
            'severity': 'HIGH',
            'scope': {'type': 'EARTH'},
            'appliesToViewer': true,
            'exposureReason': 'EARTHWIDE',
            'effects': [
              {
                'type': 'DEMAND_MULTIPLIER',
                'target': 'ENERGY',
                'modifierBps': 500,
              },
            ],
            'source': {'type': 'SYSTEM'},
            'effectiveFromGameDay': 1840,
            'effectiveToGameDay': 1845,
          },
        ],
      },
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WorldConditionsPanel(state: state)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('GRID STRESS'), findsOneWidget);
    expect(find.text('DEMAND MULTIPLIER · ENERGY +5%'), findsOneWidget);
    expect(find.text('EARTH'), findsWidgets);
    expect(find.text('AFFECTING YOU (1 CONDITION)'), findsOneWidget);
  });
}
