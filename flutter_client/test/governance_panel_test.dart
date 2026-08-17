import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/governance_panels.dart';

void main() {
  testWidgets('ProposalPanel renders active proposal and voting choices',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 1, 'minute': 100},
      'human': {'credits': 500, 'standing': 10, 'legacy': 0},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {'city': {}, 'corporation': {}},
      'life': {},
      'governance': {
        'proposals': [
          {
            'id': 'PROP-101',
            'title': 'Infrastructure levy adjustment',
            'status': 'active',
            'outcome': 'pending',
            'quorum': 0.3,
            'approval_threshold': 0.5,
            'votes': {'support': 12, 'oppose': 3, 'uncast': 5},
          }
        ]
      },
    });

    String? castChoice;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalPanel(
            state: state,
            busy: false,
            action: (callback) async {
              castChoice = 'voted';
            },
          ),
        ),
      ),
    );

    expect(find.text('UC PROPOSAL PROP-101'), findsOneWidget);
    expect(find.text('Infrastructure levy adjustment'), findsOneWidget);
    expect(find.text('Quorum 30% · approval 50%'), findsOneWidget);
    expect(find.text('Support 12  ·  Oppose 3  ·  Uncast 5'), findsOneWidget);
    expect(find.text('support'), findsOneWidget);
    expect(find.text('oppose'), findsOneWidget);
    expect(find.text('abstain'), findsOneWidget);

    // Verify info dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Universal Citizenship Democratic Ballot'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('support'));
    expect(castChoice, 'voted');
  });
}
