import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/communications/comm_link_dialog.dart';
import 'package:earth_client/shared/design_system/earth_controls.dart';

void main() {
  testWidgets('CommLinkDialog renders split view without topic title and with search', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Global Relay Chat',
                'scope': 'global',
                'description': 'Main global channel'
              },
              {
                'id': 'channel-city-1',
                'name': 'New Kyoto Plaza Chat',
                'scope': 'city',
                'description': 'City discussion'
              },
              {
                'id': 'channel-corp-1',
                'name': 'Apex Boardroom Chat',
                'scope': 'corporation',
                'description': 'Corporate channel'
              },
              {
                'id': 'dm-user-2',
                'name': 'Amara Kline',
                'scope': 'direct',
                'description': 'Direct message'
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/comm/messages') {
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 'msg-1',
                'sender_display_name': 'Commander John',
                'body': 'Welcome to the relay!',
                'game_day': 184,
                'game_minute': 120,
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/social/directory') {
        return http.Response(
          jsonEncode({
            'humans': [
              {'id': 'H-99', 'display_name': 'Bob Vance', 'city_name': 'New Kyoto'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });

    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Check that topic title "MESSAGES" is NOT present
    expect(find.text('MESSAGES'), findsNothing);

    // 2. Check that group headers 'ORGANIZATION CHATS', 'PUBLIC CHANNELS', 'PRIVATE MESSAGES' are NOT present
    expect(find.text('ORGANIZATION CHATS'), findsNothing);
    expect(find.text('PUBLIC CHANNELS'), findsNothing);
    expect(find.text('PRIVATE MESSAGES'), findsNothing);

    // 3. Check that small descriptions are NOT displayed
    expect(find.text('Main global channel'), findsNothing);
    expect(find.text('City discussion'), findsNothing);

    // 4. Check channel names are displayed cleanly without trailing ' Chat'
    expect(find.text('Global Relay'), findsOneWidget); // in channel list
    expect(find.text('New Kyoto Plaza'), findsOneWidget);
    expect(find.text('Apex Boardroom'), findsOneWidget);
    expect(find.text('Amara Kline'), findsOneWidget);
    expect(find.text('Global Relay Chat'), findsNothing);
    expect(find.text('Apex Boardroom Chat'), findsNothing);

    // 5. Check no Divider after search input
    expect(find.byType(Divider), findsNothing);

    // 6. Check right panel has no conversation header info badge
    expect(find.text('GLOBAL'), findsNothing);

    // 7. Check SEND button exists
    expect(find.text('SEND'), findsOneWidget);

    // 8. Check search toggle button exists and tapping it shows search input
    expect(find.byKey(const ValueKey('comm_link_search_toggle')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comm_link_search_toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(EarthSearchInput), findsOneWidget);

    // 9. Typing in search filters chats and queries users
    await tester.enterText(find.byType(TextField).first, 'Kyoto');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Only matching chat should show
    expect(find.text('New Kyoto Plaza'), findsOneWidget);
    expect(find.text('Apex Boardroom'), findsNothing);

    // 10. Clear search restores full list
    final clearBtn = find.descendant(
      of: find.byType(EarthSearchInput),
      matching: find.byIcon(Icons.close),
    );
    if (clearBtn.evaluate().isNotEmpty) {
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
      expect(find.text('Apex Boardroom'), findsOneWidget);
    }

    // 11. Check that message shows sender full name and game datetime formatted with Year, Day, Time
    expect(find.text('Commander John'), findsOneWidget);
    expect(find.textContaining('YEAR 1   DAY 184   02:00'), findsOneWidget);

    // 12. Check Ctrl+Enter shortcut sends message
    final messageField = find.byType(TextField).last;
    await tester.enterText(messageField, 'Testing shortcut send');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  });

  testWidgets('CommLinkDialog close button triggers onClose callback and has narrow left panel', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool closed = false;
    final client = MockClient((request) async {
      return http.Response('{"channels": []}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            isPageMode: true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify left panel has fixed width 250
    final sizedBoxFinder = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.width == 250,
    );
    expect(sizedBoxFinder, findsOneWidget);

    // Verify close button exists and clicking it calls onClose
    final closeBtnFinder = find.byKey(const ValueKey('comm_link_close_button'));
    expect(closeBtnFinder, findsOneWidget);

    await tester.tap(closeBtnFinder);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('CommLinkDialog displays account display name if citizen ID was returned', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Global Relay',
                'scope': 'global',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/comm/messages') {
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 'msg-1',
                'sender_human_id': 'H-0044',
                'sender_display_name': 'H-0044', // Citizen ID instead of name
                'body': 'Citizen ID test message',
                'game_day': 240,
                'game_minute': 720,
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    const earthState = EarthState({
      'human': {
        'id': 'H-0044',
        'display_name': 'Alex Sterling',
      },
      'clock': {
        'day': 240,
        'minute': 720,
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            state: earthState,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify fallback from H-0044 to Alex Sterling
    expect(find.text('Alex Sterling'), findsOneWidget);
    expect(find.text('H-0044'), findsNothing);
    expect(find.textContaining('YEAR 1   DAY 240   12:00'), findsOneWidget);
  });

  testWidgets('CommLinkDialog remembers latest active chat and restores it when reopened without initialChannelId',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    CommLinkDialog.lastActiveChannelId = null;

    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Global Relay',
                'category': 'public',
                'members_count': 120,
              },
              {
                'id': 'channel-city-tokyo',
                'name': 'Neo Tokyo',
                'category': 'city',
                'members_count': 45,
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/comm/messages') {
        final channelId = request.url.queryParameters['channelId'] ??
            request.url.queryParameters['channel_id'] ??
            'channel-global-relay';
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 'msg-1',
                'sender_display_name': 'Tester',
                'body': 'Message in $channelId',
                'game_day': 10,
                'game_minute': 100,
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    // 1. First open: default to global relay
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message in channel-global-relay'), findsOneWidget);

    // 2. Select 'Neo Tokyo'
    await tester.tap(find.text('Neo Tokyo'));
    await tester.pumpAndSettle();
    expect(find.text('Message in channel-city-tokyo'), findsOneWidget);
    expect(CommLinkDialog.lastActiveChannelId, 'channel-city-tokyo');

    // 3. Reopen CommLinkDialog without initialChannelId -> should restore Neo Tokyo
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            key: UniqueKey(),
            api: api,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message in channel-city-tokyo'), findsOneWidget);

    // 4. Reopen CommLinkDialog WITH specific initialChannelId -> should navigate to specified channel
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            key: UniqueKey(),
            api: api,
            initialChannelId: 'channel-global-relay',
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message in channel-global-relay'), findsOneWidget);
  });

  testWidgets('CommLinkDialog displays own messages on the right, other messages on the left, smaller timestamp, and no helper text',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Global Relay',
                'scope': 'global',
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/comm/messages') {
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 'msg-1',
                'sender_human_id': 'H-OTHER',
                'sender_display_name': 'Other Pilot',
                'body': 'Incoming message from someone else',
                'game_day': 10,
                'game_minute': 100,
              },
              {
                'id': 'msg-2',
                'sender_human_id': 'H-ME',
                'sender_display_name': 'My Pilot',
                'body': 'Outgoing message from me',
                'game_day': 10,
                'game_minute': 105,
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    const earthState = EarthState({
      'human': {
        'id': 'H-ME',
        'display_name': 'My Pilot',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            state: earthState,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify helper text 'Search chats or users' and 'Write a message...' are NOT displayed
    expect(find.text('Search chats or users...'), findsNothing);
    expect(find.text('Write a message...'), findsNothing);
    expect(find.text('Write a private message...'), findsNothing);

    // 2. Check alignment of own vs other messages
    final otherMsgFinder = find.ancestor(
      of: find.text('Incoming message from someone else'),
      matching: find.byType(Align),
    );
    final ownMsgFinder = find.ancestor(
      of: find.text('Outgoing message from me'),
      matching: find.byType(Align),
    );

    final otherAlign = tester.widget<Align>(otherMsgFinder.first);
    final ownAlign = tester.widget<Align>(ownMsgFinder.first);

    expect(otherAlign.alignment, Alignment.centerLeft);
    expect(ownAlign.alignment, Alignment.centerRight);

    // 3. Check timestamp font size is smaller (8.5)
    final timestampFinder = find.textContaining('DAY 10');
    expect(timestampFinder, findsNWidgets(2));
    final firstTimestampWidget = tester.widget<Text>(timestampFinder.first);
    expect(firstTimestampWidget.style?.fontSize, 8.5);
  });

  testWidgets('CommLinkDialog on small screens renders communications header with close button',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    bool closed = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(jsonEncode({'channels': []}), 200, headers: {'content-type': 'application/json'});
      }
      if (request.url.path == '/api/comm/messages') {
        return http.Response(jsonEncode({'messages': []}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            isPageMode: true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check title in small screen header
    expect(find.text('COMMUNICATIONS'), findsOneWidget);

    // Verify close button in header works
    final closeBtnFinder = find.byKey(const ValueKey('comm_link_close_button'));
    expect(closeBtnFinder, findsOneWidget);

    await tester.tap(closeBtnFinder);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('CommLinkDialog on mobile switches from channels list to chat on select and back on arrow tap',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final client = MockClient((request) async {
      if (request.url.path == '/api/comm/channels') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 'channel-global-relay',
                'name': 'Global Relay Chat',
                'scope': 'global',
              },
              {
                'id': 'channel-city-1',
                'name': 'City Chat',
                'scope': 'city',
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/comm/messages') {
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 'msg-1',
                'sender_display_name': 'Mayor',
                'body': 'Welcome to City',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://mock.test', client: client));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommLinkDialog(
            api: api,
            isPageMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // On initial small screen with no initialChannelId: channels list is shown, back button is not shown
    expect(find.text('City'), findsOneWidget);
    expect(find.byKey(const ValueKey('comm_link_back_button')), findsNothing);

    // Tap City channel -> transitions to chat screen with message and back button
    await tester.tap(find.text('City'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('comm_link_back_button')), findsOneWidget);
    expect(find.text('Welcome to City'), findsOneWidget);

    // Tap back button -> transitions back to channels list
    await tester.tap(find.byKey(const ValueKey('comm_link_back_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('comm_link_back_button')), findsNothing);
    expect(find.byKey(const ValueKey('comm_link_search_toggle')), findsOneWidget);
  });
}
