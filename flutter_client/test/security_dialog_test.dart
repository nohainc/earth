import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/features/auth/security_dialog.dart';

void main() {
  late EarthApi api;

  setUp(() {
    final client = MockClient((request) async {
      if (request.url.path.contains('/enroll')) {
        return http.Response(
          jsonEncode({'ok': true, 'secret': 'JBSWY3DPEHPK3PXP'}),
          200,
          headers: {'x-earth-api-version': '2026-08', 'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('/sessions')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'sessions': [
              {
                'id': 'sess-current',
                'current': true,
                'created_at': '2026-08-16T12:00:00.000Z',
                'expires_at': '2026-08-23T12:00:00.000Z',
              },
              {
                'id': 'sess-other',
                'current': false,
                'created_at': '2026-08-15T12:00:00.000Z',
                'expires_at': '2026-08-22T12:00:00.000Z',
              }
            ],
          }),
          200,
          headers: {'x-earth-api-version': '2026-08', 'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'x-earth-api-version': '2026-08', 'content-type': 'application/json'},
      );
    });

    final transport = EarthApiTransport(baseUrl: 'https://earthuc.com', client: client);
    api = EarthApi(transport: transport);
  });

  testWidgets('showMfaDialog displays secret and submits confirmation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showMfaDialog(context, api),
              child: const Text('Open MFA'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open MFA'));
    await tester.pumpAndSettle();

    expect(find.text('Enable authenticator MFA'), findsOneWidget);
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Authenticator code'), '654321');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
  });

  testWidgets('showDisableMfaDialog prompts for verification code and disables MFA',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDisableMfaDialog(context, api),
              child: const Text('Disable MFA'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Disable MFA'));
    await tester.pumpAndSettle();

    expect(find.text('Disable authenticator MFA'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Current six-digit code'), '123456');
    await tester.pumpAndSettle();

    await tester.tap(find.text('DISABLE'));
    await tester.pumpAndSettle();
  });

  testWidgets('showSecurityDialog displays session list and enables revoking',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSecurityDialog(context, api, () {}),
              child: const Text('Open Security Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Security Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Account security'), findsOneWidget);
    expect(find.text('Active sessions'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Other session'), findsOneWidget);

    final revokeOther = find.byTooltip('Revoke session');
    expect(revokeOther, findsOneWidget);
    await tester.tap(revokeOther);
    await tester.pumpAndSettle();

    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
  });
}
