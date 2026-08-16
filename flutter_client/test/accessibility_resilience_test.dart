import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/shared/widgets/earth_primitives.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/business_panel.dart';

void main() {
  group('Accessibility & UX Resilience', () {
    testWidgets('EarthPanel and EarthMetric expose accessible semantic labels',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EarthPanel(
                  title: 'CENTRAL TREASURY',
                  child: Text('Treasury balance: 5,000 C'),
                ),
                EarthMetric(
                  label: 'STANDING',
                  value: '840',
                  accent: Colors.tealAccent,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(EarthPanel)),
        matchesSemantics(label: 'CENTRAL TREASURY'),
      );

      expect(
        tester.getSemantics(find.byType(EarthMetric)),
        matchesSemantics(label: 'STANDING: 840'),
      );
    });

    testWidgets('EarthErrorState provides error message and reconnect button',
        (tester) async {
      bool reconnected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EarthErrorState(
              message: 'Connection dropped',
              retry: () {
                reconnected = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Connection dropped'), findsOneWidget);
      expect(find.text('RECONNECT'), findsOneWidget);

      await tester.tap(find.text('RECONNECT'));
      await tester.pumpAndSettle();

      expect(reconnected, isTrue);
    });

    testWidgets('BusinessPanel buttons are disabled when busy to prevent duplicate actions',
        (tester) async {
      const state = EarthState({
        'clock': {'day': 184, 'minute': 100},
        'human': {'id': 'H-0044', 'credits': 5000},
        'world': {'health': 100},
        'resources': {},
        'business': {
          'id': 'B-1048',
          'name': 'Kline Works',
          'policy': 'growth',
          'condition': 95,
          'status': 'operating',
        },
        'technology': {'research': {}},
        'institutions': {},
        'life': {},
        'governance': {},
        'market': {'orders': []},
      });

      const financials = {
        'revenue': 8000,
        'operating_costs': 2000,
        'profit': 6000,
        'taxed_revenue': 500,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BusinessPanel(
                state: state,
                busy: true, // Pending command active
                businessOwnership: const {},
                businessFinancials: financials,
                businessProfile: const {},
                action: (_) async {},
              ),
            ),
          ),
        ),
      );

      final dividendButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'DISTRIBUTE DIVIDENDS'),
      );
      expect(dividendButton.onPressed, isNull,
          reason: 'Button must be disabled when busy');
    });

    testWidgets('Responsive layouts adapt smoothly to narrow (360px) and wide (1200px) viewports',
        (tester) async {
      // Test Narrow 360px viewport
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EarthPanel(
                title: 'NARROW VIEWPORT ADAPTATION',
                child: Text('Content inside narrow container'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('NARROW VIEWPORT ADAPTATION'), findsOneWidget);

      // Test Wide 1200px viewport
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();

      expect(find.text('NARROW VIEWPORT ADAPTATION'), findsOneWidget);
    });
  });
}
