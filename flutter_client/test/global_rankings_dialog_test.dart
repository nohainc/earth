import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/lifecycle/global_rankings_dialog.dart';

void main() {
  testWidgets('GlobalRankingsDialog renders podium, categories, table, and inspector',
      (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/rankings') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'citizens': [
              {
                'rank': 1,
                'rankDelta': 0,
                'tierBadge': 'Sovereign',
                'id': 'H-0044',
                'displayName': 'Amara Vance',
                'ageYears': 42,
                'standing': 840,
                'legacy': 120,
                'credits': 5000,
                'cityId': 'city-new-tokyo',
                'dynastyName': 'Vance Dynasty',
                'compositeScore': 14484,
              },
              {
                'rank': 2,
                'rankDelta': 1,
                'tierBadge': 'Patrician',
                'id': 'H-0012',
                'displayName': 'Dmitri Rostov',
                'ageYears': 38,
                'standing': 720,
                'legacy': 95,
                'credits': 4200,
                'cityId': 'city-london',
                'dynastyName': 'House of Rostov',
                'compositeScore': 12150,
              },
              {
                'rank': 3,
                'rankDelta': -1,
                'tierBadge': 'Patrician',
                'id': 'H-0088',
                'displayName': 'Kaelen Thorne',
                'ageYears': 49,
                'standing': 680,
                'legacy': 80,
                'credits': 3800,
                'cityId': 'city-geneva',
                'dynastyName': 'Thorne Syndicate',
                'compositeScore': 10980,
              },
            ],
            'cities': [
              {
                'id': 'city-new-tokyo',
                'name': 'Neo-Tokyo',
                'residents': 124,
                'treasury': 28500,
                'qolIndex': 92,
                'rank': 1,
                'rankDelta': 0,
              },
            ],
            'corporations': [
              {
                'id': 'corp-kline-industrial',
                'name': 'Kline Industrial Syndicate',
                'member_count': 14,
                'treasury': 32000,
                'marketCap': 84000,
                'rank': 1,
                'rankDelta': 0,
              },
            ],
            'dynasticHouses': [
              {
                'dynasty_name': 'Vance Dynasty',
                'deceased_count': 3,
                'peak_legacy': 5400,
                'peak_standing': 980,
                'rank': 1,
                'rankDelta': 0,
              },
            ],
            'technologies': [
              {
                'id': 'tech-quantum-core',
                'name': 'Quantum Core Infrastructure',
                'owner_id': 'H-0044',
                'progress': 100,
                'rank': 1,
                'rankDelta': 0,
              },
            ],
            'userStanding': {
              'rank': 1,
              'totalTracked': 3,
              'tierBadge': 'Sovereign',
              'score': 14484,
            },
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
          body: GlobalRankingsDialog(api: api),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Subtitle
    expect(find.text('CIVILIZATIONAL LEADERBOARDS & RANKINGS'), findsOneWidget);
    expect(find.text('CIVILIZATIONAL APEX PODIUM (TOP 3)'), findsOneWidget);
    expect(find.text('🥇 GOLD'), findsOneWidget);
    expect(find.text('🥈 SILVER'), findsOneWidget);
    expect(find.text('🥉 BRONZE'), findsOneWidget);

    // Verify Citizen entries in Podium & Table
    expect(find.textContaining('Amara Vance'), findsWidgets);
    expect(find.textContaining('Dmitri Rostov'), findsWidgets);
    expect(find.textContaining('Kaelen Thorne'), findsWidgets);
    expect(find.text('SOVEREIGN'), findsWidgets);
    expect(find.text('PATRICIAN'), findsWidgets);

    // Verify Sticky User Position
    expect(find.text('YOUR STANDING: Rank #1 of 3'), findsOneWidget);

    // Switch Category Tab to CITIES
    final citiesChip = find.text('CITIES');
    await tester.ensureVisible(citiesChip);
    await tester.tap(citiesChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('Neo-Tokyo'), findsWidgets);

    // Switch Category Tab to CORPORATIONS
    final corpsChip = find.text('CORPORATIONS');
    await tester.ensureVisible(corpsChip);
    await tester.tap(corpsChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('Kline Industrial Syndicate'), findsWidgets);

    // Switch Category Tab to DYNASTIES
    final dynChip = find.text('DYNASTIES');
    await tester.ensureVisible(dynChip);
    await tester.tap(dynChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('Vance Dynasty'), findsWidgets);

    // Tap dynasty row to open inspector
    final dynRow = find.textContaining('Vance Dynasty').first;
    await tester.ensureVisible(dynRow);
    await tester.tap(dynRow);
    await tester.pumpAndSettle();

    expect(find.text('Inscribed Ancestors'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('Dynastic Legacy'), findsOneWidget);
    expect(find.text('5400 LP'), findsWidgets);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Switch Category Tab to TECHNOLOGIES
    final techChip = find.text('TECHNOLOGIES');
    await tester.ensureVisible(techChip);
    await tester.tap(techChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('Quantum Core Infrastructure'), findsWidgets);

    // Tap first technology row to open inspector
    final techRow = find.textContaining('Quantum Core Infrastructure').first;
    await tester.ensureVisible(techRow);
    await tester.tap(techRow);
    await tester.pumpAndSettle();

    expect(find.text('Entity ID / Ticker'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    // Close Inspector
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });
}
