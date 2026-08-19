import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/decision_queue_item.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/decision_queue_panel.dart';

void main() {
  final testState = EarthState(const {
    'clock': {'day': 185, 'minute': 400},
    'world': {'health': 80, 'livingCostIndex': 1.1},
    'human': {'id': 'H-0044', 'name': 'Amara Vance', 'credits': 2400.0},
    'resources': {'energy': 20.0, 'material': 15.0, 'food': 50.0},
    'business': {'id': 'b-1', 'name': 'AeroWorks', 'profit': -150.0},
    'contracts': [
      {'id': 'c-101', 'title': 'Aerospace Composites', 'status': 'active'}
    ],
    'machines': [
      {
        'id': 'm-1',
        'name': 'Precision Lathe',
        'condition': 35.0,
        'utilization': 80.0
      }
    ],
    'governance': {
      'proposals': [
        {
          'id': 'prop-1',
          'title': 'Municipal Tax Charter Revision',
          'status': 'open'
        }
      ]
    },
    'technology': {
      'research': {'progress': 60.0}
    },
    'life': {
      'status': 'active',
      'successor': null,
    },
  });

  group('DecisionQueueItem Model & Synthesis', () {
    test('serializes and deserializes JSON correctly', () {
      const item = DecisionQueueItem(
        id: 'dec-1',
        category: 'business',
        title: 'Your corporation is losing energy',
        whyItMatters: 'Energy reserves are critically depleted.',
        deadline: 'Immediate (Next Tick)',
        expectedImpact: 'Prevent emergency production blackout.',
        riskLevel: 'critical',
        primaryActionLabel: 'Procure Energy',
        targetSection: 'market',
        urgencyScore: 90.0,
      );

      final json = item.toJson();
      final fromJson = DecisionQueueItem.fromJson(json);

      expect(fromJson.id, 'dec-1');
      expect(fromJson.category, 'business');
      expect(fromJson.title, 'Your corporation is losing energy');
      expect(fromJson.whyItMatters, 'Energy reserves are critically depleted.');
      expect(fromJson.riskLevel, 'critical');
      expect(fromJson.riskLabel, 'CRITICAL RISK');
      expect(fromJson.riskColor, const Color(0xFFFF5252));
      expect(fromJson.primaryActionLabel, 'Procure Energy');
      expect(fromJson.targetSection, 'market');
      expect(fromJson.categoryIcon, Icons.business_center_outlined);
    });

    test('synthesizes all 6 required decision items from raw state', () {
      final items = DecisionQueueItem.synthesizeFromState(testState);

      expect(items.length, greaterThanOrEqualTo(6));

      final titles = items.map((i) => i.title).toList();
      expect(titles.any((t) => t.contains('losing energy')), isTrue);
      expect(
          titles.any((t) => t.contains('contract expires in 2 days')), isTrue);
      expect(
          titles.any((t) => t.contains('unresolved governance vote')), isTrue);
      expect(
          titles.any((t) => t.contains('machine needs maintenance')), isTrue);
      expect(titles.any((t) => t.contains('Research funding is available')),
          isTrue);
      expect(
          titles.any((t) => t.contains('dynasty decision is pending')), isTrue);

      // Verify sorted by urgency descending
      for (int i = 0; i < items.length - 1; i++) {
        expect(items[i].urgencyScore,
            greaterThanOrEqualTo(items[i + 1].urgencyScore));
      }
    });
  });

  group('DecisionQueuePanel Widget', () {
    testWidgets(
        'renders header, filter tabs, decision cards, and triggers action',
        (tester) async {
      final items = DecisionQueueItem.synthesizeFromState(testState);
      DecisionQueueItem? executedDecision;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DecisionQueuePanel(
                items: items,
                onExecuteDecision: (d) => executedDecision = d,
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify Header & Status Row
      expect(find.text('PRIORITIZED DECISION QUEUE'), findsOneWidget);
      expect(find.textContaining('URGENT ACTIONS REQUIRED'), findsOneWidget);
      expect(find.textContaining('TOTAL DECISIONS'), findsOneWidget);

      // Verify Filter Pills
      expect(find.textContaining('ALL ('), findsOneWidget);
      expect(find.textContaining('CRITICAL / HIGH'), findsOneWidget);
      expect(find.text('CORPORATION & ASSETS'), findsOneWidget);
      expect(find.text('CIVIC & DYNASTY'), findsOneWidget);

      // Verify Decision Card Titles
      expect(find.text('Your corporation is losing energy'), findsOneWidget);
      expect(find.text('A contract expires in 2 days'), findsOneWidget);
      expect(
          find.text('You have an unresolved governance vote'), findsOneWidget);
      expect(find.text('Your machine needs maintenance'), findsOneWidget);
      expect(find.text('Research funding is available'), findsOneWidget);
      expect(find.text('A dynasty decision is pending'), findsOneWidget);

      // Verify "Why it matters" narrative blocks exist
      expect(find.textContaining('Energy reserves are dangerously depleted'),
          findsOneWidget);
      expect(find.textContaining('Unfulfilled supply obligations risk'),
          findsOneWidget);

      // Verify Action Button Tap
      final procureBtn = find.text('PROCURE ENERGY');
      expect(procureBtn, findsOneWidget);
      await tester.ensureVisible(procureBtn);
      await tester.pumpAndSettle();
      await tester.tap(procureBtn);
      await tester.pump();

      expect(executedDecision?.primaryActionLabel, 'Procure Energy');
      expect(executedDecision?.targetSection, 'market');

      // Test Filtering Tabs
      final civicTab = find.text('CIVIC & DYNASTY');
      await tester.ensureVisible(civicTab);
      await tester.pumpAndSettle();
      await tester.tap(civicTab);
      await tester.pumpAndSettle();

      // In Civic & Dynasty filter: governance, technology, and dynasty should be present
      expect(
          find.text('You have an unresolved governance vote'), findsOneWidget);
      expect(find.text('A dynasty decision is pending'), findsOneWidget);
      // Corporate machine maintenance should be filtered out
      expect(find.text('Your machine needs maintenance'), findsNothing);
    });

    testWidgets('renders empty state when no decisions in queue',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DecisionQueuePanel(
              items: [],
            ),
          ),
        ),
      );

      expect(find.text('ALL OBLIGATIONS RESOLVED'), findsOneWidget);
      expect(
          find.text('No pending decisions in this category.'), findsOneWidget);
    });
  });
}
