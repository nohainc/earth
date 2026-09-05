import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/top_fixed_hud_panel.dart';

void main() {
  test('YearAndDay model properties', () {
    const y = YearAndDay(2, 45);
    expect(y.year, 2);
    expect(y.dayOfYear, 45);
  });

  testWidgets(
      'TopFixedHudPanel renders brand header, live status, and triggers callbacks',
      (tester) async {
    const state = EarthState({
      'clock': {
        'day': 184,
        'minute': 720,
        'serverCurrentTime': 1771412400000,
      },
      'human': {
        'id': 'H-0044',
        'display_name': 'Amara Kline',
        'name': 'Amara Kline',
        'credits': 18420,
        'standing': 742,
      },
      'world': {'health': 100},
      'resources': {
        'food': 120,
        'energy': 340,
        'material': 560,
        'compute': 80,
      },
      'business': {},
      'technology': {'research': {}},
      'institutions': {
        'city': {'name': 'New Kyoto'},
      },
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool drawerOpened = false;
    bool loggedOut = false;
    bool securityOpened = false;
    bool commLinkOpened = false;
    bool notificationsOpened = false;

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 1. Desktop mode (showDrawerButton: false) -> displays EARTH and UNITED CORPORATIONS and telemetry
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopFixedHudPanel(
            state: state,
            unreadNotifications: 3,
            unreadCommMessages: 5,
            isLiveConnected: true,
            isReconnecting: false,
            showDrawerButton: false,
            onOpenDrawer: () => drawerOpened = true,
            onNavigate: (_) {},
            onLogout: () => loggedOut = true,
            onSecurity: () => securityOpened = true,
            onCommLink: () => commLinkOpened = true,
            onNotifications: () => notificationsOpened = true,
          ),
        ),
      ),
    );

    // Verify brand header text and telemetry in desktop mode
    expect(find.text('EARTH'), findsOneWidget);
    expect(find.text('UNITED CORPORATIONS'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);

    // Verify separate badges for Notifications (3) and Comm Messages (5)
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    // Test Notifications button (opens popup menu)
    final notifBtn = find.byIcon(Icons.notifications_active_outlined);
    expect(notifBtn, findsOneWidget);
    await tester.tap(notifBtn);
    await tester.pumpAndSettle();
    expect(find.text('VIEW ALL NOTIFICATIONS'), findsOneWidget);
    await tester.tap(find.text('VIEW ALL NOTIFICATIONS'));
    await tester.pumpAndSettle();
    expect(notificationsOpened, isTrue);

    // Test Messages button
    final messagesBtn = find.byIcon(Icons.forum_outlined);
    expect(messagesBtn, findsOneWidget);
    await tester.tap(messagesBtn);
    await tester.pumpAndSettle();
    expect(commLinkOpened, isTrue);

    // Test security trigger
    final securityBtn = find.byIcon(Icons.shield_outlined);
    if (securityBtn.evaluate().isNotEmpty) {
      await tester.tap(securityBtn.first);
      expect(securityOpened, isTrue);
    }

    // Test logout trigger
    final logoutBtn = find.byIcon(Icons.logout_rounded);
    if (logoutBtn.evaluate().isNotEmpty) {
      await tester.tap(logoutBtn.first);
      expect(loggedOut, isTrue);
    }

    // 2. Mobile / collapsed sidebar mode (showDrawerButton: true) -> shows hamburger menu on left, hides brand text & telemetry
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopFixedHudPanel(
            state: state,
            unreadNotifications: 0,
            unreadCommMessages: 0,
            isLiveConnected: true,
            isReconnecting: false,
            showDrawerButton: true,
            onOpenDrawer: () => drawerOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EARTH'), findsNothing);
    expect(find.text('UNITED CORPORATIONS'), findsNothing);
    expect(find.text('LIVE'), findsNothing);

    final drawerBtn = find.byIcon(Icons.menu_rounded);
    expect(drawerBtn, findsOneWidget);
    await tester.tap(drawerBtn);
    expect(drawerOpened, isTrue);
  });

  testWidgets('TopFixedHudPanel triggers 3-stage rollover lifecycle callbacks',
      (tester) async {
    bool recalculateTriggered = false;
    bool prefetchTriggered = false;
    bool rolloverTriggered = false;

    // Set clock at 23:49:59 (total minute 1429) so 1 second advance hits 23:50:00 (minute 1430)
    final epochStartMs =
        DateTime.utc(2026, 1, 1, 0, 0, 0).millisecondsSinceEpoch;
    final stateAt2349 = EarthState({
      'clock': {
        'day': 1,
        'minute': 1429,
        'serverCurrentTime': epochStartMs + (1429 * 1000),
      },
      'human': {'id': 'H-0044', 'name': 'Commander'},
      'world': {'health': 100},
      'resources': {},
      'institutions': {'city': {'name': 'Neo Tokyo'}},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopFixedHudPanel(
            state: stateAt2349,
            onDayRecalculateTrigger: () => recalculateTriggered = true,
            onDayPrefetch: () => prefetchTriggered = true,
            onDayRollover: () => rolloverTriggered = true,
          ),
        ),
      ),
    );

    // Advance 1 real second -> hits 23:50:00 (minute 1430)
    await tester.pump(const Duration(seconds: 1));
    expect(recalculateTriggered, isTrue);
    expect(prefetchTriggered, isFalse);
    expect(rolloverTriggered, isFalse);

    // Advance 9 real seconds -> hits 23:59:00 (minute 1439)
    await tester.pump(const Duration(seconds: 9));
    expect(prefetchTriggered, isTrue);
    expect(rolloverTriggered, isFalse);

    // Advance 1 real second -> hits 00:00:00 of Day 2 (minute 0)
    await tester.pump(const Duration(seconds: 1));
    expect(rolloverTriggered, isTrue);
  });
}
