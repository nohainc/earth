import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/technology_panel.dart';

const _catalogState = EarthState({
  'technology': {
    'catalog': [
      {
        'id': 'TECH-FOOD-1',
        'code': 'food_science',
        'name': 'Food Science',
        'category': 'LIFE_SUPPORT',
        'description': 'Improves food production efficiency.',
        'researchCostUnits': '18000',
        'researchDurationGameDays': '12',
        'researchPointsRequired': '900',
        'viewerStatus': 'AVAILABLE',
        'effects': [
          {
            'effectType': 'PRODUCTION_OUTPUT',
            'modifierFamily': 'OUTPUT',
            'targetType': 'RESOURCE',
            'targetKey': 'FOOD',
            'modifierBps': 1000,
          }
        ],
        'prerequisites': [],
      },
      {
        'id': 'TECH-AUTO-1',
        'code': 'automation',
        'name': 'Industrial Automation',
        'category': 'INDUSTRY',
        'description': 'Improves industrial output.',
        'researchCostUnits': '25000',
        'researchDurationGameDays': '15',
        'researchPointsRequired': '1000',
        'viewerStatus': 'ACTIVE',
        'effects': [],
        'prerequisites': ['TECH-FOUNDATION'],
      },
      {
        'id': 'TECH-LOCKED-1',
        'code': 'locked_technology',
        'name': 'Locked Technology',
        'category': 'INDUSTRY',
        'description': 'Unavailable until authority is granted.',
        'researchCostUnits': '40000',
        'researchDurationGameDays': '20',
        'researchPointsRequired': '1400',
        'viewerStatus': 'LOCKED',
        'effects': [],
        'prerequisites': ['TECH-PREREQUISITE'],
      },
    ],
    'projects': [
      {
        'id': 'PROJECT-AUTO',
        'name': 'Industrial Automation',
        'targetType': 'TECHNOLOGY',
        'targetId': 'TECH-AUTO-1',
        'status': 'ACTIVE',
        'creditCostUnits': '25000',
        'startedGameDay': 175,
        'progressBps': 5000,
        'remainingGameDays': 3,
        'completionGameDay': 190,
      }
    ],
    'adoptedCodes': [],
    'researchBudget': {
      'authorizedUnits': '100000',
      'committedUnits': '25000',
      'spentUnits': '10000',
      'availableUnits': '65000',
      'status': 'ACTIVE',
    },
    'frontier': [],
  },
});

void main() {
  testWidgets('catalog renders fixed cost, typed effects, status, and countdown',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TechnologyOutcomePanel(state: _catalogState),
        ),
      ),
    ));

    expect(find.text('Food Science'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
    expect(find.textContaining('180.00'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsWidgets);
    expect(find.textContaining('EFFECTS: PRODUCTION OUTPUT'), findsOneWidget);
    expect(find.textContaining('COMPLETION: DAY 190'), findsOneWidget);
    expect(find.textContaining('3 GAME DAYS REMAINING'), findsOneWidget);
    expect(find.textContaining('CORPORATION RESEARCH BUDGET'), findsOneWidget);
  });

  testWidgets('catalog search and status/domain filters use the typed model',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TechnologyOutcomePanel(state: _catalogState),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Locked');
    await tester.pumpAndSettle();
    expect(find.text('Locked Technology'), findsOneWidget);
    expect(find.text('Food Science'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'LOCKED'));
    await tester.pumpAndSettle();
    expect(find.text('Locked Technology'), findsOneWidget);
    expect(find.textContaining('PREREQUISITES: TECH-PREREQUISITE'), findsOneWidget);
  });

  testWidgets('independent players see a read-only Corporation research catalogue',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TechnologyPanel(
            state: _catalogState,
            busy: false,
            initialTab: 1,
            action: _noopAction,
          ),
        ),
      ),
    ));

    expect(find.textContaining('technology catalogue is read-only'), findsOneWidget);
    expect(find.textContaining('Corporation membership is required'), findsOneWidget);
  });
}

Future<void> _noopAction(Future<EarthState> Function() callback) async {}
