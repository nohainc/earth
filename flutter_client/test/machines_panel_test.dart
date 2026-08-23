import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/machines_panel.dart';

void main() {
  testWidgets('MachinesPanel renders machine inventory, condition, utilization and actions',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {'material': 200, 'components': 80},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      'machines': [
        {
          'id': 'M-H0044-01',
          'name': 'Primary Fabrication Rig',
          'machine_type': 'fabrication-rig',
          'condition': 88,
          'utilization': 50,
          'productive_capacity': 1.2,
          'maintenance_due': 10,
          'input_resource': 'material',
          'output_resource': 'components',
          'status': 'active',
        },
      ],
    });

    String? executedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MachinesPanel(
              state: state,
              busy: false,
              productionCatalog: const [],
              action: (cb) async {
                executedAction = 'action_executed';
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('AUTOMATION / MACHINE INVENTORY'), findsOneWidget);
    expect(find.textContaining('Primary Fabrication Rig (FABRICATION-RIG)'), findsOneWidget);
    expect(find.text('88% COND'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.textContaining('Flow: MATERIAL → COMPONENTS · Capacity: 1.2x'), findsOneWidget);
    expect(find.text('MAINTAIN (10 COMP)'), findsOneWidget);
    expect(find.text('UPGRADE (+0.2x)'), findsOneWidget);
    expect(find.text('SELL MACHINE'), findsOneWidget);
    expect(find.text('RECYCLE'), findsOneWidget);

    // Upgrade dialog
    await tester.tap(find.text('UPGRADE (+0.2x)'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade machine'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
    await tester.pumpAndSettle();
    expect(executedAction, 'action_executed');

    // Recycle dialog
    await tester.tap(find.text('RECYCLE'));
    await tester.pumpAndSettle();
    expect(find.text('Recycle machine?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Recycle'));
    await tester.pumpAndSettle();
    expect(executedAction, 'action_executed');
  });

  testWidgets('MachinesPanel opens acquisition dialog and submits new machine',
      (tester) async {
    const emptyState = EarthState({
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
      'machines': [],
    });

    bool acquireTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MachinesPanel(
              state: emptyState,
              busy: false,
              productionCatalog: const [],
              action: (cb) async {
                acquireTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('No registered machines in active inventory.'), findsOneWidget);
    expect(find.text('ACQUIRE MACHINE'), findsOneWidget);

    await tester.tap(find.text('ACQUIRE MACHINE'));
    await tester.pumpAndSettle();

    expect(find.text('Acquire Machine'), findsOneWidget);
    expect(find.text('Acquire'), findsOneWidget);

    await tester.tap(find.text('Acquire'));
    await tester.pumpAndSettle();

    expect(acquireTriggered, isTrue);
  });

  testWidgets('MachinesPanel acquisition dialog handles string-formatted numbers in catalog safely',
      (tester) async {
    const emptyState = EarthState({
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
      'machines': [],
    });

    final stringCatalog = [
      {
        'sector': 'energy',
        'output': 'energy',
        'catalog': [
          {
            'type': 'solar-array',
            'name': 'Photovoltaic Array',
            'category': 'energy',
            'tier': '1',
            'output': 'energy',
            'credit': '3200',
            'material': '50',
            'capacity': '1.5',
            'description': 'Solar energy harvester.',
          },
        ],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MachinesPanel(
              state: emptyState,
              busy: false,
              productionCatalog: stringCatalog,
              action: (cb) async => cb(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ACQUIRE MACHINE'));
    await tester.pumpAndSettle();

    // Verify it opened without throwing type error
    expect(find.text('Acquire Machine'), findsOneWidget);
    expect(find.textContaining('3200 CR + 50 Mat'), findsOneWidget);
  });
}

