import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/player_objective.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/objectives_panel.dart';

void main() {
  final testState = const EarthState({
    'clock': {'day': 185, 'minute': 400},
    'world': {'health': 80, 'essentialServicesIndex': 0.88},
    'human': {'id': 'H-0044', 'name': 'Amara Vance', 'credits': 32000.0, 'standing': 85.0},
    'resources': {'energy': 80.0, 'material': 150.0, 'food': 50.0},
    'business': {'id': 'b-1', 'name': 'AeroWorks', 'profit': 1500.0},
    'contracts': [
      {'id': 'c-101', 'title': 'Aerospace Composites', 'status': 'active'}
    ],
    'machines': [
      {'id': 'm-1', 'name': 'Precision Lathe', 'condition': 85.0, 'utilization': 80.0},
      {'id': 'm-2', 'name': 'Foundry Mk2', 'condition': 90.0, 'utilization': 70.0}
    ],
    'governance': {
      'proposals': [
        {'id': 'prop-1', 'title': 'Municipal Tax Charter Revision', 'status': 'open'}
      ]
    },
    'technology': {
      'research': {'progress': 75.0}
    },
    'life': {
      'generation': 2,
      'status': 'active',
      'successor': {'id': 'H-0099', 'name': 'Cyrus Vance'},
    },
  });

  group('PlayerObjective Model & Synthesis', () {
    test('serializes and deserializes JSON correctly', () {
      const obj = PlayerObjective(
        id: 'obj-1',
        category: 'enterprise',
        title: 'Build the Most Valuable Corporation',
        description: 'Grow your enterprise into an industrial conglomerate.',
        currentValue: 45000.0,
        targetValue: 100000.0,
        progressPercentage: 45.0,
        metricLabel: '45,000 / 100,000 C Valuation',
        status: 'in_progress',
        rewardDescription: 'Title: "Industrial Titan"',
        targetSection: 'business',
        iconName: 'business_center',
      );

      final json = obj.toJson();
      final fromJson = PlayerObjective.fromJson(json);

      expect(fromJson.id, 'obj-1');
      expect(fromJson.category, 'enterprise');
      expect(fromJson.title, 'Build the Most Valuable Corporation');
      expect(fromJson.progressPercentage, 45.0);
      expect(fromJson.categoryLabel, 'ENTERPRISE & INDUSTRY');
      expect(fromJson.categoryColor, const Color(0xFFF59E0B));
      expect(fromJson.categoryIcon, Icons.business_center_outlined);
      expect(fromJson.isCompleted, isFalse);
    });

    test('synthesizes all exemplar objectives from state', () {
      final objectives = PlayerObjective.synthesizeFromState(testState);

      expect(objectives.length, 9);

      final titles = objectives.map((o) => o.title).toList();
      expect(titles.any((t) => t.contains('Valuable Corporation')), isTrue);
      expect(titles.any((t) => t.contains('Civic Delegate')), isTrue);
      expect(titles.any((t) => t.contains('House with Sovereign Traits')), isTrue);
      expect(titles.any((t) => t.contains('Technology Licensor')), isTrue);
      expect(titles.any((t) => t.contains('Financial Independence')), isTrue);
      expect(titles.any((t) => t.contains('Public-Service Score')), isTrue);
    });
  });

  group('ObjectivesPanel Widget', () {
    testWidgets('renders ambition gauge, cards, reward descriptions, and triggers pursue action',
        (tester) async {
      final objectives = PlayerObjective.synthesizeFromState(testState);
      String? navigatedSection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ObjectivesPanel(
                objectives: objectives,
                onNavigate: (s) => navigatedSection = s,
              ),
            ),
          ),
        ),
      );

      // Verify Header and Global Ambition Gauge
      expect(find.text('CURRENT DIRECTION'), findsOneWidget);
      expect(find.textContaining('DIRECTIONS COMPLETED'), findsOneWidget);
      expect(find.textContaining('OVERALL PROGRESS'), findsOneWidget);

      // Verify Filter Pills
      expect(find.textContaining('ALL (9)'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsOneWidget);
      expect(find.text('CIVIC & HOUSE'), findsOneWidget);
      expect(find.text('TECH & FINANCE'), findsOneWidget);
      expect(find.textContaining('COMPLETED ('), findsOneWidget);

      // Verify Titles of Objectives
      expect(find.text('Build the Most Valuable Corporation'), findsOneWidget);
      expect(find.text('Become a Major Civic Delegate'), findsOneWidget);
      expect(find.text('Found a House with Sovereign Traits'), findsOneWidget);
      expect(find.text('Become a Leading Technology Licensor'), findsNothing);
      expect(find.text('Reach Financial Independence'), findsNothing);
      expect(find.text('Maintain the Highest Public-Service Score'), findsNothing);

      // Verify Rewards preview text
      expect(find.textContaining('Industrial Titan'), findsOneWidget);
      expect(find.textContaining('Grand Tribune'), findsOneWidget);

      // Test Pursue Button Click
      final pursueBtn = find.text('PURSUE').first;
      await tester.ensureVisible(pursueBtn);
      await tester.pumpAndSettle();
      await tester.tap(pursueBtn);
      await tester.pump();

      expect(navigatedSection, isNotNull);

      // Test Filtering Tabs
      final techFinanceTab = find.text('TECH & FINANCE');
      await tester.ensureVisible(techFinanceTab);
      await tester.pumpAndSettle();
      await tester.tap(techFinanceTab);
      await tester.pumpAndSettle();

      // Technology & Finance should be present
      expect(find.text('Become a Leading Technology Licensor'), findsOneWidget);
      expect(find.text('Reach Financial Independence'), findsOneWidget);
      // Civic delegate should be filtered out
      expect(find.text('Become a Major Civic Delegate'), findsNothing);
    });

    testWidgets('showObjectivesDialog opens modal and dismisses', (tester) async {
      final objectives = PlayerObjective.synthesizeFromState(testState);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showObjectivesDialog(
                    context,
                    objectives: objectives,
                  ),
                  child: const Text('OPEN CODEX'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN CODEX'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('LONG-TERM STRATEGIC OBJECTIVES'), findsWidgets);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });
}
