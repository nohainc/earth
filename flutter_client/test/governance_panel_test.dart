import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/governance_panels.dart';

void main() {
  testWidgets('TabbedProposalPanel renders active proposal and voting choices',
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
        'rules': [
          {
            'institution_id': 'OUC-001',
            'quorum_threshold': 0.3,
            'approval_threshold': 0.5,
            'voting_period_days': 3,
            'implementation_delay_days': 2,
            'status': 'active',
          }
        ],
        'proposals': [
          {
            'id': 'PROP-101',
            'title': 'Infrastructure levy adjustment',
            'institution_id': 'OUC-001',
            'status': 'open',
            'outcome': 'pending',
            'votes': {'support': 12, 'oppose': 3, 'uncast': 5},
          }
        ]
      },
    });

    String? castChoice;

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            body: SingleChildScrollView(
              child: TabbedProposalPanel(
                state: state,
                busy: false,
                action: (callback) async {
                  castChoice = 'voted';
                },
              ),
            ),
          ),
        ),
      ),
    );

    // The new tabbed UI shows tab labels with counts
    expect(find.text('WORLD (1)'), findsOneWidget);
    expect(find.text('CORPORATION (0)'), findsOneWidget);
    expect(find.text('CITY (0)'), findsOneWidget);
    await tester.tap(find.text('WORLD (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Infrastructure levy adjustment'), findsOneWidget);
    expect(find.textContaining('30% quorum · 50% approval'), findsOneWidget);
    expect(find.text('Support 12  ·  Oppose 3  ·  Uncast 5'), findsOneWidget);
    expect(find.text('support'), findsOneWidget);
    expect(find.text('oppose'), findsOneWidget);
    expect(find.text('abstain'), findsOneWidget);

    // Verify info dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Proposals remain open until their configured'),
        findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('support'));
    expect(castChoice, 'voted');
  });

  testWidgets(
      'TabbedProposalPanel renders passed proposal awaiting automatic execution',
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
            'institution_id': 'OUC-001',
            'status': 'closed',
            'outcome': 'passed',
            'quorum': 0.25,
            'approval_threshold': 0.5,
            'execution_status': 'ready',
            'votes': {'support': 40, 'oppose': 10, 'uncast': 0},
          }
        ]
      },
      'roles': [],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            body: SingleChildScrollView(
              child: TabbedProposalPanel(
                state: state,
                busy: false,
                action: (callback) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('WORLD (1)'), findsOneWidget);
    await tester.tap(find.text('WORLD (1)'));
    await tester.pumpAndSettle();
    expect(find.text('APPROVED'), findsOneWidget);
    expect(
        find.text(
            'Approved — the action will start automatically after daily settlement.'),
        findsOneWidget);
    expect(find.text('EXECUTE PROPOSAL'), findsNothing);
    expect(find.text('CHALLENGE PROPOSAL'), findsNothing);
  });

  testWidgets('proposal shows the game deadline and the viewer vote',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 12, 'minute': 60},
      'human': {'id': 'H-1'},
      'institutions': {
        'city': {'id': 'CITY-1'}
      },
      'governance': {
        'proposals': [
          {
            'id': 'CITY-VOTE-1',
            'institution_id': 'CITY-1',
            'title': 'City grid upgrade',
            'status': 'open',
            'outcome': 'pending',
            'closes_game_day': '15',
            'closes_game_minute': '90',
            'my_vote': 'support',
            'votes': {'support': 1, 'oppose': 0, 'uncast': 0},
          },
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TabbedProposalPanel(
            state: state,
            busy: false,
            action: (callback) async {},
          ),
        ),
      ),
    ));

    expect(find.textContaining('Voting ends in 3 days · Year 1 · Day 16'),
        findsOneWidget);
    expect(find.text('VOTED SUPPORT'), findsOneWidget);
    expect(find.text('support'), findsNothing);
    expect(find.text('oppose'), findsNothing);
    expect(find.text('abstain'), findsNothing);
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

    await tester.pumpWidget(const MaterialApp(
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

  testWidgets(
      'TabbedProposalPanel renders clean empty state when no proposals exist',
      (tester) async {
    const state = EarthState({
      'governance': {'proposals': []},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            body: SingleChildScrollView(
              child: TabbedProposalPanel(
                state: state,
                busy: false,
                action: (callback) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('PROPOSALS'), findsOneWidget);
    expect(find.text('No proposals in this category.'), findsOneWidget);
    expect(find.text('WORLD (0)'), findsOneWidget);
    expect(find.text('Support 0  ·  Oppose 0  ·  Uncast 0'), findsNothing);
  });

  testWidgets(
      'TabbedProposalPanel shows proposals in correct tabs and expands queued work',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 12},
      'institutions': {
        'city': {'id': 'CITY-1'}
      },
      'governance': {
        'proposals': [
          {
            'id': 'CITY-BUILD-1',
            'institution_id': 'CITY-1',
            'title': 'Build a civic solar plant',
            'body': 'Approve the next municipal energy project.',
            'status': 'closed',
            'outcome': 'passed',
            'execution_status': 'queued',
            'target_category': 'megaproject_procurement',
            'target_value_json': {'building_type': 'solar_plant'},
            'votes': {'support': 1, 'oppose': 0, 'uncast': 0},
          },
          {
            'id': 'UC-OPEN-1',
            'institution_id': 'OUC-001',
            'title': 'Universal charter update',
            'status': 'open',
            'outcome': 'pending',
            'votes': {'support': 0, 'oppose': 0, 'uncast': 1},
          },
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TabbedProposalPanel(
              state: state,
              busy: false,
              action: (callback) async {},
            ),
          ),
        ),
      ),
    ));

    // World tab shows 1 proposal, City tab shows 1
    expect(find.text('WORLD (1)'), findsOneWidget);
    expect(find.text('CITY (1)'), findsOneWidget);

    // Default tab (City) shows the build proposal.
    expect(find.text('Build a civic solar plant'), findsOneWidget);

    // World remains available as the final tab.
    await tester.tap(find.text('WORLD (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Universal charter update'), findsOneWidget);

    await tester.tap(find.text('CITY (1)'));
    await tester.pumpAndSettle();

    // Expand the building proposal to see rich details
    await tester.tap(find.text('SHOW DETAILS'));
    await tester.pump();
    expect(find.textContaining('Blocker: the approved item'), findsOneWidget);
  });

  testWidgets(
      'TabbedProposalPanel renders typed building catalog and research target proposals with rich layout',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-1'},
      'clock': {'day': 1, 'minute': 0},
      'memberships': {
        'city': {'id': 'CITY-1'},
        'corporation': {'id': 'CORP-1'},
      },
      'buildingCatalog': [
        {
          'id': 'fusion-plant-t1',
          'building_type': 'fusion-plant',
          'name': 'Fusion Power Plant',
          'description': 'Advanced clean energy facility.',
          'tier': 1,
          'slot_footprint': 3,
          'cost_credits': 50000,
          'cost_materials': 400,
          'output_energy': 250,
          'ownership_class': 'civic',
        },
      ],
      'governance': {
        'proposals': [
          {
            'id': 'PROP-BLD-1',
            'institution_id': 'CITY-1',
            'title': 'Commission Fusion Facility',
            'body': 'Urgent strategic energy infrastructure initiative.',
            'status': 'open',
            'outcome': 'pending',
            'target_kind': 'building_catalog',
            'building_catalog_id': 'fusion-plant-t1',
            'target_value_json': {'building_type': 'fusion-plant'},
            'votes': {'support': 5, 'oppose': 1, 'uncast': 0},
          },
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TabbedProposalPanel(
              state: state,
              busy: false,
              action: (callback) async {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('Commission Fusion Facility'), findsOneWidget);

    // Expand details
    await tester.tap(find.text('SHOW DETAILS'));
    await tester.pump();

    // Rationale above
    expect(find.text('Urgent strategic energy infrastructure initiative.'),
        findsOneWidget);
    // Catalog title & description to right
    expect(find.text('Fusion Power Plant'), findsOneWidget);
    expect(find.text('Advanced clean energy facility.'), findsOneWidget);
    expect(find.text('TIER 1'), findsOneWidget);
  });
}
