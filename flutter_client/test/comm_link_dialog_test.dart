import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/communications/comm_link_dialog.dart';

void main() {
  testWidgets('CommLinkDialog renders channels, messages, sends text, and switches to dispatches',
      (tester) async {
    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/comm/channels') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'channels': [
              {
                'id': 'channel-global-relay',
                'scope': 'global',
                'name': 'Planetary Public Relay',
                'description': 'Universal broadcast frequency',
              },
              {
                'id': 'channel-city-new-tokyo',
                'scope': 'city',
                'name': 'Neo-Tokyo City Hall',
                'description': 'Municipal forum for Neo-Tokyo',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/comm/messages') {
        if (request.method == 'POST') {
          return http.Response(
            NanoMarkupHelper.encode({
              'ok': true,
              'message': {
                'id': 'msg-999',
                'channel_id': 'channel-global-relay',
                'sender_human_id': 'H-0044',
                'sender_display_name': 'Amara Vance',
                'sender_dynasty_name': 'Vance Dynasty',
                'body': 'Test broadcast message',
                'game_day': 184,
                'game_minute': 500,
                'attachments': [],
                'created_at': DateTime.now().toIso8601String(),
              },
            }),
            200,
            headers: {'content-type': 'application/nanomarkup'},
          );
        }
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'messages': [
              {
                'id': 'msg-1',
                'channel_id': 'channel-global-relay',
                'sender_human_id': 'H-0012',
                'sender_display_name': 'Dmitri Rostov',
                'sender_dynasty_name': 'House of Rostov',
                'body': 'Silicon demand has spiked in London.',
                'game_day': 184,
                'game_minute': 420,
                'attachments': [],
                'created_at': DateTime.now().toIso8601String(),
              },
            ],
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
                'id': 'mail-999',
                'sender_human_id': 'H-0044',
                'recipient_human_id': 'H-0012',
                'subject': 'Trade Agreement Accepted',
                'body': 'Terms confirmed.',
                'status': 'unread',
              },
            }),
            200,
            headers: {'content-type': 'application/nanomarkup'},
          );
        }
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'dispatches': [
              {
                'id': 'mail-1',
                'sender_human_id': 'H-0012',
                'sender_display_name': 'Dmitri Rostov',
                'recipient_human_id': 'H-0044',
                'subject': 'Tender Offer & Supply Contract',
                'body': 'We are seeking to secure long-term rights to 250 units.',
                'status': 'unread',
                'game_day': 184,
                'game_minute': 510,
                'dispatch_type': 'contract_offer',
                'action_payload': {'contractId': 'CTR-904', 'creditsOffered': 1500},
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
      transport: EarthApiTransport(baseUrl: 'http://127.0.0.1:8899', client: mockClient),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(api: api),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Top Header & Mode Tabs
    expect(find.text('UNIVERSAL COMM-LINK / SUB-SPACE RELAY'), findsOneWidget);
    expect(find.text('CHANNELS'), findsOneWidget);
    expect(find.text('DISPATCHES'), findsOneWidget);

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

    // 5. Switch Mode to DISPATCHES
    await tester.tap(find.text('DISPATCHES'));
    await tester.pumpAndSettle();

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

    expect(find.text('TRANSMIT DIPLOMATIC DISPATCH'), findsOneWidget);

    // Fill Compose Form
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'H-0012');
    await tester.enterText(textFields.at(1), 'Agreement Confirmation');
    await tester.enterText(textFields.at(2), 'We accept your terms.');

    // Transmit
    await tester.tap(find.text('TRANSMIT DISPATCH'));
    await tester.pumpAndSettle();
  });
}
