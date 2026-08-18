import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/auth/reincarnation_dialog.dart';

void main() {
  testWidgets('ReincarnationDialog renders eulogy and triggers rebirth flow',
      (tester) async {
    bool rebirthCalled = false;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/auth/rebirth') {
        rebirthCalled = true;
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'reborn': true,
            'human': {
              'id': 'H-NEW-01',
              'display_name': 'Marcus Vance II',
              'life_status': 'active',
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
    Map<String, dynamic>? rebornResult;

    final deceased = {
      'id': 'H-0044',
      'display_name': 'Founder Marcus Vance',
      'legacy': 4500,
      'standing': 980,
      'life_status': 'deceased',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReincarnationDialog(
            deceasedHuman: deceased,
            api: api,
            onReborn: (res) => rebornResult = res,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Eulogy & Inscriptions
    expect(find.text('MORTALITY & DYNASTIC SUCCESSION'), findsOneWidget);
    expect(find.textContaining('The life journey of Founder Marcus Vance'),
        findsOneWidget);
    expect(find.textContaining('Lifetime Legacy: 4500'), findsOneWidget);
    expect(find.textContaining('Final Standing: 980'), findsOneWidget);

    // Enter New Character Name
    final nameField = find.widgetWithText(TextField, 'New Character Display Name');
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Marcus Vance II');
    await tester.pumpAndSettle();

    // Submit Rebirth
    final rebirthBtn = find.text('PAY 500 C NATURALIZATION FEE & REBIRTH');
    expect(rebirthBtn, findsOneWidget);
    await tester.ensureVisible(rebirthBtn);
    await tester.pumpAndSettle();
    await tester.tap(rebirthBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(rebirthCalled, isTrue);
    expect(rebornResult?['reborn']?.toString(), 'true');
  });

  testWidgets('ReincarnationDialog triggers claim heir flow',
      (tester) async {
    bool claimHeirCalled = false;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/auth/claim-heir') {
        claimHeirCalled = true;
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'claimed': true,
            'human': {
              'id': 'H-HEIR-02',
              'display_name': 'Marcus Vance II',
              'life_status': 'active',
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
    Map<String, dynamic>? rebornResult;

    final deceased = {
      'id': 'H-0044',
      'display_name': 'Founder Marcus Vance',
      'legacy': 4500,
      'standing': 980,
      'life_status': 'deceased',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReincarnationDialog(
            deceasedHuman: deceased,
            api: api,
            onReborn: (res) => rebornResult = res,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Claim Heir
    final claimBtn = find.text('CLAIM HEIR');
    expect(claimBtn, findsOneWidget);
    await tester.ensureVisible(claimBtn);
    await tester.pumpAndSettle();
    await tester.tap(claimBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(claimHeirCalled, isTrue);
    expect(rebornResult?['claimed']?.toString(), 'true');
  });
}
