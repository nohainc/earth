import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/community_models.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

class _SuccessfulApiTransport extends EarthApiTransport {
  @override
  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    return <String, dynamic>{'ok': true};
  }
}

void main() {
  test('Community roles accept only OWNER, MODERATOR, and MEMBER', () {
    expect(normalizeCommunityRole('OWNER'), 'OWNER');
    expect(normalizeCommunityRole('MODERATOR'), 'MODERATOR');
    expect(normalizeCommunityRole('MEMBER'), 'MEMBER');
    expect(normalizeCommunityRole('FOUNDER'), isEmpty);
    expect(normalizeCommunityRole('ADMIN'), isEmpty);

    final founder = CommunityMember.fromJson({
      'house_id': 'HOUSE-1',
      'house_name': 'House One',
      'role': 'FOUNDER',
    });
    expect(founder.role, isEmpty);
  });

  test(
      'House community membership keeps its role when its representative succeeds',
      () {
    final before = CommunityMember.fromJson({
      'house_id': 'HOUSE-1',
      'house_name': 'House One',
      'current_human_id': 'HUMAN-1',
      'current_human_name': 'First Representative',
      'role': 'MODERATOR',
    });
    final after = CommunityMember.fromJson({
      'house_id': 'HOUSE-1',
      'house_name': 'House One',
      'current_human_id': 'HUMAN-2',
      'current_human_name': 'Successor Representative',
      'role': 'MODERATOR',
    });

    expect(after.houseId, before.houseId);
    expect(after.role, before.role);
    expect(after.currentHumanId, isNot(before.currentHumanId));
    expect(after.currentHumanName, 'Successor Representative');
  });

  test('Community access and roles never infer membership or founder status', () {
    final visitor = CommunitySummary.fromJson({
      'id': 'COM-PUBLIC',
      'name': 'Public Community',
      'founder_house_id': 'HOUSE-FOUNDER',
      'founder_house_name': 'House Founder',
      'member_count': 2,
      'viewer': {'membershipStatus': null, 'role': null},
    });
    final owner = CommunityMember.fromJson({
      'house_id': 'HOUSE-OWNER',
      'house_name': 'House Owner',
      'role': 'OWNER',
    });

    expect(visitor.viewer.membershipStatus, isNull);
    expect(visitor.viewer.role, isNull);
    expect(owner.role, 'OWNER');
    expect(owner.role, isNot('FOUNDER'));
    expect(visitor.founderHouseName, 'House Founder');
  });

  test('Community membership pagination preserves large rosters and cursors', () {
    final response = CommunityMembersResponse.fromJson({
      'members': List.generate(
        125,
        (index) => {
          'house_id': 'HOUSE-$index',
          'house_name': 'House $index',
          'role': index == 0 ? 'OWNER' : 'MEMBER',
        },
      ),
      'totalCount': 125,
      'hasMore': true,
      'nextCursor': 'cursor-100',
    });

    expect(response.members, hasLength(125));
    expect(response.totalCount, 125);
    expect(response.hasMore, isTrue);
    expect(response.nextCursor, 'cursor-100');
  });

  test('Owner leave capabilities distinguish sole-owner and transferable ownership', () {
    CommunityViewerPermissions permissions(Map<String, dynamic> json) =>
        CommunityViewerPermissions.fromJson({
          'membershipStatus': 'ACTIVE',
          'role': 'OWNER',
          ...json,
        });

    expect(permissions({'canLeave': false, 'capabilities': {}}).canLeave,
        isFalse);
    expect(permissions({'canLeave': true, 'capabilities': {}}).canLeave,
        isTrue);
  });

  testWidgets(
      'CommunitiesPanel renders non-member and owner communities with correct badges and actions',
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
          'join_policy': 'OPEN',
          'viewer': {
            'membershipStatus': null,
            'role': null,
            'requestStatus': null,
            'canJoin': true
          },
          'member_count': 16,
          'shared_credits': 240.0,
        },
        {
          'id': 'COM-002',
          'name': 'Solar Engineers',
          'founder_id': 'H-0044',
          'founder_name': 'Amara Vance',
          'description':
              'Pioneering clean renewable energy across the quadrant.',
          'status': 'active',
          'join_policy': 'REQUEST',
          'viewer': {
            'membershipStatus': 'ACTIVE',
            'role': 'OWNER',
            'requestStatus': null,
            'canJoin': false,
            'canLeave': false,
            'canEdit': true,
            'canTransferOwnership': true,
            'canDisband': true,
          },
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
              communityApi: EarthApi(transport: _SuccessfulApiTransport()),
            ),
          ),
        ),
      ),
    );

    expect(find.text('COMMUNITIES'), findsOneWidget);
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

    expect(find.text('Create Community'), findsOneWidget);
    expect(find.text('OPEN ACCESS'), findsOneWidget);
    expect(find.text('APPROVAL REQUIRED'), findsOneWidget);

    // Enter required fields (name and description)
    await tester.enterText(
        find.widgetWithText(TextField, 'Community Name (Required)'),
        'Olympus Cooperative');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description (Required)'),
        'Advancing lunar mining automation.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Found Community'));
    await tester.pumpAndSettle();

    expect(communityCreated, isTrue);
  });

  testWidgets(
      'CommunitiesPanel renders CANCEL REQ for pending applications and opens application dialog for approval communities',
      (tester) async {
    bool cancelCalled = false;
    bool applicationSubmitted = false;

    final state = const EarthState({
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
          'join_policy': 'REQUEST',
          'application_question':
              'What is your operational excavation experience?',
          'viewer': {
            'membershipStatus': null,
            'role': null,
            'requestStatus': 'PENDING',
            'canJoin': false
          },
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
          'join_policy': 'REQUEST',
          'application_question':
              'List your active academic publications or patents.',
          'viewer': {
            'membershipStatus': null,
            'role': null,
            'requestStatus': null,
            'canJoin': true
          },
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
                // action completed
              },
            ),
          ),
        ),
      ),
    );

    // Pending community COM-003 displays a non-actionable pending state
    await tester.tap(find.text('Titan Mining Guild'));
    await tester.pumpAndSettle();
    expect(find.text('REQUEST PENDING'), findsOneWidget);
    expect(find.text('PENDING REVIEW'), findsOneWidget);

    // Approval community COM-004 displays APPLY button
    await tester.tap(find.text('Nebula Research Coop'));
    await tester.pumpAndSettle();
    expect(find.text('APPLY'), findsOneWidget);

    // Tap APPLY to open the application-note dialog
    await tester.tap(find.text('APPLY'));
    await tester.pumpAndSettle();

    expect(find.text('Apply to Nebula Research Coop'), findsOneWidget);
    expect(find.text('APPLICATION NOTE'), findsOneWidget);
    expect(
      find.text(
          'Optionally tell the community owners why you would like to join.'),
      findsOneWidget,
    );
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
          'join_policy': 'OPEN',
          'viewer': {
            'membershipStatus': null,
            'role': null,
            'requestStatus': null,
            'canJoin': true
          },
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

    expect(
        find.text('Artisanal fabrication guild of Carthage.'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);
  });

  testWidgets('MyCommunityPanel renders active guild metrics and role badges',
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
          'description':
              'Pioneering clean renewable energy across the quadrant.',
          'status': 'active',
          'join_policy': 'REQUEST',
          'viewer': {
            'membershipStatus': 'ACTIVE',
            'role': 'OWNER',
            'requestStatus': null,
            'canJoin': false,
            'canLeave': false
          },
          'member_count': 5,
        },
      ],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    String? navigatedSection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyCommunityPanel(
              state: state,
              busy: false,
              action: (cb) async {},
              onNavigate: (sec) => navigatedSection = sec,
            ),
          ),
        ),
      ),
    );

    expect(find.text('SOLAR ENGINEERS'), findsOneWidget);
    expect(find.text('Founded by Amara Vance'), findsNothing);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('REQUEST'), findsOneWidget);
    expect(find.text('OPEN CHAT'), findsOneWidget);
    expect(find.text('GUILD MANIFESTO & PURPOSE'), findsNothing);
    expect(find.text('Pioneering clean renewable energy across the quadrant.'),
        findsOneWidget);
    expect(find.text('CONTRIBUTE TO GUILD TREASURY'), findsNothing);

    await tester.tap(find.text('OPEN CHAT'));
    await tester.pumpAndSettle();
    expect(navigatedSection, 'messages:channel-community-COM-002');
  });
}
