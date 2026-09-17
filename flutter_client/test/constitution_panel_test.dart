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
              'rules': {'EARTH.CAPACITY.BASE_RATE': '1000'},
              'versionIds': {'EARTH.CAPACITY.BASE_RATE': 'CONST-V1'},
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EARTH.CAPACITY.BASE_RATE'), findsOneWidget);
    expect(find.text('1000 · CONST-V1'), findsOneWidget);
  });
}
