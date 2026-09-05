import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/house/house_lineage_dialog.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';
import 'package:earth_client/core/models/earth_state.dart';

void main() {
  group('HouseLineageDialog & Interactive Row Lineage Inspection', () {
    testWidgets('HouseLineageDialog renders header, metrics, and generational tree nodes', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockHouse = {
        'house_name': 'House of Vance',
        'founder_name': 'Marcus Vance',
        'active_heir': 'Amara Vance',
        'motto': 'From the Red Dust We Build Eternity',
        'generation': 3,
        'deceased_count': 3,
        'total_legacy': 5400,
        'peak_standing': 980,
        'house_score': 28450,
        'founded_game_day': 1,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showHouseLineageDialog(context, house: mockHouse),
                child: const Text('OPEN DIALOG'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN DIALOG'));
      await tester.pumpAndSettle();

      expect(find.text('House of Vance'), findsOneWidget);
      expect(find.text('28450 PTS'), findsOneWidget);
      expect(find.text('5400 LP'), findsOneWidget);
      expect(find.text('980 Std'), findsOneWidget);
      expect(find.text('3 Inscribed'), findsOneWidget);
      expect(find.text('HOUSE SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Marcus Vance'), findsWidgets);
      expect(find.text('Amara Vance'), findsWidgets);
      expect(find.text('CLOSE'), findsOneWidget);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('HOUSE SUCCESSION & LINEAGE TREE'), findsNothing);
    });

    testWidgets('CivicRankingsPanel tapping house row opens HouseLineageDialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = const EarthState(
        {
          'rankings': {
            'corporations': [],
            'cities': [],
            'citizens': [],
            'houses': [
              {
                'house_name': 'House of Noha',
                'founder_name': 'Vitalii Noha',
                'active_heir': 'Vitalii Noha',
                'generation': 3,
                'deceased_count': 2,
                'total_legacy': 4600,
                'peak_standing': 920,
                'house_score': 24200,
                'founded_game_day': 120,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CivicRankingsPanel(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to HOUSES tab on column 1
      final housesTab = find.widgetWithText(InkWell, 'HOUSES');
      expect(housesTab, findsOneWidget);
      await tester.tap(housesTab);
      await tester.pumpAndSettle();

      // Find the House of Noha row and tap it
      expect(find.text('House of Noha'), findsOneWidget);
      await tester.tap(find.text('House of Noha'));
      await tester.pumpAndSettle();

      // Verify HouseLineageDialog opened
      expect(find.text('HOUSE SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Vitalii Noha'), findsAtLeastNWidgets(1));
    });

    testWidgets('HistoricalArchivePanel tapping recorded house card opens HouseLineageDialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pantheon = {
        'deceasedPantheon': [],
        'houses': [
          {
            'house_name': 'House of Vance (Historical)',
            'founder': 'Marcus Vance',
            'heir': '—',
            'is_extinct': true,
            'generation': 4,
            'ancestors_count': 4,
            'total_legacy': 6200,
            'standing': 850,
            'founded_game_day': 1,
            'motto': 'Eternity achieved.',
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoricalArchivePanel(pantheon: pantheon),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('House of Vance (Historical)'), findsOneWidget);
      await tester.tap(find.text('House of Vance (Historical)'));
      await tester.pumpAndSettle();

      // Verify HouseLineageDialog opened for extinct house
      expect(find.text('HOUSE SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Lineage Extinct'), findsOneWidget);
    });
  });
}
