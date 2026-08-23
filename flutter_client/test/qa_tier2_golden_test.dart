import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/shared/widgets/earth_primitives.dart';
import 'package:earth_client/app/theme.dart';

void main() {
  const viewports = <Size>[Size(375, 812), Size(768, 1024), Size(1440, 900)];

  for (final mode in EarthThemeMode.values) {
    for (final viewport in viewports) {
      testWidgets('Tier 2 golden ${mode.id} ${viewport.width.toInt()}px', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(MaterialApp(
          theme: createEarthTheme(mode),
          home: Scaffold(
            body: EarthPanel(
              title: 'UNITED CORPORATIONS',
              child: Row(children: [
                const Expanded(child: Text('CENTRAL TREASURY')),
                EarthMetric(label: 'CREDITS', value: '12,450', accent: mode.accent),
              ]),
            ),
          ),
        ));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile(
          'goldens/qa/${mode.id}_${viewport.width.toInt()}.png',
        ));
      });
    }
  }
}
