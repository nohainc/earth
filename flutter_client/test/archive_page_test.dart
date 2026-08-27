import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';

void main() {
  const pantheon = {
    'deceasedPantheon': [
      {'display_name': 'Founder Marcus Vance', 'death_game_day': 1200, 'final_legacy': 5400, 'house_name': 'House of Vance'},
    ],
    'houses': [
      {'house_name': 'House of Vance', 'deceased_count': 1, 'peak_legacy': 5400, 'is_extinct': true},
    ],
  };

  testWidgets('memorial page renders citizens and houses with tab switching', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('MEMORIAL CITIZENS'), findsWidgets);
    expect(find.text('CITIZENS (1)'), findsOneWidget);
    expect(find.text('HOUSES (1)'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsOneWidget);

    // Switch to Houses tab on narrow layout
    await tester.tap(find.text('HOUSES (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HISTORICAL HOUSES'), findsWidgets);
    expect(find.textContaining('House of Vance'), findsWidgets);
    expect(find.text('WORLD MILESTONES'), findsNothing);
  });

  testWidgets('memorial page renders explicit empty states across tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: {},
      events: [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('No citizens have entered the public archive yet.'), findsOneWidget);

    await tester.tap(find.text('HOUSES (0)'));
    await tester.pumpAndSettle();
    expect(find.text('No extinct houses have been recorded in the archive yet.'), findsOneWidget);
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

  testWidgets('tapping info icon on HISTORICAL HOUSES opens prestige score modal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoricalArchivePanel(
      pantheon: pantheon,
      events: [],
    ))));
    await tester.pumpAndSettle();

    // Switch to Houses tab
    await tester.tap(find.text('HOUSES (1)'));
    await tester.pumpAndSettle();

    final infoIcon = find.byIcon(Icons.info_outline);
    expect(infoIcon, findsOneWidget);

    await tester.tap(infoIcon);
    await tester.pumpAndSettle();

    expect(find.text('HISTORICAL HOUSES'), findsWidgets);
    expect(find.textContaining('1 : 5 : 25 weighting ratio'), findsOneWidget);
    expect(find.textContaining('House Legacy (25x relative weight)'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });

  testWidgets('searching citizens and houses filters archive lists and shows empty states', (tester) async {
    const multiPantheon = {
      'deceasedPantheon': [
        {'display_name': 'Founder Marcus Vance', 'house_name': 'House of Vance', 'death_game_day': 1200, 'final_legacy': 5400},
        {'display_name': 'Elena Rostova', 'house_name': 'House of Rostov', 'death_game_day': 1450, 'final_legacy': 3200},
      ],
      'houses': [
        {'house_name': 'House of Vance', 'is_extinct': true, 'deceased_count': 1},
        {'house_name': 'House of Rostov', 'is_extinct': true, 'deceased_count': 1},
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

    // Switch to Houses tab
    await tester.tap(find.textContaining('HOUSES'));
    await tester.pumpAndSettle();

    expect(find.textContaining('House of Vance'), findsWidgets);
    expect(find.textContaining('House of Rostov'), findsWidgets);

    // Search houses for Rostov
    final houseSearchFields = find.byType(TextField);
    await tester.enterText(houseSearchFields.first, 'Rostov');
    await tester.pumpAndSettle();

    expect(find.textContaining('House of Rostov'), findsWidgets);
    expect(find.textContaining('House of Vance'), findsNothing);

    // Non-matching house search
    await tester.enterText(houseSearchFields.first, 'Nonexistent House');
    await tester.pumpAndSettle();
    expect(find.text('No recorded houses match "Nonexistent House".'), findsOneWidget);
  });
}
