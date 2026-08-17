import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/activity/activity_panel.dart';

void main() {
  testWidgets('ActivityPanel renders notifications, unread count, mark read, and live status',
      (tester) async {
    final notifications = [
      {
        'id': 'NOTIF-001',
        'title': 'Tax Assessment Cleared',
        'body': 'Quarterly municipal tax was deducted.',
        'read': false,
      },
      {
        'id': 'NOTIF-002',
        'title': 'Contract Proposed',
        'body': 'New capacity agreement proposed.',
        'read': false,
      },
    ];

    final events = [
      {
        'id': 1,
        'eventKey': 'evt-1',
        'type': 'world.day_advanced',
        'gameDay': 185,
      },
      {
        'id': 2,
        'eventKey': 'evt-2',
        'type': 'market.batch_settled',
        'gameDay': 185,
      },
    ];

    String? markedReadId;
    bool markedAllRead = false;
    bool refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityPanel(
              events: events,
              notifications: notifications,
              unreadCount: 2,
              isLiveConnected: true,
              isReconnecting: false,
              onRefresh: () => refreshed = true,
              onMarkRead: (id) async => markedReadId = id,
              onMarkAllRead: () async => markedAllRead = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('ACTIVITY & NOTIFICATIONS CENTER'), findsOneWidget);
    expect(find.text('LIVE STREAM ACTIVE'), findsOneWidget);
    expect(find.text('ALERTS (2)'), findsOneWidget);
    expect(find.text('Tax Assessment Cleared'), findsOneWidget);
    expect(find.text('Contract Proposed'), findsOneWidget);
    expect(find.text('MARK ALL READ'), findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Real-Time Operations Telemetry'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Tap mark read icon for NOTIF-001
    await tester.tap(find.byTooltip('Mark read').first);
    await tester.pumpAndSettle();
    expect(markedReadId, 'NOTIF-001');

    // Tap mark all read
    await tester.tap(find.text('MARK ALL READ'));
    await tester.pumpAndSettle();
    expect(markedAllRead, isTrue);

    // Switch to Public Activity tab
    await tester.tap(find.text('PUBLIC FEED'));
    await tester.pumpAndSettle();

    expect(find.textContaining('World simulation cycle advanced to Game Day 185'), findsOneWidget);
    expect(find.textContaining('Central Market batch cleared and settled'), findsOneWidget);

    // Refresh icon
    await tester.tap(find.byTooltip('Refresh events & notifications'));
    expect(refreshed, isTrue);
  });
}
