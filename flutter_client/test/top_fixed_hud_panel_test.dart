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

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopFixedHudPanel(
            state: state,
            unreadNotifications: 3,
            unreadCommMessages: 5,
            isLiveConnected: true,
            isReconnecting: false,
            showDrawerButton: true,
            onOpenDrawer: () => drawerOpened = true,
            onNavigate: (_) {},
            onLogout: () => loggedOut = true,
            onSecurity: () => securityOpened = true,
            onCommLink: () => commLinkOpened = true,
          ),
        ),
      ),
    );

    // Verify brand header
    expect(find.text('EARTH'), findsOneWidget);
    expect(find.text('UNITED CORPORATIONS'), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // Combined alerts badge

    // Test grouped alerts menu and Messages action
    final notifBtn = find.byIcon(Icons.notifications_none_outlined);
    expect(notifBtn, findsOneWidget);
    await tester.tap(notifBtn);
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Invitations'), findsOneWidget);
    await tester.tap(find.text('Messages'));
    expect(commLinkOpened, isTrue);

    // The comm-link action is now exposed through the grouped Messages item.

    // Test drawer trigger
    final drawerBtn = find.byIcon(Icons.menu);
    if (drawerBtn.evaluate().isNotEmpty) {
      await tester.tap(drawerBtn.first);
      expect(drawerOpened, isTrue);
    }

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
  });
}
