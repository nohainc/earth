import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/lifecycle/cemetery_pantheon_dialog.dart';

void main() {
  testWidgets('memorial page renders cemetery, pantheon, and dynasty tabs', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/cemetery') {
        return http.Response(NanoMarkupHelper.encode({'cemetery': [
          {'human_id': 'H-01', 'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'successor_name': 'Amara Vance', 'dynasty_name': 'Vance Dynasty', 'epitaph': 'A lasting foundation.'},
        ]}), 200, headers: {'content-type': 'application/nanomarkup'});
      }
      return http.Response(NanoMarkupHelper.encode({'deceasedPantheon': [
        {'human_id': 'H-01', 'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty', 'epitaph': 'A lasting foundation.'},
      ], 'dynasticHouses': [{'dynasty_name': 'Vance Dynasty', 'deceased_count': 1, 'peak_legacy': 5400}]}), 200, headers: {'content-type': 'application/nanomarkup'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://memorial.test', client: client));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CemeteryPantheonDialog(
      api: api,
      lineageSource: const {
        'deceasedPantheon': [
          {'display_name': 'Founder Marcus Vance', 'generation': 1, 'final_legacy': 5400},
        ],
        'livingLeaders': [
          {'display_name': 'Amara Vance', 'generation': 2, 'legacy': 1200},
        ],
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('PLANETARY PANTHEON & CEMETERY ARCHIVE'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsWidgets);
    expect(find.text('ALL CEMETERY MEMORIALS'), findsOneWidget);
    await tester.tap(find.text('PANTHEON OF HONORS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Founder Marcus Vance'), findsWidgets);
    await tester.tap(find.text('DYNASTIC HOUSES'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vance Dynasty'), findsWidgets);
    expect(find.text('DYNASTIC SUCCESSION LINEAGE TREE'), findsOneWidget);
    expect(find.text('Amara Vance'), findsOneWidget);
  });
}
