import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/dynasty/dynasty_lineage_dialog.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';
import 'package:earth_client/features/lifecycle/historical_archive_panel.dart';
import 'package:earth_client/core/models/earth_state.dart';

void main() {
  group('DynastyLineageDialog & Interactive Row Lineage Inspection', () {
    testWidgets('DynastyLineageDialog renders header, metrics, and generational tree nodes', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockDynasty = {
        'dynasty_name': 'Vance Dynasty',
        'founder_name': 'Marcus Vance',
        'active_heir': 'Amara Vance',
        'motto': 'From the Red Dust We Build Eternity',
        'generation': 3,
        'deceased_count': 3,
        'total_legacy': 5400,
        'peak_standing': 980,
        'dynasty_score': 28450,
        'founded_game_day': 1,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDynastyLineageDialog(context, dynasty: mockDynasty),
                child: const Text('OPEN DIALOG'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN DIALOG'));
      await tester.pumpAndSettle();

      expect(find.text('Vance Dynasty'), findsOneWidget);
      expect(find.text('“From the Red Dust We Build Eternity”'), findsOneWidget);
      expect(find.text('28450 PTS'), findsOneWidget);
      expect(find.text('5400 LP'), findsOneWidget);
      expect(find.text('980 Std'), findsOneWidget);
      expect(find.text('3 Inscribed'), findsOneWidget);
      expect(find.text('DYNASTIC SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Marcus Vance'), findsOneWidget);
      expect(find.text('Amara Vance'), findsOneWidget);
      expect(find.text('CLOSE'), findsOneWidget);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('DYNASTIC SUCCESSION & LINEAGE TREE'), findsNothing);
    });

    testWidgets('CivicRankingsPanel tapping dynasty row opens DynastyLineageDialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = EarthState(
        {
          'rankings': {
            'corporations': [],
            'cities': [],
            'citizens': [],
            'dynasties': [
              {
                'dynasty_name': 'Noha Dynasty',
                'founder_name': 'Vitalii Noha',
                'active_heir': 'Vitalii Noha',
                'generation': 3,
                'deceased_count': 2,
                'total_legacy': 4600,
                'peak_standing': 920,
                'dynasty_score': 24200,
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

      // Switch to DYNASTIES tab on column 1
      final dynastiesTab = find.text('DYNASTIES (1)');
      expect(dynastiesTab, findsOneWidget);
      await tester.tap(dynastiesTab);
      await tester.pumpAndSettle();

      // Find the Noha Dynasty row and tap it
      expect(find.text('Noha Dynasty'), findsOneWidget);
      await tester.tap(find.text('Noha Dynasty'));
      await tester.pumpAndSettle();

      // Verify DynastyLineageDialog opened
      expect(find.text('DYNASTIC SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Vitalii Noha'), findsAtLeastNWidgets(1));
    });

    testWidgets('HistoricalArchivePanel tapping recorded dynasty card opens DynastyLineageDialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pantheon = {
        'deceasedPantheon': [],
        'dynasties': [
          {
            'dynasty_name': 'House of Vance (Historical)',
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

      // Verify DynastyLineageDialog opened for extinct house
      expect(find.text('DYNASTIC SUCCESSION & LINEAGE TREE'), findsOneWidget);
      expect(find.text('Lineage Extinct'), findsOneWidget);
    });
  });
}
