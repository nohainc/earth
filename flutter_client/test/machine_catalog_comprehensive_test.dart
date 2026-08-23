import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/machines_dialogs.dart';
import 'package:earth_client/features/operations/machines_panel.dart';

void main() {
  test('CatalogMachineModel default catalog contains 24 distinct assets across 4 tiers', () {
    expect(CatalogMachineModel.defaultCatalog.length, 24);

    final categories = CatalogMachineModel.defaultCatalog.map((m) => m.category).toSet();
    expect(categories, containsAll(['energy', 'food', 'extraction', 'components', 'compute', 'specialized']));

    final tiers = CatalogMachineModel.defaultCatalog.map((m) => m.tier).toSet();
    expect(tiers, equals({1, 2, 3, 4}));

    final types = CatalogMachineModel.defaultCatalog.map((m) => m.type).toList();
    expect(types.toSet().length, 24); // all unique types

    for (final machine in CatalogMachineModel.defaultCatalog) {
      expect(machine.credit, greaterThan(0));
      expect(machine.material, greaterThan(0));
      expect(machine.capacity, greaterThan(1.0));
      expect(machine.inputPerOutput, greaterThan(0));
      expect(machine.description.isNotEmpty, isTrue);
    }
  });

  testWidgets('MachinesPanel category filtering toggles displayed assets', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 50000},
      'world': {'health': 100},
      'resources': {'energy': 500, 'food': 300, 'material': 200, 'components': 80, 'compute': 50},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      'machines': [
        {
          'id': 'M-01',
          'name': 'Solar Array Alpha',
          'machine_type': 'solar-photovoltaic-array',
          'condition': 95,
          'utilization': 75,
          'productive_capacity': 1.5,
          'maintenance_due': 20,
          'input_resource': 'material',
          'output_resource': 'energy',
          'status': 'active',
        },
        {
          'id': 'M-02',
          'name': 'Deep Crust Drill Beta',
          'machine_type': 'sub-crustal-bore-drill',
          'condition': 80,
          'utilization': 50,
          'productive_capacity': 1.5,
          'maintenance_due': 12,
          'input_resource': 'energy',
          'output_resource': 'material',
          'status': 'active',
        },
        {
          'id': 'M-03',
          'name': 'Quantum Annealer Gamma',
          'machine_type': 'quantum-annealing-rig',
          'condition': 90,
          'utilization': 100,
          'productive_capacity': 2.1,
          'maintenance_due': 15,
          'input_resource': 'energy',
          'output_resource': 'compute',
          'status': 'active',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MachinesPanel(
              state: state,
              busy: false,
              productionCatalog: const [],
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    // Initial state: shows all 3 deployed machines
    expect(find.text('Solar Array Alpha (SOLAR-PHOTOVOLTAIC-ARRAY)'), findsOneWidget);
    expect(find.text('Deep Crust Drill Beta (SUB-CRUSTAL-BORE-DRILL)'), findsOneWidget);
    expect(find.text('Quantum Annealer Gamma (QUANTUM-ANNEALING-RIG)'), findsOneWidget);

    // Filter by ENERGY
    await tester.tap(find.text('⚡ ENERGY'));
    await tester.pumpAndSettle();
    expect(find.text('Solar Array Alpha (SOLAR-PHOTOVOLTAIC-ARRAY)'), findsOneWidget);
    expect(find.text('Deep Crust Drill Beta (SUB-CRUSTAL-BORE-DRILL)'), findsNothing);
    expect(find.text('Quantum Annealer Gamma (QUANTUM-ANNEALING-RIG)'), findsNothing);

    // Filter by COMPUTE
    await tester.ensureVisible(find.text('📡 COMPUTE'));
    await tester.tap(find.text('📡 COMPUTE'));
    await tester.pumpAndSettle();
    expect(find.text('Solar Array Alpha (SOLAR-PHOTOVOLTAIC-ARRAY)'), findsNothing);
    expect(find.text('Deep Crust Drill Beta (SUB-CRUSTAL-BORE-DRILL)'), findsNothing);
    expect(find.text('Quantum Annealer Gamma (QUANTUM-ANNEALING-RIG)'), findsOneWidget);

    // Return to ALL
    await tester.ensureVisible(find.text('ALL (3)'));
    await tester.tap(find.text('ALL (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Solar Array Alpha (SOLAR-PHOTOVOLTAIC-ARRAY)'), findsOneWidget);
    expect(find.text('Deep Crust Drill Beta (SUB-CRUSTAL-BORE-DRILL)'), findsOneWidget);
    expect(find.text('Quantum Annealer Gamma (QUANTUM-ANNEALING-RIG)'), findsOneWidget);
  });

  testWidgets('Acquisition dialog supports 24 machines and category chips', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMachineAcquisitionDialog(
                context,
                (cb) async => cb(),
                const [],
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('Acquire Machine'), findsOneWidget);
    expect(find.text('ALL (24)'), findsOneWidget);
    expect(find.text('⚡ ENERGY'), findsOneWidget);
    expect(find.text('🌾 FOOD'), findsOneWidget);
    expect(find.text('⛏️ MINING'), findsOneWidget);
    expect(find.text('⚙️ FABRICATION'), findsOneWidget);
    expect(find.text('📡 COMPUTE'), findsOneWidget);
    expect(find.text('🤖 SPECIALIZED'), findsOneWidget);

    // Filter by MINING
    await tester.ensureVisible(find.text('⛏️ MINING'));
    await tester.tap(find.text('⛏️ MINING'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DEEP ROTARY BORE DRILL'), findsWidgets);

    // Filter by SPECIALIZED
    await tester.ensureVisible(find.text('🤖 SPECIALIZED'));
    await tester.tap(find.text('🤖 SPECIALIZED'));
    await tester.pumpAndSettle();

    expect(find.textContaining('AUTONOMOUS SERVICE DRONE HUB'), findsWidgets);
  });
}
