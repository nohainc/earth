import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/world/initiatives_panel.dart';

void main() {
  testWidgets('InitiativesPanel renders segmented pill tabs and switches content',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 100},
      'human': {'name': 'Test Citizen'},
      'publicProjects': {'projects': []},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InitiativesPanel(
            state: state,
            personalFinanceData: const {},
            busy: false,
            action: (fn) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify tabs rendered as segmented pills
    expect(find.text('INITIATIVES'), findsWidgets);
    expect(find.text('PROGRAMS'), findsOneWidget);
    expect(find.text('PROJECTS'), findsOneWidget);

    // Switch to PROJECTS tab
    await tester.tap(find.text('PROJECTS'));
    await tester.pumpAndSettle();

    // Switch back to PROGRAMS tab
    await tester.tap(find.text('PROGRAMS'));
    await tester.pumpAndSettle();
  });
}
