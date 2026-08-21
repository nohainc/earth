import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('CorporationOverviewPanel keeps independent status minimal',
      (tester) async {
    const state = EarthState({
      'institutions': {},
      'membership': {},
      'rankings': {
        'corporations': [
          {'name': 'Hidden Corporation', 'member_count': 99},
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CorporationOverviewPanel(state: state)),
    ));

    expect(find.text('MEMBERSHIP'), findsOneWidget);
    expect(find.text('You are currently independent.'), findsOneWidget);
    expect(find.textContaining('Join a corporation to access'), findsOneWidget);
    expect(find.text('Hidden Corporation'), findsNothing);
    expect(find.text('CORPORATION DECISIONS'), findsNothing);
    expect(find.text('TREASURY'), findsNothing);
  });

  testWidgets(
      'CorporationOverviewPanel presents affiliation and corporation direction',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-0044'},
      'institutions': {
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_count': 38,
          'treasury': 12500,
        },
      },
      'membership': {'corporation_id': 'CORP-001', 'city_id': 'CITY-0084'},
      'rankings': {
        'corporations': [
          {'id': 'CORP-001', 'name': 'Carthage Dynamics', 'member_count': 38},
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CorporationOverviewPanel(state: state)),
    ));

    expect(find.text('CORPORATION'), findsOneWidget);
    expect(find.text('You belong to Carthage Dynamics.'), findsNothing);
    expect(find.text('LEAVE CORPORATION'), findsOneWidget);
    expect(find.text('CORPORATION DECISIONS'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('12500 C'), findsOneWidget);
  });

  testWidgets(
      'InstitutionsCapacityPanel renders city residency, pressure ratios, and proposes budget',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {
        'health': 100,
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.60,
          'connectivity': 0.95,
          'health': 0.90,
        },
      },
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {
        'city': {
          'id': 'CITY-0084',
          'name': 'New Carthage',
          'residents': 142,
          'housing_capacity': 200,
          'energy_capacity': 300,
        },
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_count': 38,
          'constitution_version': 2,
        },
      },
      'membership': {
        'city_id': 'CITY-0084',
        'corporation_id': 'CORP-001',
      },
      'communities': [],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool budgetProposed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InstitutionsCapacityPanel(
              state: state,
              busy: false,
              action: (cb) async {
                budgetProposed = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('INSTITUTIONS / CITY & CORP'), findsNothing);
    expect(
        find.textContaining('CITY: NEW CARTHAGE (CITY-0084)'), findsOneWidget);
    expect(
        find.textContaining(
            '142 residents · Housing cap: 200 · Energy cap: 300'),
        findsOneWidget);
    expect(find.textContaining('CORPORATION: CARTHAGE DYNAMICS (CORP-001)'),
        findsNothing);
    expect(find.text('CHANGE CITY'), findsOneWidget);
    expect(find.text('PROPOSE BUDGET'), findsOneWidget);
    expect(find.text('TAX CHARTER'), findsOneWidget);

    await tester.pumpAndSettle();

    await tester.tap(find.text('PROPOSE BUDGET'));
    await tester.pumpAndSettle();

    expect(budgetProposed, isTrue);
  });
  testWidgets('CityImpactPanel explains city pressure and service conditions',
      (tester) async {
    const state = EarthState({
      'world': {
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.60,
          'connectivity': 0.95,
          'health': 0.90,
        },
      },
      'institutions': {
        'city': {
          'name': 'New Carthage',
          'service_pressure': 62,
          'tax_rate': 4.5
        },
      },
      'business': {'city_operating_modifier': 3.5},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: CityImpactPanel(state: state)),
      ),
    ));

    expect(find.text('CITY EFFECTS / LIFE & BUSINESS'), findsOneWidget);
    expect(find.text('CITY PRESSURE'), findsOneWidget);
    expect(find.text('BUSINESS EFFECT'), findsOneWidget);
    expect(find.text('SERVICE CONDITIONS'), findsOneWidget);
    expect(find.text('HOUSING · 85%'), findsOneWidget);
  });
}
