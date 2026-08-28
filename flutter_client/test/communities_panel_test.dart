import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('CommunitiesPanel renders non-member and owner communities with correct badges and actions',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'name': 'Amara Vance', 'credits': 5000},
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
          'founder_id': 'H-9999',
          'founder_name': 'Marcus Aurelius',
          'description': 'Artisanal fabrication guild.',
          'status': 'active',
          'admission_policy': 'open',
          'my_role': null,
          'my_request_status': null,
          'member_count': 16,
          'shared_credits': 240.0,
        },
        {
          'id': 'COM-002',
          'name': 'Solar Engineers',
          'founder_id': 'H-0044',
          'founder_name': 'Amara Vance',
          'description': 'Pioneering clean renewable energy across the quadrant.',
          'status': 'active',
          'admission_policy': 'approval',
          'my_role': 'founder',
          'my_request_status': null,
          'member_count': 5,
          'shared_credits': 1250.0,
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
    expect(find.text('ALL (2)'), findsOneWidget);
    expect(find.text('MY COMMUNITIES (1)'), findsOneWidget);
    expect(find.text('OPEN TO JOIN (1)'), findsOneWidget);

    expect(find.text('Carthage Artisans'), findsOneWidget);
    expect(find.text('Solar Engineers'), findsOneWidget);

    // Verify CONTRIBUTE button is not on registry rows
    expect(find.text('CONTRIBUTE'), findsNothing);

    // Badges & Actions for non-member COM-001
    await tester.tap(find.text('Carthage Artisans'));
    await tester.pumpAndSettle();
    expect(find.text('JOIN'), findsOneWidget);

    // Founder rows expose their role in the registry; management is handled by MyCommunityPanel.
    await tester.tap(find.text('Solar Engineers'));
    await tester.pumpAndSettle();

    // Test filter chip switching
    await tester.tap(find.text('MY COMMUNITIES (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Solar Engineers'), findsOneWidget);
    expect(find.text('Carthage Artisans'), findsNothing);

    await tester.tap(find.text('OPEN TO JOIN (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Carthage Artisans'), findsOneWidget);
    expect(find.text('Solar Engineers'), findsNothing);

    await tester.tap(find.text('ALL (2)'));
    await tester.pumpAndSettle();

    // Test Search filter
    await tester.enterText(find.byType(TextField).first, 'Carthage');
    await tester.pumpAndSettle();
    expect(find.text('Carthage Artisans'), findsOneWidget);
    expect(find.text('Solar Engineers'), findsNothing);

    // Clear search
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(find.text('Carthage Artisans'), findsOneWidget);
    expect(find.text('Solar Engineers'), findsOneWidget);

    // Open Founder Composer Dialog
    await tester.tap(find.text('+ FOUND COMMUNITY'));
    await tester.pumpAndSettle();

    expect(find.text('Found New Community'), findsOneWidget);
    expect(find.text('OPEN ACCESS'), findsOneWidget);
    expect(find.text('APPROVAL REQUIRED'), findsOneWidget);

    // Enter required fields (name and description)
    await tester.enterText(find.widgetWithText(TextField, 'Community Name (Required)'), 'Olympus Cooperative');
    await tester.enterText(find.widgetWithText(TextField, 'Manifesto & Purpose (Required)'), 'Advancing lunar mining automation.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Found Community'));
    await tester.pumpAndSettle();

    expect(communityCreated, isTrue);
  });

  testWidgets('CommunitiesPanel renders CANCEL REQ for pending applications and opens application dialog for approval communities',
      (tester) async {
    bool cancelCalled = false;
    bool applicationSubmitted = false;

    final state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'name': 'Amara Vance', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'membership': {},
      'communities': [
        {
          'id': 'COM-003',
          'name': 'Titan Mining Guild',
          'founder_id': 'H-8888',
          'founder_name': 'Goran Silva',
          'description': 'Heavy orbital mineral excavation.',
          'status': 'active',
          'admission_policy': 'approval',
          'application_question': 'What is your operational excavation experience?',
          'my_role': null,
          'my_request_status': 'pending',
          'member_count': 10,
          'shared_credits': 500.0,
        },
        {
          'id': 'COM-004',
          'name': 'Nebula Research Coop',
          'founder_id': 'H-7777',
          'founder_name': 'Elena Chen',
          'description': 'Advanced particle physics research.',
          'status': 'active',
          'admission_policy': 'approval',
          'application_question': 'List your active academic publications or patents.',
          'my_role': null,
          'my_request_status': null,
          'member_count': 8,
          'shared_credits': 800.0,
        },
      ],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunitiesPanel(
              state: state,
              busy: false,
              action: (cb) async {
                final res = await cb();
                if (res != null) {
                  // action completed
                }
              },
            ),
          ),
        ),
      ),
    );

    // Pending community COM-003 displays CANCEL REQ button
    await tester.tap(find.text('Titan Mining Guild'));
    await tester.pumpAndSettle();
    expect(find.text('CANCEL REQ'), findsOneWidget);
    expect(find.text('PENDING REVIEW'), findsOneWidget);

    // Approval community COM-004 displays APPLY button
    await tester.tap(find.text('Nebula Research Coop'));
    await tester.pumpAndSettle();
    expect(find.text('APPLY'), findsOneWidget);

    // Tap APPLY to open application dialog with question
    await tester.tap(find.text('APPLY'));
    await tester.pumpAndSettle();

    expect(find.text('Apply to Nebula Research Coop'), findsOneWidget);
    expect(find.text('List your active academic publications or patents.'), findsOneWidget);
    expect(find.text('SUBMIT APPLICATION'), findsOneWidget);
  });

  testWidgets('Community details dialog opens and displays manifesto',
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
          'founder_id': 'H-9999',
          'founder_name': 'Marcus Aurelius',
          'description': 'Artisanal fabrication guild of Carthage.',
          'status': 'active',
          'admission_policy': 'open',
          'my_role': null,
          'member_count': 16,
          'shared_credits': 240.0,
        },
      ],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunitiesPanel(
              state: state,
              busy: false,
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Carthage Artisans'));
    await tester.pumpAndSettle();

    expect(find.text('Artisanal fabrication guild of Carthage.'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);
  });

  testWidgets('MyCommunityPanel renders active guild metrics, manifesto, contribution actions, and role badges',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'name': 'Amara Vance', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'membership': {},
      'communities': [
        {
          'id': 'COM-002',
          'name': 'Solar Engineers',
          'founder_id': 'H-0044',
          'founder_name': 'Amara Vance',
          'description': 'Pioneering clean renewable energy across the quadrant.',
          'status': 'active',
          'admission_policy': 'approval',
          'my_role': 'founder',
          'member_count': 5,
          'shared_credits': 1250.0,
        },
      ],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool contributionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyCommunityPanel(
              state: state,
              busy: false,
              action: (cb) async {
                contributionTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('SOLAR ENGINEERS'), findsOneWidget);
    expect(find.text('FOUNDED BY: Amara Vance'), findsOneWidget);
    expect(find.text('OWNER / FOUNDER'), findsOneWidget);
    expect(find.text('1250.00 C'), findsOneWidget);
    expect(find.text('GUILD MANIFESTO & PURPOSE'), findsNothing);
    expect(find.text('Pioneering clean renewable energy across the quadrant.'), findsOneWidget);
    expect(find.text('CONTRIBUTE TO GUILD TREASURY'), findsOneWidget);
    expect(find.text('+100 C'), findsOneWidget);

    await tester.tap(find.text('+100 C'));
    await tester.pumpAndSettle();

    expect(contributionTriggered, isTrue);
  });
}
