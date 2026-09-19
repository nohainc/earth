import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/governance_panels.dart';

void main() {
  testWidgets('V5 governance keeps Earth and Corporation scopes explicit',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044'},
      'membership': {'corporation_id': 'CORP-1'},
      'governance': {'proposals': []},
      'corporation': {'id': 'CORP-1', 'name': 'Nova'},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: V5GovernancePanel(
            state: state,
            busy: false,
            action: (callback) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ALL'), findsOneWidget);
    expect(find.textContaining('MY CORPORATION'), findsOneWidget);
    expect(find.text('EARTH (0)'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.textContaining('Territory'), findsNothing);
  });
}
