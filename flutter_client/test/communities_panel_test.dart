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
    expect(find.textContaining('Carthage Artisans (COM-001)'), findsOneWidget);
    expect(find.textContaining('Solar Engineers (COM-002)'), findsOneWidget);

    // Badges & Actions for non-member COM-001
    expect(find.text('JOIN'), findsOneWidget);
    expect(find.text('DETAILS'), findsNWidgets(2));

    // Badges & Actions for founder COM-002
    expect(find.text('OWNER / FOUNDER'), findsOneWidget);
    expect(find.text('MANAGE'), findsOneWidget);

    // Open Founder Composer Dialog
    await tester.tap(find.text('FOUND COMMUNITY'));
    await tester.pumpAndSettle();

    expect(find.text('Found New Community'), findsOneWidget);
    expect(find.text('OPEN ACCESS'), findsNWidgets(2));
    expect(find.text('APPROVAL REQUIRED'), findsOneWidget);

    await tester.tap(find.text('Found Community'));
    await tester.pumpAndSettle();

    expect(communityCreated, isTrue);
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

    await tester.tap(find.text('DETAILS'));
    await tester.pumpAndSettle();

    expect(find.text('MANIFESTO & PURPOSE'), findsOneWidget);
    expect(find.text('Artisanal fabrication guild of Carthage.'), findsOneWidget);
    expect(find.text('JOIN COMMUNITY'), findsOneWidget);
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
    expect(find.textContaining('Guild ID: COM-002'), findsOneWidget);
    expect(find.text('OWNER / FOUNDER'), findsOneWidget);
    expect(find.text('1250.00 C'), findsOneWidget);
    expect(find.text('GUILD MANIFESTO & PURPOSE'), findsOneWidget);
    expect(find.text('Pioneering clean renewable energy across the quadrant.'), findsOneWidget);
    expect(find.text('CONTRIBUTE TO GUILD TREASURY'), findsOneWidget);
    expect(find.text('+100 C'), findsOneWidget);

    await tester.tap(find.text('+100 C'));
    await tester.pumpAndSettle();

    expect(contributionTriggered, isTrue);
  });
}
