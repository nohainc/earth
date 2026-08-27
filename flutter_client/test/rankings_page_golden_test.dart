import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/lifecycle/global_rankings_dialog.dart';

void main() {
  testWidgets('Tier 2 rankings page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((request) async => http.Response(
      NanoMarkupHelper.encode({
        'citizens': [{'rank': 1, 'rankDelta': 0, 'tierBadge': 'Sovereign', 'id': 'H-01', 'displayName': 'Amara Vance', 'standing': 840, 'legacy': 120, 'credits': 5000, 'compositeScore': 14484}],
        'cities': [{'id': 'CITY-01', 'name': 'Neo-Tokyo', 'residents': 124, 'rank': 1, 'rankDelta': 0}],
        'corporations': [{'id': 'CORP-01', 'name': 'Aether Dynamics', 'member_count': 42, 'rank': 1, 'rankDelta': 0}],
        'houses': [],
        'technologies': [],
        'userStanding': {'rank': 1, 'totalTracked': 1, 'tierBadge': 'Sovereign', 'score': 14484},
      }), 200, headers: {'content-type': 'application/nanomarkup'}));
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://127.0.0.1:8899', client: client));
    await tester.pumpWidget(MaterialApp(theme: createEarthTheme(), home: Scaffold(body: GlobalRankingsDialog(api: api))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/rankings_1440.png'));
  });
}
