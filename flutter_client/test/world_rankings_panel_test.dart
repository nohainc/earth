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
}
