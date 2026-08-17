import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('InstitutionsCapacityPanel renders city residency, pressure ratios, and proposes budget',
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

    expect(find.text('INSTITUTIONS / CITY & CORP'), findsOneWidget);
    expect(find.textContaining('CITY: NEW CARTHAGE (CITY-0084)'), findsOneWidget);
    expect(find.textContaining('142 residents · Housing cap: 200 · Energy cap: 300'), findsOneWidget);
    expect(find.textContaining('CORPORATION: CARTHAGE DYNAMICS (CORP-001)'), findsOneWidget);
    expect(find.text('LEAVE CITY'), findsOneWidget);
    expect(find.text('PROPOSE BUDGET'), findsOneWidget);
    expect(find.text('TAX CHARTER'), findsOneWidget);
    expect(find.text('FUND SERVICES · 100 C'), findsOneWidget);

    // Verify info dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Municipal & Corporate Institutions'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PROPOSE BUDGET'));
    await tester.pumpAndSettle();

    expect(budgetProposed, isTrue);
  });
}
