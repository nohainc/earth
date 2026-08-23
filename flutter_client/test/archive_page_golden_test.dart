import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';

void main() {
  testWidgets('Tier 2 archive page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: createEarthTheme(),
      home: Scaffold(body: HistoricalArchivePanel(
        pantheon: const {'deceasedPantheon': [{'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty'}]},
        events: const [{'type': 'world_clock', 'gameDay': 184, 'title': 'World advances'}],
      )),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/archive_1440.png'));
  });
}
