import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('corporate page shows affiliation, capital city, and safe leave confirmation', (tester) async {
    const state = EarthState({
      'membership': {'corporation_id': 'CORP-01', 'city_id': 'CITY-01'},
      'institutions': {'corporation': {'id': 'CORP-01', 'name': 'Aether Dynamics', 'capital_city_name': 'New Kyoto', 'member_count': 42, 'treasury': 12000}},
      'technology': {'research': {}},
    });
    var actions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CorporationDirectoryPanel(
      state: state,
      busy: false,
      action: (_) async { actions++; },
    )))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aether Dynamics'), findsWidgets);
    expect(find.textContaining('New Kyoto'), findsWidgets);
    expect(find.text('LEAVE CORPORATION'), findsOneWidget);
    await tester.tap(find.text('LEAVE CORPORATION').first);
    await tester.pumpAndSettle();
    expect(find.text('Leave Corporation?'), findsOneWidget);
    expect(actions, 0);
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Aether Dynamics',
    );
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('LEAVE CORPORATION'),
    ));
    await tester.pumpAndSettle();
    expect(actions, 1);
  });
}
