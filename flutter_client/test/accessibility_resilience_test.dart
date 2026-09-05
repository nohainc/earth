import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/shared/widgets/earth_primitives.dart';

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
