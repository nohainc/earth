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

  testWidgets('Historical Archive presents people, houses, and milestones',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HistoricalArchivePanel(
          pantheon: {
            'deceasedPantheon': [
              {
                'display_name': 'Mira Vance',
                'house_name': 'House of Vance',
                'death_game_day': 180
              }
            ],
            'houses': [
              {
                'house_name': 'House of Vance',
                'generation': 3,
                'legacy_points': 240
              }
            ],
          },
          events: [],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('MEMORIAL & PANTHEON'), findsOneWidget);
    expect(find.text('Mira Vance'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, 'HOUSES'));
    await tester.pumpAndSettle();
    expect(find.text('House of Vance'), findsWidgets);
    expect(find.text('WORLD MILESTONES'), findsNothing);
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
