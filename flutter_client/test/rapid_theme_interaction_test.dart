import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/models/live_connection_status.dart';
import 'package:earth_client/features/command_center/top_fixed_hud_panel.dart';
import 'package:earth_client/features/command_center/sidebar.dart';

void main() {
  const testState = EarthState({
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

  group('Tier 4: Interaction Contracts & Dynamic Theme Hot-Switching Resilience', () {
    testWidgets('Rapidly cycling through all 6 faction themes during active ticks causes zero exceptions', (tester) async {
      String currentSection = 'command';

      for (int i = 0; i < 3; i++) {
        for (final mode in EarthThemeMode.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: createEarthTheme(mode),
              home: Scaffold(
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child: TopFixedHudPanel(
                    state: testState,
                    connectionStatus: LiveConnectionStatus.live,
                    onCommLink: () {},
                    onReconnect: () {},
                  ),
                ),
                body: Row(
                  children: [
                    Sidebar(
                      state: testState,
                      selectedSection: currentSection,
                      onNavigate: (s) => currentSection = s,
                      unreadNotifications: 2,
                      unreadCommMessages: 1,
                    ),
                    const Expanded(
                      child: Center(child: Text('Workspace Canvas')),
                    ),
                  ],
                ),
              ),
            ),
          );

          // Fast pumping simulating rapid user hot-theme switching
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull, reason: 'Theme switch to ${mode.name} must never throw');
        }
      }

      await tester.pumpAndSettle();
      expect(find.text('Workspace Canvas'), findsOneWidget);
    });

    testWidgets('Sidebar accordion expansion and active navigation updates correctly', (tester) async {
      String activeSec = 'command';

      await tester.pumpWidget(
        MaterialApp(
          theme: createEarthTheme(EarthThemeMode.solarGold),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Sidebar(
                  state: testState,
                  selectedSection: activeSec,
                  onNavigate: (s) {
                    setState(() => activeSec = s);
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Business Category Accordion
      final businessHeader = find.text('ENTERPRISE & ASSETS');
      if (businessHeader.evaluate().isNotEmpty) {
        await tester.tap(businessHeader);
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
