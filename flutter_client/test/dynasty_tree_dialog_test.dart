import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/dynasty/dynasty_tree_dialog.dart';

void main() {
  testWidgets(
      'DynastyTreeDialog renders lineage tree, member list and inspector',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/dynasty') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'dynasty': {
              'id': 'DYN-H0044',
              'email': 'amara@earth.local',
              'dynasty_name': 'House Vance',
              'motto': 'From the Red Dust We Build Eternity',
              'founder_human_id': 'H-0044',
              'legacy_points': 350,
              'total_wealth_generated': 450000.0,
            },
            'lineage': [
              {
                'id': 'LIN-001',
                'dynasty_id': 'DYN-H0044',
                'human_id': 'H-0044',
                'predecessor_human_id': null,
                'generation': 1,
                'name': 'Cassian Vance I',
                'title': 'Pioneer Patriarch',
                'birth_game_day': 1,
                'death_game_day': 140,
                'is_incumbent': false,
                'cause_of_death': 'Hyperbaric Decompression',
                'epitaph': 'Laid the foundation stones of Neo-Tokyo.',
                'lifetime_wealth': 280000.0,
                'businesses_founded': 3,
                'proposals_authored': 4,
                'legacy_score': 180,
              },
              {
                'id': 'LIN-002',
                'dynasty_id': 'DYN-H0044',
                'human_id': 'H-0044',
                'predecessor_human_id': 'H-0044',
                'generation': 2,
                'name': 'Amara Vance',
                'title': 'Current Dynastic Head',
                'birth_game_day': 120,
                'death_game_day': null,
                'is_incumbent': true,
                'cause_of_death': null,
                'epitaph':
                    'Steering House Vance through the corporate expansion age.',
                'lifetime_wealth': 170000.0,
                'businesses_founded': 2,
                'proposals_authored': 2,
                'legacy_score': 170,
              },
            ],
            'perks': [
              {
                'id': 'PRK-001',
                'dynasty_id': 'DYN-H0044',
                'perk_key': 'industrialist_lineage',
                'perk_name': 'Industrialist Lineage',
                'perk_category': 'operations',
                'tier': 1,
                'unlocked_game_day': 140,
              },
            ],
            'heirlooms': [
              {
                'id': 'HLM-001',
                'dynasty_id': 'DYN-H0044',
                'name': 'The Vance Founding Signet',
                'heirloom_type': 'founder_seal',
                'quality_tier': 'Legendary',
                'stat_buff':
                    '+10% Machine Build Speed & -15% Business Startup Fees',
                'equipped_by_human_id': 'H-0044',
                'inscription': 'Forged from titanium.',
              },
            ],
            'catalogPerks': [
              {
                'key': 'industrialist_lineage',
                'name': 'Industrialist Lineage',
                'category': 'Operations',
                'cost': 100,
                'description': '+10% Machine Build Speed',
              },
              {
                'key': 'diplomatic_dynasty',
                'name': 'Diplomatic Dynasty',
                'category': 'Governance',
                'cost': 100,
                'description': '+15% Voting Influence',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200,
          headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport =
        EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynastyTreeDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('HOUSE VANCE'), findsOneWidget);
    expect(find.text('"From the Red Dust We Build Eternity"'), findsOneWidget);
    expect(find.text('Cassian Vance I'), findsWidgets);
    expect(find.text('Amara Vance'), findsOneWidget);
    expect(find.text('GENERATION 1 DOSSIER'), findsOneWidget);
    expect(find.text('FAMILY TODAY'), findsOneWidget);
    expect(find.text('PEOPLE & RELATIONSHIPS'), findsOneWidget);
    expect(find.text('FAMILY IDENTITY'), findsOneWidget);
    expect(find.text('FAMILY HEIRLOOMS & SHARED ASSETS'), findsOneWidget);
  });

  testWidgets('DynastyTreeDialog unlocks hereditary trait', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/dynasty') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'dynasty': {
              'id': 'DYN-H0044',
              'email': 'amara@earth.local',
              'dynasty_name': 'House Vance',
              'motto': 'From the Red Dust We Build Eternity',
              'legacy_points': 350,
              'total_wealth_generated': 450000.0,
            },
            'lineage': [
              {
                'id': 'LIN-001',
                'dynasty_id': 'DYN-H0044',
                'human_id': 'H-0044',
                'name': 'Cassian Vance I',
                'generation': 1,
              },
            ],
            'perks': [],
            'heirlooms': [],
            'catalogPerks': [
              {
                'key': 'diplomatic_dynasty',
                'name': 'Diplomatic Dynasty',
                'category': 'Governance',
                'cost': 100,
                'description': '+15% Voting Influence',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/perks/unlock')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'perkKey': 'diplomatic_dynasty',
            'perkName': 'Diplomatic Dynasty',
            'remainingPoints': 250,
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200,
          headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport =
        EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynastyTreeDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Scroll until unlock perk button is visible
    final unlockBtn =
        find.byKey(const Key('btn-unlock-perk-diplomatic_dynasty'));
    await tester.scrollUntilVisible(unlockBtn, 200);
    expect(unlockBtn, findsOneWidget);

    await tester.tap(unlockBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.textContaining('Hereditary Trait "Diplomatic Dynasty" unlocked!'),
        findsOneWidget);
  });

  testWidgets('DynastyTreeDialog equips and unequips heirloom', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/dynasty') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'dynasty': {
              'id': 'DYN-H0044',
              'email': 'amara@earth.local',
              'dynasty_name': 'House Vance',
              'motto': 'From the Red Dust We Build Eternity',
              'legacy_points': 350,
              'total_wealth_generated': 450000.0,
            },
            'lineage': [],
            'perks': [],
            'heirlooms': [
              {
                'id': 'HLM-001',
                'dynasty_id': 'DYN-H0044',
                'name': 'The Vance Founding Signet',
                'heirloom_type': 'founder_seal',
                'quality_tier': 'Legendary',
                'stat_buff': '+10% Machine Build Speed',
                'equipped_by_human_id': null,
                'inscription': 'Forged from titanium.',
              },
            ],
            'catalogPerks': [],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/heirlooms/equip')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'heirloomId': 'HLM-001',
            'isEquipped': true,
            'equippedBy': 'H-0044',
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200,
          headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport =
        EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynastyTreeDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Scroll until equip heirloom button is visible
    final equipBtn = find.byKey(const Key('btn-equip-heirloom-HLM-001'));
    await tester.scrollUntilVisible(equipBtn, 200);
    expect(equipBtn, findsOneWidget);

    await tester.tap(equipBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('equipped to current Dynastic Head'),
        findsOneWidget);
  });

  testWidgets('DynastyTreeDialog opens edit motto dialog and saves creed',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/dynasty') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'dynasty': {
              'id': 'DYN-H0044',
              'email': 'amara@earth.local',
              'dynasty_name': 'House Vance',
              'motto': 'From the Red Dust We Build Eternity',
              'legacy_points': 350,
              'total_wealth_generated': 450000.0,
            },
            'lineage': [],
            'perks': [],
            'heirlooms': [],
            'catalogPerks': [],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/motto')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'motto': 'Per Aspera Ad Astra',
            'dynastyName': 'House Vance-Neo',
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200,
          headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport =
        EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynastyTreeDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final editBtn = find.byKey(const Key('btn-edit-motto-dialog'));
    expect(editBtn, findsOneWidget);

    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    expect(find.text('EDIT DYNASTY CREED'), findsOneWidget);

    final saveBtn = find.byKey(const Key('btn-save-motto'));
    expect(saveBtn, findsOneWidget);

    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Dynasty creed updated successfully'),
        findsOneWidget);
  });
}
