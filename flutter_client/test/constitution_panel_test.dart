import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/constitution_panel.dart';

void main() {
  testWidgets(
      'ConstitutionPanel renders planetary hierarchy, tiers, and statutes',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185},
      'constitutionalRules': [
        {
          'id': 'CONST-TIME-001',
          'part_number': 1,
          'rule_number': '1.1',
          'category': 'TIME & SETTLEMENT',
          'title': 'Authoritative World Time',
          'description': 'The canonical World Clock governs settlement.',
          'default_value': 'World Clock',
          'permitted_values': 'Immutable',
          'authority': 'EARTH',
          'invariant': true,
        },
        {
          'id': 'CONST-AMEND-001',
          'part_number': 10,
          'rule_number': '10.1',
          'category': 'AMENDMENTS & CONSTITUTION',
          'title': 'Constitutional Amendment Supermajority',
          'description': 'Constitutional amendments require supermajority.',
          'default_value': '67%',
          'permitted_values': 'Planetary Referendum',
          'authority': 'EARTH',
          'invariant': true,
        },
      ],
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(state: state),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Core Header & Invariants Metrics
    expect(find.text('PLANETARY CONSTITUTION'), findsOneWidget);
    expect(find.text('EARTH'), findsWidgets);
    expect(find.text('ORGANIZATION'), findsWidgets);
    expect(find.text('TERRITORY'), findsWidgets);

    // 2. Canonical Articles & Search
    expect(find.text('Authoritative World Time'), findsOneWidget);
    expect(find.text('Constitutional Amendment Supermajority'), findsOneWidget);
  });

  testWidgets('ConstitutionPanel can render a canonical typed policy snapshot',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185}
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(
            state: state,
            canonicalLoader: () async => {
              'ok': true,
              'gameDay': 185,
              'rules': {
                'EARTH.CAPACITY.BASE_RATE': '1000',
                'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': 'SCHEDULE-V1',
              },
              'versionIds': {
                'EARTH.CAPACITY.BASE_RATE': 'CONST-V1',
                'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': 'CONST-SCHEDULE-V1',
              },
              'scheduleBrackets': {
                'SCHEDULE-V1': [
                  {
                    'lower_bound_units': '0',
                    'upper_bound_units': '10',
                    'marginal_multiplier_numerator': '1',
                    'marginal_multiplier_denominator': '1',
                  },
                  {
                    'lower_bound_units': '10',
                    'marginal_multiplier_numerator': '2',
                    'marginal_multiplier_denominator': '1',
                  },
                ],
              },
              'history': [
                {
                  'rule_code': 'EARTH.CAPACITY.BASE_RATE',
                  'value_json': {'value': '1000'},
                  'effective_from_game_day': 1,
                  'status': 'ACTIVE',
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EARTH.CAPACITY.BASE_RATE'), findsNWidgets(2));
    expect(find.text('1000 · CONST-V1'), findsOneWidget);
    expect(find.text('CONSTITUTION RULE HISTORY'), findsOneWidget);
    expect(find.textContaining('DAY 1 · ACTIVE'), findsOneWidget);
    expect(find.text('PROGRESSIVE BRACKETS'), findsOneWidget);
    expect(find.text('0–10 · ×1/1'), findsOneWidget);
  });
}
