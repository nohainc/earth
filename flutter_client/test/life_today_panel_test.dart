import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets(
      'LifeTodayPanel presents personal status without invented metrics',
      (tester) async {
    const state = EarthState({
      'human': {
        'age_years': 34,
        'health': 82,
        'energy': 64,
        'legacy': 120,
        'life_status': 'active',
      },
      'business': {'name': 'Northstar Robotics'},
      'institutions': {
        'city': {'name': 'Aurelia'},
      },
      'membership': {'name': 'Civic Assembly'},
      'life': {},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LifeTodayPanel(state: state)),
    ));

    expect(find.text('MY LIFE TODAY'), findsOneWidget);
    expect(find.text('AURELIA'), findsOneWidget);
    expect(find.textContaining('Age 34'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsNothing);
  });
}
