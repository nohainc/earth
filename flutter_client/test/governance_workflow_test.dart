import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/governance_panels.dart';

void main() {
  testWidgets('ProposalPanel renders passed proposal and executes proposal',
      (tester) async {
    const passedState = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {
        'proposals': [
          {
            'id': 'PROP-042',
            'title': 'Expand Municipal Solar Grid',
            'status': 'passed',
            'outcome': 'passed',
            'execution_status': 'executable',
            'quorum': 0.25,
            'approval_threshold': 0.50,
            'votes': {'support': 450, 'oppose': 50, 'uncast': 0},
          },
        ],
      },
      'roles': [],
      'finance': {'taxRules': []},
      'market': {'orders': []},
    });

    bool executeTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProposalPanel(
              state: passedState,
              busy: false,
              action: (cb) async {
                executeTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('UC PROPOSAL PROP-042'), findsOneWidget);
    expect(find.text('Expand Municipal Solar Grid'), findsOneWidget);
    expect(find.text('EXECUTABLE'), findsOneWidget);
    expect(find.text('EXECUTE PROPOSAL'), findsOneWidget);
    expect(find.text('CHALLENGE PROPOSAL'), findsOneWidget);

    await tester.tap(find.text('EXECUTE PROPOSAL'));
    await tester.pumpAndSettle();

    expect(executeTriggered, isTrue);
  });

}
