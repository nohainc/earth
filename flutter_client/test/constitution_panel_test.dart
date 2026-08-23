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
    expect(find.text('PLANETARY CONSTITUTION & GOVERNANCE'), findsOneWidget);
    expect(find.text('3 TIERS'), findsOneWidget);
    expect(find.text('5 LAWS'), findsOneWidget);

    // 2. Hierarchy Tiers
    expect(find.text('GOVERNANCE HIERARCHY & OVERRIDE MODEL'), findsOneWidget);
    expect(find.text('EARTH (UNIVERSAL CITIZENSHIP)'), findsOneWidget);
    expect(find.text('CORPORATIONS'), findsOneWidget);
    expect(find.text('CITIES & MUNICIPALITIES'), findsOneWidget);

    // 3. Active Statutes
    expect(find.text('ACTIVE PLANETARY STATUTES'), findsOneWidget);
    expect(find.text('Central Market Clearing & Fair Allocation'), findsOneWidget);
    expect(find.text('Macroeconomic Statutory Citizen Levy'), findsOneWidget);
    expect(find.text('Democratic Ballot Quorum & Supermajority Thresholds'), findsOneWidget);
    expect(find.text('Mandatory Legislative Cooling-Off & Judicial Review'), findsOneWidget);
    expect(find.text('Dynastic Succession & Testamentary Integrity'), findsOneWidget);
  });
}
