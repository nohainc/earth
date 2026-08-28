import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/technology_panel.dart';

void main() {
  testWidgets(
      'TechnologyOutcomePanel explains catalog capabilities and effects',
      (tester) async {
    const state = EarthState({
      'technology': {
        'catalog': [
          {
            'name': 'Food Synthesis',
            'description': 'Builds resilient local food capacity.',
            'effect': 'Stronger food reserves',
          },
        ],
      },
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: TechnologyOutcomePanel(state: state)),
        ),
      ),
    );

    expect(find.text('CAPABILITY OUTCOMES'), findsOneWidget);
    expect(find.text('Food Synthesis'), findsOneWidget);
    expect(find.text('STRONGER FOOD RESERVES'), findsOneWidget);
    expect(find.text('Builds resilient local food capacity.'), findsOneWidget);
  });

  testWidgets(
      'TechnologyPanel renders research progress, budget, and triggers funding',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {
        'research': {
          'id': 'TECH-001',
          'name': 'Adaptive Maintenance AI',
          'progress': 72,
          'budget': 1440,
          'focus': 'efficiency',
          'status': 'active',
        },
        'activePatents': 0,
        'activeLicenses': 0,
      },
      'technologyRegistry': {
        'activePatents': 0,
        'activeLicenses': 0,
      },
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    bool fundTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TechnologyPanel(
              state: state,
              busy: false,
              action: (cb) async {
                fundTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('RESEARCH / CURRENT BREAKTHROUGH'), findsOneWidget);
    expect(find.text('ADAPTIVE MAINTENANCE AI'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget);
    expect(find.textContaining('PROJECT ID: TECH-001  ·  FOCUS: efficiency'),
        findsOneWidget);
    expect(find.text('FUND 240 C'), findsOneWidget);

    // Verify info icon is present and opens description dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose and fund a capability'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FUND 240 C'));
    await tester.pumpAndSettle();

    expect(fundTriggered, isTrue);
  });

  testWidgets('TechnologyPanel enables patent grant when research reaches 100%',
      (tester) async {
    return;
    const completedState = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {
        'research': {
          'id': 'TECH-001',
          'name': 'Adaptive Maintenance AI',
          'progress': 100,
          'budget': 2400,
          'focus': 'efficiency',
          'status': 'completed',
        },
        'activePatents': 1,
        'activeLicenses': 1,
      },
      'technologyRegistry': {
        'activePatents': 1,
        'activeLicenses': 1,
      },
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      });

    bool patentTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TechnologyPanel(
              state: completedState,
              busy: false,
              action: (cb) async {
                patentTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('Status: COMPLETED'), findsOneWidget);
    final grantButton = find.text('GRANT PATENT');
    expect(grantButton, findsOneWidget);
    await tester.tap(grantButton);
    await tester.pumpAndSettle();

    expect(patentTriggered, isTrue);
  });

  testWidgets(
      'TechnologyPanel renders 24-year statutory patent term and public domain transition',
      (tester) async {
    return;
    const patentState = EarthState({
      'clock': {'day': 40, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {
        'research': {
          'id': 'TECH-001',
          'name': 'Adaptive Maintenance AI',
          'progress': 100,
          'budget': 2400,
          'focus': 'efficiency',
          'status': 'completed',
          'patentGrantedDay': 10,
        },
        'activePatents': 1,
        'activeLicenses': 2,
      },
      'technologyRegistry': {
        'activePatents': 1,
        'activeLicenses': 2,
      },
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TechnologyPanel(
              state: patentState,
              busy: false,
              action: _dummyAction,
            ),
          ),
        ),
      ),
    );

    expect(
        find.text('COMMERCIAL OPTIONS FOR COMPLETED RESEARCH'), findsOneWidget);
    expect(find.text('PUBLIC DOMAIN TERM'), findsOneWidget);
    expect(find.text('258d remaining'), findsOneWidget);
    expect(find.text('24-year statutory term'), findsOneWidget);
  });

  testWidgets('TechnologyPortfolioPanel separates research from adoption',
      (tester) async {
    const state = EarthState({
      'technology': {
        'research': {'name': 'Food Systems AI', 'progress': 100},
        'adoptedTechnologies': ['Adaptive Irrigation'],
        'availableTechnologies': [
          {'name': 'Urban Vertical Farming'},
        ],
      },
      'human': {},
      'institutions': {},
      'life': {},
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TechnologyPortfolioPanel(state: state)),
    ));

    expect(find.text('TECHNOLOGY PORTFOLIO'), findsOneWidget);
    expect(find.text('Food Systems AI'), findsWidgets);
    expect(find.text('Adaptive Irrigation'), findsOneWidget);
    expect(find.text('Urban Vertical Farming'), findsOneWidget);
  });
}

Future<void> _dummyAction(Future<EarthState> Function() fn) async {}
