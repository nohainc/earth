import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/constitution_panel.dart';

void main() {
  testWidgets('ConstitutionPanel renders planetary hierarchy, tiers, and statutes', (tester) async {
    const state = EarthState({
      'clock': {'day': 185},
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
    expect(find.text('Sole Monetary Authority'), findsOneWidget);
    expect(find.text('House Continuity Invariant'), findsOneWidget);
    expect(find.text('Constitutional Amendment Supermajority'), findsOneWidget);
  });
}
