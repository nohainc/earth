import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('city page renders capacity, services, and resident rank', (tester) async {
    const state = EarthState({
      'human': {'id': 'H-01'},
      'membership': {'city_id': 'CITY-01'},
      'institutions': {
        'city': {
          'id': 'CITY-01', 'name': 'New Kyoto', 'residents': 80,
          'housing_capacity': 120, 'energy_capacity': 100,
        },
      },
      'world': {
        'serviceRatios': {'housing': 0.75, 'energy': 0.90, 'connectivity': 0.82, 'health': 0.95},
      },
      'cityMembers': [
        {'id': 'H-99'},
        {'id': 'H-01'},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InstitutionsCapacityPanel(
      state: state,
      busy: false,
      action: (_) async {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('NEW KYOTO'), findsOneWidget);
    expect(find.textContaining('80'), findsWidgets);
    expect(find.textContaining('120'), findsWidgets);
    expect(find.textContaining('90%'), findsWidgets);
    expect(find.text('CITY STANDING'), findsOneWidget);
    expect(find.text('You rank #2 among active residents by civic standing.'), findsOneWidget);
  });

  testWidgets('city page safely handles an independent citizen', (tester) async {
    const state = EarthState({'institutions': {'city': {'name': 'New Kyoto'}}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InstitutionsCapacityPanel(
      state: state,
      busy: true,
      action: (_) async {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('NEW KYOTO'), findsOneWidget);
    expect(find.text('NON-RESIDENT'), findsOneWidget);
  });
}
