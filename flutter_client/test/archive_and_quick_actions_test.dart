import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/quick_actions_panel.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';

void main() {
  const state = EarthState({
    'clock': {'day': 220},
    'business': {'businesses': []},
    'membership': {'city_id': 'CITY-0084'},
    'technology': {
      'research': {'progress': 72}
    },
    'life': {'successor': {}},
  });

  testWidgets('Historical Archive presents people, dynasties, and milestones',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoricalArchivePanel(
          pantheon: const {
            'deceasedPantheon': [
              {
                'display_name': 'Mira Vance',
                'dynasty_name': 'Vance House',
                'death_game_day': 180
              }
            ],
            'dynasties': [
              {
                'dynasty_name': 'Vance House',
                'generation': 3,
                'legacy_points': 240
              }
            ],
          },
          events: const [
            {'title': 'City resilience charter adopted', 'game_day': 210}
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('HISTORICAL ARCHIVE'), findsOneWidget);
    expect(find.text('Mira Vance'), findsOneWidget);
    expect(find.text('Vance House'), findsWidgets);
    expect(find.text('City resilience charter adopted'), findsOneWidget);
  });

  testWidgets('Quick Actions routes the player to the selected domain',
      (tester) async {
    String? destination;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuickActionsPanel(
          state: state,
          onNavigate: (section) => destination = section,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('RUN THE BUSINESS'), findsOneWidget);
    expect(find.text('DIRECT RESEARCH'), findsOneWidget);
    await tester.tap(find.text('CHECK CITY SERVICES'));
    expect(destination, 'city');
  });
}
