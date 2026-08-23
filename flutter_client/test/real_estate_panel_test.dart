import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/real_estate_panel.dart';
import 'package:earth_client/features/operations/real_estate_dialogs.dart';

void main() {
  testWidgets('RealEstateDistrictPanel renders properties, megaprojects, and labor pool', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 50000},
      'membership': {'city_id': 'CITY-0084'},
      'machines': [
        {
          'id': 'M-01',
          'name': 'Service Drone Alpha',
          'machine_type': 'service-robot-hub',
          'condition': 95,
          'status': 'active',
        },
      ],
      'buildings': [
        {
          'id': 'BLD-01',
          'city_id': 'CITY-0084',
          'owner_id': 'H-0044',
          'ownership_type': 'private',
          'building_type': 'restaurant',
          'name': 'Nova Bistro',
          'tier': 1,
          'condition': 100,
          'max_staff_slots': 4,
          'active_staff_count': 1,
          'upkeep_energy': 0.5,
          'upkeep_food': 0.25,
          'base_revenue_crd': 450.0,
          'status': 'active',
        },
        {
          'id': 'BLD-MUNI-01',
          'city_id': 'CITY-0084',
          'owner_id': 'CITY-0084',
          'ownership_type': 'municipal',
          'building_type': 'geothermal-grid',
          'name': 'New Carthage Geothermal Central',
          'tier': 3,
          'condition': 98,
          'max_staff_slots': 16,
          'active_staff_count': 4,
          'upkeep_materials': 1.5,
          'base_revenue_crd': 850.0,
          'status': 'active',
        },
      ],
      'municipalLabor': [
        {
          'id': 'MLP-01',
          'city_id': 'CITY-0084',
          'human_id': 'H-0044',
          'machine_id': 'M-01',
          'machine_name': 'Service Drone Alpha',
          'machine_type': 'service-robot-hub',
          'status': 'active',
          'accumulated_wages_crd': 384.0,
        },
      ],
      'buildingCatalog': [
        {
          'type': 'restaurant',
          'name': 'Bistro & Molecular Restaurant',
          'category': 'commercial',
          'tier': 1,
          'baseCreditCost': 8500,
          'baseMaterialCost': 120,
          'maxStaffSlots': 4,
          'baseDailyRevenueCrd': 450,
          'description': 'Molecular dining.',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RealEstateDistrictPanel(
              state: state,
              busy: false,
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    // Verify title and metrics
    expect(find.text('URBAN REAL ESTATE & MUNICIPAL DISTRICT'), findsOneWidget);
    expect(find.text('1 PRIVATE'), findsOneWidget);
    expect(find.text('+450 CRD'), findsOneWidget);
    expect(find.text('1 ROBOTS POOLED'), findsOneWidget);

    // Verify building items
    expect(find.text('Nova Bistro (RESTAURANT)'), findsOneWidget);
    expect(find.text('New Carthage Geothermal Central (GEOTHERMAL-GRID)'), findsOneWidget);
    expect(find.text('MUNICIPAL PUBLIC'), findsOneWidget);
    expect(find.text('PRIVATE ESTATE'), findsOneWidget);

    // Verify labor pool section
    expect(find.text('MUNICIPAL SHARED LABOR POOL'), findsOneWidget);
    expect(find.textContaining('Service Drone Alpha (SERVICE-ROBOT-HUB)'), findsOneWidget);
    expect(find.text('WITHDRAW'), findsOneWidget);
  });

  testWidgets('Real estate acquisition dialog opens and renders cost and details', (tester) async {
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
              onPressed: () => showBuildingAcquisitionDialog(
                context,
                (cb) async => cb(),
                const [],
                'CITY-0084',
              ),
              child: const Text('ACQUIRE PLOT'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ACQUIRE PLOT'));
    await tester.pumpAndSettle();

    expect(find.text('Acquire Commercial / Industrial Plot'), findsOneWidget);
    expect(find.text('BUILDING ARCHETYPE'), findsOneWidget);
    expect(find.textContaining('8500 CRD + 120 MAT'), findsOneWidget);
    expect(find.text('PURCHASE & BUILD'), findsOneWidget);
  });
}
