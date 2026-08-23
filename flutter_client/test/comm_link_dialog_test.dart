import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/communications/comm_link_dialog.dart';

void main() {
  testWidgets(
      'CommLinkDialog renders channels and dispatches as separate stacked topics',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/comm/channels') {
        return http.Response(
          NanoMarkupHelper.encode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Planetary Public Relay',
                'scope': 'global',
                'description': 'Universal sub-space broadcast channel',
                'active_participants': 1420,
              },
              {
                'id': 'channel-city-tokyo',
                'name': 'Neo-Tokyo City Hall',
                'scope': 'city',
                'city_id': 'city-tokyo-01',
                'description': 'Official municipal communications',
                'active_participants': 89,
              },
            ],
            'frequencies': ['142.8 GHz', '84.2 GHz'],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/comm/messages' && request.method == 'GET') {
        return http.Response(
          NanoMarkupHelper.encode({
            'messages': [
              {
                'id': 'msg-101',
                'sender_human_id': 'H-0042',
                'sender_display_name': 'Dmitri Rostov',
                'sender_role': 'Commodity Broker',
                'body': 'Silicon demand has spiked in London.',
                'timestamp': '07:14:02',
                'game_day': 184,
                'is_verified': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/comm/messages' && request.method == 'POST') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'message': {
              'id': 'msg-102',
              'sender_human_id': 'H-0001',
              'sender_display_name': 'Executive Commander',
              'sender_role': 'Enterprise Founder',
              'body': 'Test broadcast message',
              'timestamp': '07:15:00',
              'game_day': 184,
              'is_verified': true,
            },
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/comm/dispatches') {
        if (request.method == 'POST') {
          return http.Response(
            NanoMarkupHelper.encode({
              'ok': true,
              'dispatch': {
                'id': 'dsp-202',
                'sender_id': 'H-0001',
                'recipient_id': 'H-0012',
                'subject': 'Agreement Confirmation',
                'content': 'We accept your terms.',
                'status': 'sent',
                'dispatch_type': 'diplomatic',
                'created_at': '2026-08-20T08:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/nanomarkup'},
          );
        }

        return http.Response(
          NanoMarkupHelper.encode({
            'dispatches': [
              {
                'id': 'dsp-201',
                'sender_id': 'H-0088',
                'sender_name': 'Ambassador Vance',
                'recipient_id': 'H-0001',
                'subject': 'Tender Offer & Supply Contract',
                'summary': 'Proposed bilateral energy distribution contract for 1,500 Credits.',
                'body': 'Dear Executive, Vance Logistics hereby extends an official tender offer.',
                'status': 'unread',
                'dispatch_type': 'contract_offer',
                'created_at': '2026-08-20T06:30:00Z',
                'has_actionable_contract': true,
                'action_payload': {
                  'contractId': 'CTR-904',
                  'creditsOffered': 1500
                },
              },
            ],
            'unreadCount': 1,
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/comm/dispatches/read') {
        return http.Response(
          NanoMarkupHelper.encode({'ok': true, 'read': true}),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      return http.Response('{}', 404);
    });

    final api = EarthApi(
      transport: EarthApiTransport(
          baseUrl: 'http://127.0.0.1:8899', client: mockClient),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommLinkDialog(api: api, isPageMode: true),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Two Distinct Topics
    expect(find.text('CHANNELS'), findsOneWidget);
    expect(find.text('DIPLOMATIC DISPATCHES'), findsOneWidget);
    expect(find.text('UNIVERSAL COMM-LINK / SUB-SPACE RELAY'), findsNothing);
    expect(find.text('RELAY STATUS'), findsNothing);
    expect(find.text('SUB-SPACE CLOCK'), findsNothing);

    // 2. Verify Channels List & Initial Message
    expect(find.text('Planetary Public Relay'), findsWidgets);
    expect(find.text('Silicon demand has spiked in London.'), findsOneWidget);
    expect(find.text('Dmitri Rostov'), findsWidgets);

    // 3. Switch Channel to Neo-Tokyo City Hall
    final cityChannel = find.text('Neo-Tokyo City Hall');
    await tester.ensureVisible(cityChannel);
    await tester.tap(cityChannel);
    await tester.pumpAndSettle();

    // 4. Transmit a Message in the Channel
    final msgInput = find.byType(TextField).first;
    await tester.enterText(msgInput, 'Hello Neo-Tokyo citizens!');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Test broadcast message'), findsOneWidget);

    // 5. Verify Dispatches topic is immediately present on the page
    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('SENT'), findsOneWidget);
    expect(find.text('COMPOSE'), findsOneWidget);
    expect(find.text('Tender Offer & Supply Contract'), findsOneWidget);

    // 6. Open the Unread Dispatch
    final mailRow = find.text('Tender Offer & Supply Contract');
    await tester.tap(mailRow);
    await tester.pumpAndSettle();

    expect(find.text('ATTACHED FORMAL TERMS'), findsOneWidget);
    expect(find.text('REVIEW TERMS'), findsOneWidget);

    // 7. Switch to Compose Form
    await tester.tap(find.text('COMPOSE'));
    await tester.pumpAndSettle();

    expect(find.text('SEND DIPLOMATIC DISPATCH'), findsOneWidget);

    // Fill Compose Form
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(1), 'H-0012');
    await tester.enterText(textFields.at(2), 'Agreement Confirmation');
    await tester.enterText(textFields.at(3), 'We accept your terms.');

    // Send
    await tester.tap(find.text('SEND DISPATCH'));
    await tester.pumpAndSettle();
  });
}
