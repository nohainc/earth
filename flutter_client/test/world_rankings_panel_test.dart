import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets(
      'World Rankings renders canonical House dimensions and Your House',
      (tester) async {
    const state = EarthState({
      'human': {'house_id': 'HOUSE-NOHA', 'house_name': 'House of Noha'},
      'rankings': {
        'generatedFrom': 'ranking-snapshots',
        'gameDay': 142,
        'rulesVersion': 'rankings-v1',
        'populationSize': 3,
        'metrics': {
          'WEALTH': [
            {
              'rank': 1,
              'subject_id': 'HOUSE-A',
              'subject_name': 'House Aurora',
              'metric_value': '12400000',
              'population_size': 3,
              'percentile': 100
            },
            {
              'rank': 2,
              'subject_id': 'HOUSE-NOHA',
              'subject_name': 'House of Noha',
              'metric_value': '8420000',
              'population_size': 3,
              'percentile': 66.7
            },
          ],
          'LEGACY': [],
        },
      },
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: WorldRankingsPanel(state: state))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('WORLD RANKINGS'), findsOneWidget);
    expect(find.text('YOUR HOUSE'), findsOneWidget);
    expect(find.text('House of Noha'), findsWidgets);
    expect(find.text('#2'), findsNWidgets(2));
    expect(find.text('CITIZENS'), findsNothing);
    expect(find.text('ORGANIZATIONS'), findsNothing);
    expect(find.text('TERRITORIES'), findsNothing);
  });

  testWidgets('World Rankings renders 4 core tabs and switches between them',
      (tester) async {
    const state = EarthState({
      'human': {'house_id': 'HOUSE-NOHA', 'house_name': 'House of Noha'},
      'rankings': {
        'generatedFrom': 'ranking-snapshots',
        'gameDay': 142,
        'rulesVersion': 'rankings-v1',
        'populationSize': 12,
        'metrics': {
          'LEGACY': [
            {'rank': 1, 'subject_name': 'House Vance', 'metric_value': '5400', 'percentile': 100},
          ],
          'WEALTH': [
            {'rank': 1, 'subject_name': 'House Aurora', 'metric_value': '12400000', 'percentile': 100},
          ],
          'PRODUCTIVE_CAPACITY': [
            {'rank': 1, 'subject_name': 'House Builders', 'metric_value': '24', 'percentile': 100},
          ],
          'TECHNOLOGY': [
            {'rank': 1, 'subject_name': 'House Tech', 'metric_value': '8', 'percentile': 100},
          ],
        },
      },
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: WorldRankingsPanel(state: state))),
    ));
    await tester.pumpAndSettle();

    // Verify all 4 core tab buttons are rendered in the single row
    expect(find.text('LEGACY'), findsWidgets);
    expect(find.text('WEALTH'), findsOneWidget);
    expect(find.text('BUILDINGS'), findsOneWidget);
    expect(find.text('TECHNOLOGY'), findsOneWidget);

    // Initial tab: LEGACY
    expect(find.text('House Vance'), findsOneWidget);
    expect(find.text('House Aurora'), findsNothing);

    // Switch to WEALTH tab
    await tester.tap(find.text('WEALTH'));
    await tester.pumpAndSettle();
    expect(find.text('House Aurora'), findsOneWidget);
    expect(find.text('House Vance'), findsNothing);

    // Switch to BUILDINGS tab
    await tester.tap(find.text('BUILDINGS'));
    await tester.pumpAndSettle();
    expect(find.text('House Builders'), findsOneWidget);

    // Switch to TECHNOLOGY tab
    await tester.tap(find.text('TECHNOLOGY'));
    await tester.pumpAndSettle();
    expect(find.text('House Tech'), findsOneWidget);
  });
}
