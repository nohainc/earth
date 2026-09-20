import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  test('ranking metric formatter respects canonical value types', () {
    expect(formatRankingMetricValue('LIQUID_CREDIT', '50000'), '500.00 C');
    expect(formatRankingMetricValue('PRODUCTIVE_CAPACITY', '184'), '184 capacity');
    expect(formatRankingMetricValue('TECHNOLOGY', '12'), '12');
    expect(formatRankingMetricValue('LEGACY', '8420'), '8420 LP');
  });

  testWidgets('canonical rankings render V5 House metrics only', (tester) async {
    const state = EarthState({
      'human': {'house_id': 'HOUSE-1', 'house_name': 'Kline'},
      'rankings': {
        'gameDay': 184,
        'rulesVersion': 'rankings-v2',
        'populationSize': 12,
        'metrics': {
          'LIQUID_CREDIT': [
            {
              'rank': 1,
              'subject_id': 'HOUSE-1',
              'subject_name': 'Kline',
              'metric_value': '50000',
              'percentile': 100,
            },
          ],
          'PRODUCTIVE_CAPACITY': [
            {
              'rank': 1,
              'subject_id': 'HOUSE-1',
              'subject_name': 'Kline',
              'metric_value': '184',
              'percentile': 100,
            },
          ],
        },
      },
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WorldRankingsPanel(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LIQUID CREDIT'), findsWidgets);
    expect(find.text('500.00 C'), findsOneWidget);
    expect(find.text('50000'), findsNothing);
    expect(find.text('YOUR HOUSE'), findsOneWidget);
    expect(find.text('CITIZENS'), findsNothing);
    expect(find.text('ORGANIZATIONS'), findsNothing);
    expect(find.text('TERRITORIES'), findsNothing);
    expect(find.text('SOVEREIGN'), findsNothing);
    expect(find.text('PATRICIAN'), findsNothing);
    expect(find.text('PIONEER'), findsNothing);
  });
}
