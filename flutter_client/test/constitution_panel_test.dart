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
    // Hierarchy tiers
    expect(find.text('GOVERNANCE HIERARCHY & OVERRIDE MODEL'), findsOneWidget);
    expect(find.text('EARTH'), findsOneWidget);
    expect(find.text('CORPORATION'), findsOneWidget);
    expect(find.text('CITY'), findsOneWidget);

    expect(find.textContaining('Constitutional rules are unavailable'), findsOneWidget);
  });
}
