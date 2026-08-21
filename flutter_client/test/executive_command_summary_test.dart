import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/models/decision_queue_item.dart';
import 'package:earth_client/features/command_center/dashboard.dart';
import 'package:earth_client/features/command_center/executive_command_summary.dart';

void main() {
  final sampleState = EarthState({
    'status': {'phase': 'Operational'},
    'world': {'name': 'Earth Prime', 'day': 42, 'population': 12000000},
    'institutions': {
      'city': {'name': 'New Geneva', 'tier': 'Metropolis', 'population': 500000},
    },
    'membership': {'city_id': 'c1'},
    'player': {
      'id': 'p1',
      'credits': 15000,
      'cash': 15000,
      'energy': 100,
      'name': 'Commander Vance',
    },
    'human': {
      'vitality': 95,
      'politicalMaturity': true,
    },
    'time': {'day': 42},
    'market': {
      'prices': {'energy': 10.5, 'materials': 4.2},
      'products': {'energy': {'price': 10.5, 'supply': 500, 'demand': 600}},
      'book': [],
      'trades': [],
      'orders': [],
      'feeRate': 0.01,
    },
    'business': {
      'name': 'Vance Energy Logistics',
      'balance': 5000,
      'energy': 100,
      'solvent': true,
    },
    'machines': [
      {'id': 'm1', 'name': 'Bio Extractor Alpha', 'condition': 45.0, 'status': 'operational'},
    ],
    'contracts': [
      {'id': 'c1', 'title': 'Energy Flow Agreement', 'status': 'accepted', 'days_remaining': 1},
    ],
    'opportunities': [
      {
        'id': 'opp-1',
        'title': 'High Energy Arbitrage Margin',
        'detail': 'Energy clearing price spread is +18% above regional baseline.',
        'signal': 'market',
        'priority': 'high',
      },
    ],
  });

  group('ExecutiveCommandSummary', () {
    testWidgets('renders all three primary executive questions and their telemetry', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? navigatedTo;
      DecisionQueueItem? executedDecision;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExecutiveCommandSummary(
                state: sampleState,
                onNavigate: (sec) => navigatedTo = sec,
                onExecuteDecision: (item) => executedDecision = item,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify Question 1: Situation
      expect(find.text('WHAT IS MY CURRENT SITUATION?'), findsOneWidget);
      expect(find.text('PERSONAL FINANCES'), findsOneWidget);
      expect(find.text('BUSINESS HEALTH'), findsOneWidget);

      // Verify Question 2: What Changed
      expect(find.text('WHAT CHANGED SINCE MY LAST VISIT?'), findsOneWidget);
      expect(find.text('DAY 42 CHRONICLE'), findsOneWidget);

      // Verify Question 3: Decision Next
      expect(find.text('WHAT DECISION SHOULD I MAKE NEXT?'), findsOneWidget);
      expect(find.text('LIVE STRATEGIC OPPORTUNITIES'), findsOneWidget);
      expect(find.text('High Energy Arbitrage Margin'), findsOneWidget);

      // Verify Briefing Breakdown is always visible
      expect(find.text('OVERNIGHT REVENUE'), findsOneWidget);

      // Test Opportunity Exploit navigation
      await tester.tap(find.text('EXPLOIT').first);
      await tester.pump();
      expect(navigatedTo, equals('market'));

      // Test Decision Action
      final actionButton = find.byType(ElevatedButton).first;
      await tester.tap(actionButton);
      await tester.pump();
      expect(executedDecision, isNotNull);
    });

    testWidgets('Dashboard integrates ExecutiveCommandSummary seamlessly in command section', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Dashboard(
                state: sampleState,
                busy: false,
                selectedSection: 'command',
                sectionKeys: const {},
                events: const [],
                notifications: const [],
                ownershipEvents: const [],
                businessOwnership: const {},
                businessFinancials: const {},
                businessProfile: const {},
                personalFinanceData: const {},
                pantheon: const {},
                contracts: const [],
                authorityEvents: const [],
                membershipEvents: const [],
                marketHistory: const {},
                productionCatalog: const [],
                unreadNotifications: 0,
                action: (_) async {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ExecutiveCommandSummary), findsOneWidget);
      expect(find.text('WHAT IS MY CURRENT SITUATION?'), findsOneWidget);
      expect(find.text('WHAT CHANGED SINCE MY LAST VISIT?'), findsOneWidget);
      expect(find.text('WHAT DECISION SHOULD I MAKE NEXT?'), findsOneWidget);
    });
  });
}
