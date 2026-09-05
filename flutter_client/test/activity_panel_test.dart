import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/activity/activity_panel.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  testWidgets('ActivityPanel renders paginated direct alerts and triggers auto-read on mount',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final notifications = List.generate(
      15,
      (i) => {
        'id': 'NOTIF-${i + 1}',
        'title': 'Notification #${i + 1}',
        'body': 'Details for alert #${i + 1}',
        'read': false,
      },
    );

    bool markedAllRead = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityPanel(
              notifications: notifications,
              unreadCount: 15,
              onRefresh: () {},
              onMarkRead: (_) async {},
              onMarkAllRead: () async => markedAllRead = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Auto-read is triggered on mount
    expect(markedAllRead, isTrue);

    // 2. Topic Title without leading icon
    expect(find.text('DIRECT ALERTS & NOTIFICATIONS'), findsOneWidget);
    expect(find.text('EVENT HISTORY & ARCHIVE'), findsNothing);
    expect(find.text('PLANETARY TELEMETRY & WORLD FEED'), findsNothing);

    // 3. Pagination: Page 1 shows items 1-10
    expect(find.text('Notification #1'), findsOneWidget);
    expect(find.text('Notification #10'), findsOneWidget);
    expect(find.text('Notification #11'), findsNothing);
    expect(find.text('PAGE 1 OF 2 (15 TOTAL)'), findsOneWidget);

    // 4. No manual MARK READ or MARK ALL AS READ buttons
    expect(find.text('MARK ALL AS READ'), findsNothing);
    expect(find.text('MARK READ'), findsNothing);

    // 5. Navigate to Page 2
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE 2 OF 2 (15 TOTAL)'), findsOneWidget);
    expect(find.text('Notification #11'), findsOneWidget);
    expect(find.text('Notification #15'), findsOneWidget);
    expect(find.text('Notification #1'), findsNothing);

    // 6. Navigate back to Page 1
    await tester.tap(find.text('PREVIOUS'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 1 OF 2 (15 TOTAL)'), findsOneWidget);
    expect(find.text('Notification #1'), findsOneWidget);
  });

  testWidgets('ActivityPanel handles read_at database format and formats game date time',
      (tester) async {
    final notifications = <Map<dynamic, dynamic>>[
      {
        'id': 'NOTIF-PG-1',
        'title': 'Tax Settlement Invoice',
        'body': '250 Credits settled.',
        'created_at': '2026-08-20T10:00:00Z',
        'read_at': null,
      },
      {
        'id': 'NOTIF-PG-2',
        'title': 'Contract Accepted',
        'body': 'Solar grid maintenance agreement.',
        'created_at': '2026-08-19T10:00:00Z',
        'read_at': '2026-08-20T10:00:00Z',
      },
    ];

    bool markedAllRead = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityPanel(
              notifications: notifications,
              onRefresh: () {},
              onMarkRead: (_) async {},
              onMarkAllRead: () async => markedAllRead = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(markedAllRead, isTrue);
    expect(find.text('DIRECT ALERTS & NOTIFICATIONS'), findsOneWidget);
    final expectedDate = formatRealToGameDateTime('2026-08-20T10:00:00Z');
    expect(find.text(expectedDate), findsOneWidget);
  });

  testWidgets('ActivityPanel renders styled close button and triggers onClose',
      (tester) async {
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityPanel(
            notifications: const [
              {
                'id': 'NOTIF-1',
                'title': 'Test alert',
                'body': 'Alert text',
                'read': false,
              }
            ],
            onRefresh: () {},
            onMarkRead: (_) async {},
            onMarkAllRead: () async {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('CLOSE'), findsOneWidget);
    final closeButtonFinder = find.byKey(const ValueKey('notifications_close_button'));
    expect(closeButtonFinder, findsOneWidget);

    await tester.tap(closeButtonFinder);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('ActivityPanel renders styled close button even when empty',
      (tester) async {
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityPanel(
            notifications: const [],
            onRefresh: () {},
            onMarkRead: (_) async {},
            onMarkAllRead: () async {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('CLOSE'), findsOneWidget);
    final closeButtonFinder = find.byKey(const ValueKey('notifications_close_button'));
    expect(closeButtonFinder, findsOneWidget);

    await tester.tap(closeButtonFinder);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
