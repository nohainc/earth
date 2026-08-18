import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/lifecycle/cemetery_pantheon_dialog.dart';

void main() {
  testWidgets('CemeteryPantheonDialog renders memorials, tabs, and dynasties',
      (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/cemetery') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'cemetery': [
              {
                'human_id': 'H-0044',
                'display_name': 'Founder Marcus Vance',
                'death_game_day': 840,
                'final_standing': 980,
                'final_legacy': 4500,
                'successor_name': 'Marcus Vance II',
                'cause_of_death': 'Natural Biological Mortality',
                'epitaph': 'Pioneered civilization across the frontier of Earth.',
                'dynasty_name': 'Vance Dynasty',
              },
              {
                'human_id': 'H-0089',
                'display_name': 'Senator Elena Rostova',
                'death_game_day': 720,
                'final_standing': 850,
                'final_legacy': 3200,
                'successor_name': 'Dmitri Rostov',
                'cause_of_death': 'Natural Biological Mortality',
                'epitaph': 'Champion of municipal justice and trade.',
                'dynasty_name': 'House of Rostov',
              },
            ],
            'totalReturned': 2,
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }
      if (request.url.path == '/api/pantheon') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'deceasedPantheon': [
              {
                'human_id': 'H-0044',
                'display_name': 'Founder Marcus Vance',
                'death_game_day': 840,
                'final_standing': 980,
                'final_legacy': 4500,
                'successor_name': 'Marcus Vance II',
                'cause_of_death': 'Natural Biological Mortality',
                'epitaph': 'Pioneered civilization across the frontier of Earth.',
                'dynasty_name': 'Vance Dynasty',
              },
            ],
            'dynasticHouses': [
              {
                'dynasty_name': 'Vance Dynasty',
                'deceased_count': 3,
                'peak_legacy': 4500,
              },
              {
                'dynasty_name': 'House of Rostov',
                'deceased_count': 2,
                'peak_legacy': 3200,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }
      return http.Response('{}', 404);
    });

    final api = EarthApi(
      transport: EarthApiTransport(baseUrl: 'http://127.0.0.1:8899', client: mockClient),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CemeteryPantheonDialog(api: api),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Subtitle
    expect(find.text('PLANETARY PANTHEON & CEMETERY ARCHIVE'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsWidgets);
    expect(find.textContaining('Senator Elena Rostova'), findsOneWidget);
    expect(find.textContaining('LEGACY: 4500'), findsOneWidget);
    expect(find.text('“Pioneered civilization across the frontier of Earth.”'),
        findsOneWidget);

    // Switch to Dynastic Houses Tab
    await tester.tap(find.text('DYNASTIC HOUSES'));
    await tester.pumpAndSettle();

    expect(find.text('Vance Dynasty'), findsOneWidget);
    expect(find.text('House of Rostov'), findsOneWidget);
    expect(find.textContaining('Deceased Ancestors Inscribed: 3'), findsOneWidget);

    // Switch to Pantheon Tab
    await tester.tap(find.text('PANTHEON OF HONORS'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Founder Marcus Vance'), findsWidgets);
  });
}
