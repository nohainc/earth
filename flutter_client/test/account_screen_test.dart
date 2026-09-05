import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/account/account_screen.dart';

void main() {
  testWidgets('AccountScreen renders identity, MFA status, sessions, and delete zone',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/me') {
        return http.Response(
          jsonEncode({
            'authenticated': true,
            'human': {
              'id': 'H-12345678',
              'email': 'commander@earth.test',
              'display_name': 'Commander Shepard',
              'life_status': 'active',
              'mfa_enabled': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/auth/sessions') {
        return http.Response(
          jsonEncode({
            'ok': true,
            'sessions': [
              {
                'id': 'sess-current-01',
                'current': true,
                'created_at': '2026-08-30T12:00:00Z',
                'expires_at': '2026-09-30T12:00:00Z',
              },
              {
                'id': 'sess-other-02',
                'current': false,
                'created_at': '2026-08-25T10:00:00Z',
                'expires_at': '2026-09-25T10:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/auth/account' && request.method == 'DELETE') {
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'content-type': 'application/json'});
    });

    const state = EarthState({
      'human': {
        'id': 'H-12345678',
        'display_name': 'Commander Shepard',
        'email': 'commander@earth.test',
        'standing': 100,
      },
      'life': {
        'houseName': 'House Shepard',
      },
      'institutions': {
        'city': {'name': 'Neo Tokyo'},
      },
    });

    final transport = EarthApiTransport(baseUrl: 'https://earthuc.com', client: client);
    final api = EarthApi(transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountScreen(
              state: state,
              api: api,
              onLogout: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Identity
    expect(find.text('ACCOUNT & SECURITY'), findsOneWidget);
    expect(find.text('Registered Email'), findsOneWidget);
    expect(find.text('commander@earth.test'), findsOneWidget);
    expect(find.text('H-12345678'), findsOneWidget);
    expect(find.text('Commander Shepard'), findsOneWidget);
    expect(find.text('House Shepard'), findsOneWidget);

    // Verify MFA Card
    expect(find.text('MULTI-FACTOR AUTHENTICATION (MFA)'), findsOneWidget);
    expect(find.text('ENABLED'), findsOneWidget);
    expect(find.text('DISABLE MFA'), findsOneWidget);

    // Verify Sessions Card
    expect(find.text('ACTIVE SESSIONS'), findsOneWidget);
    expect(find.text('Current Device'), findsOneWidget);
    expect(find.text('Other Session'), findsOneWidget);

    // Verify Danger Zone
    expect(find.text('DANGER ZONE'), findsOneWidget);
    expect(find.text('DELETE ACCOUNT'), findsOneWidget);
  });
}
