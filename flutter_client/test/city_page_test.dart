import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('city page renders capacity, services, municipal budget, and resident rank', (tester) async {
    const state = EarthState({
      'human': {'id': 'H-01', 'standing': 840},
      'membership': {'city_id': 'CITY-01'},
      'institutions': {
        'city': {
          'id': 'CITY-01',
          'name': 'New Kyoto',
          'residents': 80,
          'housing_capacity': 120,
          'energy_capacity': 100,
          'treasury': 250000.0,
        },
      },
      'world': {
        'serviceRatios': {'housing': 0.75, 'energy': 0.90, 'connectivity': 0.82, 'health': 0.95},
      },
      'cityMembers': [
        {'id': 'H-99', 'standing': 900},
        {'id': 'H-01', 'standing': 840},
      ],
    });

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstitutionsCapacityPanel(
        state: state,
        busy: false,
        action: (_) async {},
      ),
    ))));
    await tester.pumpAndSettle();

    // 1. Municipal Header & Services
    expect(find.text('NEW KYOTO'), findsWidgets);
    expect(find.text('HOUSING'), findsOneWidget);
    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('CONNECTIVITY'), findsOneWidget);
    expect(find.text('HEALTHCARE'), findsOneWidget);

    // 2. City Capacity Attributes
    expect(find.text('80'), findsWidgets);
    expect(find.text('120'), findsWidgets);
    expect(find.text('CITY STANDING'), findsWidgets);

    // 3. City Budget & Treasury
    expect(find.text('CITY BUDGET'), findsWidgets);
    expect(find.textContaining('250000 C'), findsWidgets);
  });

  testWidgets('city page safely handles an independent citizen', (tester) async {
    const state = EarthState({
      'institutions': {
        'city': {'name': 'New Kyoto', 'treasury': 0.0},
      },
      'world': {'serviceRatios': {}},
    });

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstitutionsCapacityPanel(
        state: state,
        busy: false,
        action: (_) async {},
      ),
    ))));
    await tester.pumpAndSettle();

    expect(find.text('NEW KYOTO'), findsWidgets);
    expect(find.text('CITY BUDGET'), findsWidgets);
  });

  testWidgets('city page adapts layout and wraps attributes on mobile viewports (375px)', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const state = EarthState({
      'human': {'id': 'H-01', 'standing': 840},
      'membership': {'city_id': 'CITY-01'},
      'institutions': {
        'city': {
          'id': 'CITY-01',
          'name': 'New Kyoto',
          'residents': 80,
          'housing_capacity': 120,
          'energy_capacity': 100,
          'treasury': 250000.0,
        },
      },
      'world': {
        'serviceRatios': {'housing': 0.75, 'energy': 0.90, 'connectivity': 0.82, 'health': 0.95},
      },
      'cityMembers': [],
    });

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InstitutionsCapacityPanel(
        state: state,
        busy: false,
        action: (_) async {},
      ),
    ))));
    await tester.pumpAndSettle();

    expect(find.text('NEW KYOTO'), findsWidgets);
    expect(find.text('CITY BUDGET'), findsWidgets);
    expect(find.textContaining('250000 C'), findsWidgets);
  });
}
