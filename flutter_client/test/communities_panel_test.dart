import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('CommunitiesPanel renders community list and opens founder dialog',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'membership': {},
      'communities': [
        {
          'id': 'COM-001',
          'name': 'Carthage Artisans',
          'status': 'active',
          'member_count': 16,
        },
      ],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool communityCreated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunitiesPanel(
              state: state,
              busy: false,
              action: (cb) async {
                communityCreated = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('CITIZEN COMMUNITIES & GUILDS'), findsOneWidget);
    expect(find.textContaining('Carthage Artisans (COM-001)'), findsOneWidget);
    expect(find.textContaining('16 members'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);
    expect(find.text('CONTRIBUTE'), findsOneWidget);

    await tester.tap(find.text('FOUND COMMUNITY'));
    await tester.pumpAndSettle();

    expect(find.text('Found New Community'), findsOneWidget);
    expect(find.text('Found Community'), findsOneWidget);

    await tester.tap(find.text('Found Community'));
    await tester.pumpAndSettle();

    expect(communityCreated, isTrue);
  });
}
