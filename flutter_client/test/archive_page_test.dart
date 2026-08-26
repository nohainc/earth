import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';

void main() {
  const pantheon = {
    'deceasedPantheon': [
      {'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'dynasty_name': 'Vance Dynasty'},
    ],
    'dynasties': [
      {'dynasty_name': 'Vance Dynasty', 'deceased_count': 1, 'peak_legacy': 5400, 'is_extinct': true},
    ],
  };

  testWidgets('memorial page renders citizens and dynasties with tab switching', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('MEMORIAL CITIZENS'), findsWidgets);
    expect(find.text('CITIZENS (1)'), findsOneWidget);
    expect(find.text('DYNASTIES (1)'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsOneWidget);

    // Switch to Dynasties tab on narrow layout
    await tester.tap(find.text('DYNASTIES (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HISTORICAL DYNASTIES'), findsWidgets);
    expect(find.textContaining('Vance Dynasty'), findsWidgets);
    expect(find.text('WORLD MILESTONES'), findsNothing);
  });

  testWidgets('memorial page renders explicit empty states across tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: {},
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('No citizens have entered the public archive yet.'), findsOneWidget);

    await tester.tap(find.text('DYNASTIES (0)'));
    await tester.pumpAndSettle();
    expect(find.text('No extinct dynasties have been recorded in the archive yet.'), findsOneWidget);
    expect(find.text('WORLD MILESTONES'), findsNothing);
  });

  testWidgets('tapping info icon on MEMORIAL CITIZENS opens formula modal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();

    final infoIcon = find.byIcon(Icons.info_outline);
    expect(infoIcon, findsOneWidget);

    await tester.tap(infoIcon);
    await tester.pumpAndSettle();

    expect(find.text('MEMORIAL CITIZENS'), findsWidgets);
    expect(find.textContaining('1 : 5 : 25 weighting ratio'), findsOneWidget);
    expect(find.textContaining('1 Legacy Pt = 5 Civic Standing Pts = 25 Age Years'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping info icon on HISTORICAL DYNASTIES opens prestige score modal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();

    // Switch to Dynasties tab
    await tester.tap(find.text('DYNASTIES (1)'));
    await tester.pumpAndSettle();

    final infoIcon = find.byIcon(Icons.info_outline);
    expect(infoIcon, findsOneWidget);

    await tester.tap(infoIcon);
    await tester.pumpAndSettle();

    expect(find.text('HISTORICAL DYNASTIES'), findsWidgets);
    expect(find.textContaining('1 : 5 : 25 weighting ratio'), findsOneWidget);
    expect(find.textContaining('Dynastic Legacy (25x relative weight)'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });

  testWidgets('searching citizens and dynasties filters archive lists and shows empty states', (tester) async {
    const multiPantheon = {
      'deceasedPantheon': [
        {'display_name': 'Founder Marcus Vance', 'dynasty_name': 'Vance Dynasty', 'death_game_day': 1200, 'final_legacy': 5400},
        {'display_name': 'Elena Rostova', 'dynasty_name': 'House of Rostov', 'death_game_day': 1450, 'final_legacy': 3200},
      ],
      'dynasties': [
        {'dynasty_name': 'Vance Dynasty', 'is_extinct': true, 'deceased_count': 1},
        {'dynasty_name': 'House of Rostov', 'is_extinct': true, 'deceased_count': 1},
      ],
    };

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: multiPantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();

    // Verify initial state
    expect(find.textContaining('Founder Marcus Vance'), findsOneWidget);
    expect(find.textContaining('Elena Rostova'), findsOneWidget);

    // Search for Marcus
    final searchFields = find.byType(TextField);
    await tester.enterText(searchFields.first, 'Marcus');
    await tester.pumpAndSettle();

    expect(find.textContaining('Founder Marcus Vance'), findsOneWidget);
    expect(find.textContaining('Elena Rostova'), findsNothing);

    // Non-matching citizen search
    await tester.enterText(searchFields.first, 'Unknown Citizen XYZ');
    await tester.pumpAndSettle();
    expect(find.text('No archived citizens match "Unknown Citizen XYZ".'), findsOneWidget);

    // Clear citizen search
    await tester.enterText(searchFields.first, '');
    await tester.pumpAndSettle();
    expect(find.textContaining('Elena Rostova'), findsOneWidget);

    // Switch to Dynasties tab
    await tester.tap(find.textContaining('DYNASTIES'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vance Dynasty'), findsWidgets);
    expect(find.textContaining('House of Rostov'), findsWidgets);

    // Search dynasties for Rostov
    final dynastySearchFields = find.byType(TextField);
    await tester.enterText(dynastySearchFields.first, 'Rostov');
    await tester.pumpAndSettle();

    expect(find.textContaining('House of Rostov'), findsWidgets);
    expect(find.textContaining('Vance Dynasty'), findsNothing);

    // Non-matching dynasty search
    await tester.enterText(dynastySearchFields.first, 'Nonexistent Dynasty');
    await tester.pumpAndSettle();
    expect(find.text('No recorded dynasties match "Nonexistent Dynasty".'), findsOneWidget);
  });
}
