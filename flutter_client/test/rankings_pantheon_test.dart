import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets('WorldRankingsPanel and PantheonPanel render rankings, achievements, and deceased pantheon',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      'rankings': {
        'cities': [
          {'id': 'CITY-0084', 'residents': 142},
        ],
        'corporations': [
          {'id': 'CORP-001', 'member_count': 38},
        ],
      },
      'history': {
        'events': [
          {'game_day': 180, 'title': 'First Solar Grid Activated'},
        ],
      },
    });

    const pantheon = {
      'deceasedPantheon': [
        {'display_name': 'Eleni Vance', 'final_legacy': 12500},
      ],
      'livingLeaders': [
        {'display_name': 'Amara Kline', 'composite_legacy_score': 8400},
      ],
      'achievements': [
        {'name': 'Grid Pioneer', 'description': 'Constructed first municipal power node'},
      ],
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                WorldRankingsPanel(state: state),
                HistoryArchivePanel(state: state),
                PantheonPanel(pantheon: pantheon),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('WORLD RANKINGS / POSTGRES LIVE'), findsOneWidget);
    expect(find.textContaining('CITY-0084  ·  142 residents'), findsOneWidget);
    expect(find.textContaining('CORP-001  ·  38 members'), findsOneWidget);

    expect(find.text('HISTORY / ARCHIVE'), findsOneWidget);
    expect(find.textContaining('DAY 180  ·  First Solar Grid Activated'), findsOneWidget);

    expect(find.text('PANTHEON / ACHIEVEMENTS'), findsOneWidget);
    expect(find.textContaining('Eleni Vance  ·  legacy 12500'), findsOneWidget);
    expect(find.textContaining('Amara Kline  ·  score 8400'), findsOneWidget);
    expect(find.textContaining('Grid Pioneer  ·  Constructed first municipal power node'), findsOneWidget);
  });
}
