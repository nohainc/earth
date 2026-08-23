import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/models/live_connection_status.dart';
import 'package:earth_client/shared/design_system/earth_logo.dart';
import 'package:earth_client/features/command_center/top_fixed_hud_panel.dart';

void main() {
  group('Tier 2: Visual Snapshot & Responsive Theme Contracts', () {
    testWidgets('EarthLogo renders across various scales and glowing states', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: createEarthTheme(EarthThemeMode.solarGold),
          home: const Scaffold(
            body: Center(
              child: Row(
                children: [
                  EarthLogo(size: 28, showGlow: false),
                  EarthLogo(size: 48, showGlow: true),
                  EarthLogo(size: 80, showGlow: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EarthLogo), findsNWidgets(3));
    });

    testWidgets('TopFixedHudPanel renders responsively on Desktop (1440x900) and Mobile (375x812)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      const state = EarthState({
        'clock': {'day': 185, 'minute': 640},
        'resources': {
          'credits': 85400.0,
          'energy': 1250.0,
          'food': 3400.0,
          'materials': 890.0,
          'components': 420.0,
          'compute': 650.0,
        },
        'human': {'name': 'Amara Vance', 'credits': 85400.0},
        'business': {'id': 'B-1', 'name': 'Vance Corp', 'profit': 4200.0},
      });

      for (final mode in EarthThemeMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: createEarthTheme(mode),
            home: Scaffold(
              body: TopFixedHudPanel(
                state: state,
                connectionStatus: LiveConnectionStatus.live,
                onCommLink: () {},
                onReconnect: () {},
                unreadNotifications: 3,
                unreadCommMessages: 1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('EARTH'), findsOneWidget);
        expect(find.text('UNITED CORPORATIONS'), findsOneWidget);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.byType(EarthLogo), findsOneWidget);
      }

      // Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpWidget(
        MaterialApp(
          theme: createEarthTheme(EarthThemeMode.biosphereEmerald),
          home: Scaffold(
            body: TopFixedHudPanel(
              state: state,
              connectionStatus: LiveConnectionStatus.polling,
              onCommLink: () {},
              onReconnect: () {},
              unreadNotifications: 0,
              unreadCommMessages: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EarthLogo), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Must not have layout overflows on mobile');
    });
  });
}
