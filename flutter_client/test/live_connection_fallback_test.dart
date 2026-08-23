import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/models/live_connection_status.dart';
import 'package:earth_client/features/command_center/top_fixed_hud_panel.dart';
import 'package:earth_client/features/activity/activity_panel.dart';
import 'package:earth_client/features/command_center/command_center_screen.dart';

void main() {
  final testState = EarthState(
    {
      'human': {'name': 'Commander Kira', 'credits': 150000},
      'resources': {
        'food': 500,
        'materials': 300,
        'components': 120,
        'energy': 400,
        'compute': 80
      },
      'institutions': {
        'city': {'name': 'Neo-Veridia'}
      },
      'business': {'id': 'biz-1', 'name': 'Kira Dynamics'},
      'clock': {
        'serverCurrentTime': DateTime.utc(2026, 8, 18).millisecondsSinceEpoch
      },
    },
  );

  group('LiveConnectionStatus model & extensions', () {
    test('verifies all 4 connection states have distinct properties', () {
      for (final status in LiveConnectionStatus.values) {
        expect(status.label, isNotEmpty);
        expect(status.shortLabel, isNotEmpty);
        expect(status.description, isNotEmpty);
        expect(status.color, isNotNull);
        expect(status.icon, isNotNull);
      }

      expect(LiveConnectionStatus.live.shortLabel, 'LIVE');
      expect(LiveConnectionStatus.reconnecting.shortLabel, 'RETRY');
      expect(LiveConnectionStatus.polling.shortLabel, 'POLL');
      expect(LiveConnectionStatus.offline.shortLabel, 'OFFLINE');

      expect(LiveConnectionStatus.polling.description, contains('delayed'));
      expect(LiveConnectionStatus.offline.description, contains('cached'));
    });
  });

  group('TopFixedHudPanel live connection status indicator', () {
    testWidgets('renders LIVE status pill and responds to tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopFixedHudPanel(
              state: testState,
              connectionStatus: LiveConnectionStatus.live,
            ),
          ),
        ),
      );

      expect(find.text(LiveConnectionStatus.live.shortLabel), findsOneWidget);
    });

    testWidgets('renders POLLING status pill when in fallback mode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopFixedHudPanel(
              state: testState,
              connectionStatus: LiveConnectionStatus.polling,
            ),
          ),
        ),
      );

      expect(find.text(LiveConnectionStatus.polling.shortLabel), findsOneWidget);
    });

    testWidgets('renders OFFLINE status pill when disconnected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopFixedHudPanel(
              state: testState,
              connectionStatus: LiveConnectionStatus.offline,
            ),
          ),
        ),
      );

      expect(find.text(LiveConnectionStatus.offline.shortLabel), findsOneWidget);
    });
  });

  group('ActivityPanel keeps connection status out of the workspace', () {
    testWidgets('shows the activity stream frame and refresh action',
        (tester) async {
      var refreshed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActivityPanel(
                events: const [],
                notifications: const [],
                connectionStatus: LiveConnectionStatus.polling,
                onRefresh: () => refreshed = true,
                onMarkRead: (_) async {},
                onMarkAllRead: () async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('DIRECT ALERTS & NOTIFICATIONS'), findsOneWidget);
      expect(find.text('POLLING MODE (PERIODIC SYNC)'), findsNothing);

      await tester.tap(find.byTooltip('Refresh alerts'));
      expect(refreshed, isTrue);
    });

    testWidgets('does not show an offline banner inside Activity',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActivityPanel(
                events: const [],
                notifications: const [],
                connectionStatus: LiveConnectionStatus.offline,
                onRefresh: () {},
                onMarkRead: (_) async {},
                onMarkAllRead: () async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('OFFLINE / STALE DATA'), findsNothing);
      expect(find.textContaining('cached simulation snapshot'), findsNothing);
    });
  });

  group('CommandCenter handleLiveMessage and connection states', () {
    testWidgets('handleLiveMessage ignores malformed and duplicate messages',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommandCenter(onLogout: () {}),
        ),
      );

      final state = tester.state(find.byType(CommandCenter)) as dynamic;
      expect(state.handleLiveMessage(null), isFalse);
      expect(
          state.handleLiveMessage('{"eventKey":"evt-1","type":"world_tick"}'),
          isTrue);
      // Duplicate should return false
      expect(
          state.handleLiveMessage('{"eventKey":"evt-1","type":"world_tick"}'),
          isFalse);
    });
  });
}
