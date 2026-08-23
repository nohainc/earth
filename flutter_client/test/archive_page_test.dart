import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';

void main() {
  const pantheon = {
    'deceasedPantheon': [
      {'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty'},
    ],
    'dynasties': [
      {'dynasty_name': 'Vance Dynasty', 'deceased_count': 1, 'peak_legacy': 5400, 'active_heir': 'Amara Vance'},
    ],
  };

  testWidgets('archive page renders citizens and dynasties', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('HISTORICAL ARCHIVE'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsOneWidget);
    expect(find.textContaining('Vance Dynasty'), findsWidgets);
    expect(find.text('WORLD MILESTONES'), findsNothing);
  });

  testWidgets('archive page renders explicit empty states', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: {},
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('No citizens have entered the public archive yet.'), findsOneWidget);
    expect(find.text('No dynasties have been archived yet.'), findsOneWidget);
    expect(find.text('WORLD MILESTONES'), findsNothing);
  });
}
