import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/decision_queue_item.dart';
import 'package:earth_client/features/command_center/decision_queue_panel.dart';

void main() {
  group('DecisionQueueItem Model', () {
    test('normalizes only canonical navigation routes', () {
      final item = DecisionQueueItem.fromJson(const {
        'id': 'legacy-route',
        'category': 'house',
        'targetRoute': 'territory',
      });
      expect(item.targetRoute, 'house');
    });

    test('serializes and deserializes JSON correctly', () {
      const item = DecisionQueueItem(
        id: 'dec-1',
        category: 'finance',
        title: 'House capacity rent requires urgent settlement',
        whyItMatters: 'Unpaid capacity rent restricts expansion.',
        deadline: 'Before the next settlement',
        expectedImpact: 'Restore the House to good standing.',
        riskLevel: 'critical',
        primaryActionLabel: 'Review Finance',
        targetRoute: 'finance',
        urgencyScore: 98.0,
      );

      final json = item.toJson();
      final fromJson = DecisionQueueItem.fromJson(json);

      expect(fromJson.id, 'dec-1');
      expect(fromJson.category, 'finance');
      expect(fromJson.title, 'House capacity rent requires urgent settlement');
      expect(fromJson.whyItMatters, 'Unpaid capacity rent restricts expansion.');
      expect(fromJson.riskLevel, 'critical');
      expect(fromJson.actionStatus, 'CRITICAL');
      expect(fromJson.actionStatusColor, const Color(0xFFEF4444));
      expect(fromJson.primaryActionLabel, 'Review Finance');
      expect(fromJson.targetRoute, 'finance');
      expect(fromJson.categoryIcon, Icons.account_balance_wallet_outlined);
    });

  });

  group('DecisionQueuePanel Widget', () {
    testWidgets(
        'renders header, filter tabs, decision cards, and triggers action',
        (tester) async {
      final items = [
        for (final item in const [
          ['decision-house-energy', 'house', 'House ENERGY access needs attention', 'life'],
          ['decision-building-suspended', 'buildings', 'A building is suspended from operation', 'buildings'],
          ['decision-building-utilization', 'buildings', 'A building is operating below capacity', 'buildings'],
          ['decision-capacity-arrears', 'finance', 'House capacity rent requires urgent settlement', 'finance'],
          ['decision-governance-vote', 'governance', 'You have an unresolved governance vote', 'governance'],
          ['decision-research', 'technology', 'Research funding is available', 'technology'],
          ['decision-successor', 'house', 'A house decision is pending', 'house'],
        ])
          DecisionQueueItem(
            id: item[0], category: item[1], title: item[2],
            whyItMatters: 'Server-authored V5 decision', deadline: 'Day 185',
            expectedImpact: 'Review the affected V5 system', riskLevel: 'high',
            primaryActionLabel: item[2] == 'House ENERGY access needs attention'
                ? 'Review Life & Services' : 'VIEW',
            targetRoute: item[3]),
      ];
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
      expect(find.text('ACTION QUEUE'), findsOneWidget);
      expect(find.textContaining('CRITICAL'), findsOneWidget);
      expect(find.textContaining('TOTAL DECISIONS'), findsOneWidget);

      // Verify Filter Pills
      expect(find.textContaining('ALL ('), findsOneWidget);
      expect(find.textContaining('CRITICAL ('), findsOneWidget);

      // Verify Decision Card Titles
      expect(find.text('House ENERGY access needs attention'), findsOneWidget);
      expect(find.text('A building is suspended from operation'), findsOneWidget);
      expect(find.text('A building is operating below capacity'), findsOneWidget);
      expect(find.text('House capacity rent requires urgent settlement'), findsOneWidget);
      expect(find.text('You have an unresolved governance vote'), findsOneWidget);
      expect(find.text('Research funding is available'), findsOneWidget);
      expect(find.text('A house decision is pending'), findsOneWidget);

      // Verify Action Button Tap
      final actionBtn = find.text('REVIEW LIFE & SERVICES');
      expect(actionBtn, findsOneWidget);
      await tester.ensureVisible(actionBtn);
      await tester.pumpAndSettle();
      await tester.tap(actionBtn);
      await tester.pump();

      expect(executedDecision?.primaryActionLabel, 'Review Life & Services');
      expect(executedDecision?.targetRoute, 'life');

      // Test Filtering Tabs
      final governanceTab = find.text('GOVERNANCE');
      await tester.ensureVisible(governanceTab);
      await tester.pumpAndSettle();
      await tester.tap(governanceTab);
      await tester.pumpAndSettle();

      // In Civic & House filter: governance, technology, house, finance should be present
      expect(find.text('You have an unresolved governance vote'), findsOneWidget);
      expect(find.text('A house decision is pending'), findsOneWidget);
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

      expect(find.text('NO ACTION REQUIRED'), findsNWidgets(2));
      expect(
          find.text('NO ACTION REQUIRED'), findsOneWidget);
    });

    testWidgets('renders the same V5 queue contract in light and dark themes',
        (tester) async {
      const item = DecisionQueueItem(
        id: 'governance-1',
        category: 'governance',
        title: 'Vote on capacity policy',
        whyItMatters: 'Your House is eligible to vote.',
        deadline: 'Day 190',
        expectedImpact: 'Apply your House ballot.',
        riskLevel: 'medium',
        primaryActionLabel: 'Vote',
        targetRoute: 'governance',
      );
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: DecisionQueuePanel(items: [item])),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Vote on capacity policy'), findsOneWidget);
        expect(find.text('GOVERNANCE'), findsWidgets);
      }
    });
  });
}
