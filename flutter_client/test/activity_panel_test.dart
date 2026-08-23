import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/activity/activity_panel.dart';

void main() {
  testWidgets('ActivityPanel renders paginated direct alerts without outer event wrapper or icon',
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

    String? markedReadId;
    bool markedAllRead = false;
    bool refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityPanel(
              notifications: notifications,
              unreadCount: 15,
              onRefresh: () => refreshed = true,
              onMarkRead: (id) async => markedReadId = id,
              onMarkAllRead: () async => markedAllRead = true,
            ),
          ),
        ),
      ),
    );

    // 1. Topic Title without leading icon
    expect(find.text('DIRECT ALERTS & NOTIFICATIONS (15)'), findsOneWidget);
    expect(find.text('EVENT HISTORY & ARCHIVE'), findsNothing);
    expect(find.text('PLANETARY TELEMETRY & WORLD FEED'), findsNothing);

    // 2. Pagination: Page 1 shows items 1-10
    expect(find.text('Notification #1'), findsOneWidget);
    expect(find.text('Notification #10'), findsOneWidget);
    expect(find.text('Notification #11'), findsNothing);
    expect(find.text('PAGE 1 OF 2 (15 TOTAL)'), findsOneWidget);

    // 3. Mark read single item
    await tester.tap(find.byTooltip('Mark read').first);
    await tester.pumpAndSettle();
    expect(markedReadId, 'NOTIF-1');

    // 4. Navigate to Page 2
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE 2 OF 2 (15 TOTAL)'), findsOneWidget);
    expect(find.text('Notification #11'), findsOneWidget);
    expect(find.text('Notification #15'), findsOneWidget);
    expect(find.text('Notification #1'), findsNothing);

    // 5. Navigate back to Page 1
    await tester.tap(find.text('PREVIOUS'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 1 OF 2 (15 TOTAL)'), findsOneWidget);
    expect(find.text('Notification #1'), findsOneWidget);

    // 6. Mark all read
    await tester.tap(find.text('MARK ALL READ'));
    await tester.pumpAndSettle();
    expect(markedAllRead, isTrue);

    // 7. Refresh action
    await tester.tap(find.byTooltip('Refresh alerts'));
    expect(refreshed, isTrue);
  });
}
