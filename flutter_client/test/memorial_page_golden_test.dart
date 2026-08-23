import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/lifecycle/cemetery_pantheon_dialog.dart';

void main() {
  testWidgets('Tier 2 memorial page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((request) async => http.Response(NanoMarkupHelper.encode({
      'cemetery': [{'human_id': 'H-01', 'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty', 'epitaph': 'A lasting foundation.'}],
      'deceasedPantheon': [{'human_id': 'H-01', 'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty', 'epitaph': 'A lasting foundation.'}],
      'dynasticHouses': [{'dynasty_name': 'Vance Dynasty', 'deceased_count': 1, 'peak_legacy': 5400}],
    }), 200, headers: {'content-type': 'application/nanomarkup'}));
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://memorial.test', client: client));
    await tester.pumpWidget(MaterialApp(theme: createEarthTheme(), home: Scaffold(body: CemeteryPantheonDialog(api: api))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/memorial_1440.png'));
  });
}
