import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/house/house_tree_dialog.dart';

void main() {
  testWidgets('Tier 2 house page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((_) async => http.Response(
        NanoMarkupHelper.encode({
          'houseProfile': {
            'profileVersion': 'V5-HOUSE-PROFILE-1',
            'identity': {
              'id': 'HOUSE-01',
              'name': 'House of Vance',
              'motto': 'From memory we build',
              'status': 'ACTIVE',
              'generation': 1,
              'founderHumanId': 'H-0044',
              'createdAt': '2026-01-01T00:00:00Z',
            },
            'currentHuman': {
              'id': 'H-0044',
              'displayName': 'Amara Vance',
              'birthGameDay': 1,
              'ageYears': 30,
              'status': 'ACTIVE',
              'standing': '0',
              'finalLegacy': '0',
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
            'economics': {
              'walletUnits': '0',
              'dynastyLegacyUnits': '350',
            },
          },
        }),
        200,
        headers: {'content-type': 'application/nanomarkup'}));
    final api = EarthApi(
        transport:
            EarthApiTransport(baseUrl: 'http://earth.test', client: client));
    await tester.pumpWidget(MaterialApp(
        theme: createEarthTheme(),
        home: Scaffold(body: HouseTreeDialog(api: api))));
    await tester.pumpAndSettle();
    expect(find.byType(HouseTreeDialog), findsOneWidget);
  });
}
