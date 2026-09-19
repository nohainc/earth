import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/house/house_tree_dialog.dart';

Map<String, dynamic> _houseResponse() => {
      'ok': true,
      'houseProfile': {
        'profileVersion': 'V5-HOUSE-PROFILE-1',
        'identity': {
          'id': 'HOUSE-H0044',
          'name': 'House Vance',
          'motto': 'From the Red Dust We Build Eternity',
          'status': 'ACTIVE',
          'generation': 2,
          'founderHumanId': 'H-0044',
          'createdAt': '2026-01-01T00:00:00Z',
        },
        'currentHuman': {
          'id': 'H-0044',
          'displayName': 'Amara Vance',
          'birthGameDay': 120,
          'ageYears': 34,
          'status': 'ACTIVE',
          'standing': '100',
          'finalLegacy': '170',
        },
        'affiliation': {
          'corporationId': 'CORP-NOVA',
          'corporationName': 'Nova',
          'joinedGameDay': 140,
          'status': 'ACTIVE',
        },
        'settlementProfile': {
          'corporationId': 'CORP-NOVA',
          'residentialCapacityUnits': '82',
          'productiveCapacityUnits': '74',
          'totalCapacityUnits': '156',
          'activeBuildingCount': 4,
          'profileVersion': 'V5-HOUSE-SETTLEMENT-1',
          'sourceGameDay': 184,
          'dirty': false,
        },
        'succession': {
          'successorName': 'Elena Vance',
          'registeredGameDay': 180,
          'status': 'ACTIVE',
        },
        'successionPolicy': {
          'fixedCostUnits': '500',
          'percentageCostBps': '250',
          'transitionDays': 2,
          'rulesVersion': 'RULE-184',
        },
        'successionQuote': {
          'houseWalletUnits': '10000',
          'estimatedCostUnits': '500',
          'calculation': 'FIXED',
          'affordable': true,
        },
        'economics': {
          'walletUnits': '10000',
          'dynastyLegacyUnits': '350',
        },
        'lineage': [
          {
            'humanId': 'H-0033',
            'displayName': 'Cassian Vance',
            'generation': 1,
            'birthGameDay': 1,
            'deathGameDay': 119,
            'status': 'DECEASED',
            'standing': '80',
            'finalLegacy': '150',
            'relationship': 'PREDECESSOR',
            'relatedHumanId': 'H-0044',
            'successionEventId': 'S-1',
            'successionStatus': 'COMPLETED',
            'effectiveGameDay': 120,
          },
          {
            'humanId': 'H-0044',
            'displayName': 'Amara Vance',
            'generation': 2,
            'birthGameDay': 120,
            'deathGameDay': null,
            'status': 'ACTIVE',
            'standing': '100',
            'finalLegacy': '170',
            'relationship': 'CURRENT',
            'relatedHumanId': null,
            'successionEventId': null,
            'successionStatus': null,
            'effectiveGameDay': null,
          },
        ],
        'history': [
          {
            'id': 'EVENT-1',
            'gameDay': 120,
            'gameMinute': 100,
            'category': 'LIFECYCLE',
            'eventType': 'HOUSE_SUCCESSION',
            'title': 'Amara Vance succeeded Cassian Vance',
            'subjectType': 'HOUSE',
            'subjectId': 'HOUSE-H0044',
          },
        ],
      },
    };

EarthApi _api({Future<http.Response> Function(http.Request)? handler}) {
  final client = MockClient(handler ??
      (request) async {
        return http.Response(
          NanoMarkupHelper.encode({'ok': true}),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      });
  return EarthApi(
    baseUrl: 'http://earth.test',
    transport: EarthApiTransport(baseUrl: 'http://earth.test', client: client),
  );
}

void main() {
  testWidgets('HouseTreeDialog renders only canonical House systems',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final api = _api(
      handler: (request) async => http.Response(
        NanoMarkupHelper.encode(_houseResponse()),
        200,
        headers: {'content-type': 'application/x-nano-markup'},
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HouseTreeDialog(api: api)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('VANCE'), findsWidgets);
    expect(find.text('Amara Vance'), findsWidgets);
    expect(find.text('LINEAGE & HEIRS'), findsOneWidget);
    expect(find.text('SUCCESSION & CURRENT HEAD'), findsOneWidget);
    expect(find.text('RESIDENTIAL CAPACITY'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('PRODUCTIVE CAPACITY'), findsOneWidget);
    expect(find.text('ACTIVE BUILDINGS'), findsOneWidget);
    expect(find.text('Elena Vance'), findsOneWidget);
    expect(find.text('FIXED COST'), findsOneWidget);
    expect(find.text('TRANSITION'), findsOneWidget);
    expect(find.text('Cassian Vance'), findsOneWidget);
    expect(find.text('PREDECESSOR'), findsOneWidget);
    expect(find.text('HOUSE HISTORY'), findsOneWidget);
    expect(find.text('Amara Vance succeeded Cassian Vance'), findsOneWidget);
    expect(find.text('MY CORPORATION'), findsOneWidget);
    expect(find.text('BUILDINGS'), findsOneWidget);
    expect(find.text('FINANCE'), findsOneWidget);
    expect(find.text('HEREDITARY PERKS'), findsNothing);
    expect(find.text('SHARED HEIRLOOMS & RELICS'), findsNothing);
    expect(find.text('HOUSE SCORE'), findsNothing);
    expect(find.text('HOUSE STANDING'), findsNothing);
    expect(find.text('TERRITORY'), findsNothing);
    expect(find.text('HISTORICAL MILESTONES & ACHIEVEMENTS'), findsNothing);
  });

  testWidgets('HouseTreeDialog keeps canonical House name editing',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final api = _api(
      handler: (request) async {
        if (request.url.path == '/api/house') {
          return http.Response(
            NanoMarkupHelper.encode(_houseResponse()),
            200,
            headers: {'content-type': 'application/x-nano-markup'},
          );
        }
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'motto': 'Per Aspera Ad Astra',
            'houseName': 'House Vance-Neo',
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HouseTreeDialog(api: api)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('btn-edit-motto-dialog')));
    await tester.pumpAndSettle();
    expect(find.text('EDIT HOUSE NAME'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-save-motto')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.textContaining('House name updated successfully'), findsOneWidget);
  });
}
