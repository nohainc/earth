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
    expect(find.textContaining('Universal Citizenship Democratic Ballot'),
        findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('support'));
    expect(castChoice, 'voted');
  });

  testWidgets(
      'ProposalPanel renders cooling-off judicial review state and disables premature execution',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 10, 'minute': 200},
      'human': {'id': 'h-amara', 'credits': 500, 'standing': 10, 'legacy': 0},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {'city': {}, 'corporation': {}},
      'life': {},
      'governance': {
        'proposals': [
          {
            'id': 'PROP-102',
            'title': 'Energy Tariff Standardization',
            'status': 'closed',
            'outcome': 'passed',
            'quorum': 0.25,
            'approval_threshold': 0.5,
            'implementation_game_day': 13,
            'implementation_delay_days': 3,
            'execution_status': 'ready',
            'votes': {'support': 40, 'oppose': 10, 'uncast': 0},
          }
        ]
      },
      'roles': [],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalPanel(
            state: state,
            busy: false,
            action: (callback) async {},
          ),
        ),
      ),
    );

    expect(find.text('UC PROPOSAL PROP-102'), findsOneWidget);
    expect(find.text('COOLING-OFF'), findsOneWidget);
    expect(find.textContaining('Cooling-off active: Implementation Day 13'),
        findsOneWidget);
    expect(find.text('COOLING-OFF (DAY 13)'), findsOneWidget);
    expect(find.text('CHALLENGE PROPOSAL'), findsOneWidget);
  });
  testWidgets('Civic status and influence explain the player civic position',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-1', 'standing': 420},
      'membership': {
        'status': 'citizen',
        'voting_eligible': true,
        'obligations': 'Annual civic contribution',
      },
      'institutions': {
        'city': {'name': 'Aurelia'}
      },
      'governance': {
        'proposals': [{}]
      },
      'roles': [
        {'human_id': 'H-1', 'name': 'Community Delegate'},
      ],
      'communities': [{}],
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            CivicStatusPanel(state: state),
            CivicInfluencePanel(state: state),
          ]),
        ),
      ),
    ));

    expect(find.text('CIVIC STATUS'), findsOneWidget);
    expect(find.text('AURELIA'), findsOneWidget);
    expect(find.text('ELIGIBLE'), findsOneWidget);
    expect(find.text('YOUR CIVIC INFLUENCE'), findsOneWidget);
    expect(find.text('OFFICES HELD'), findsOneWidget);
  });
}
