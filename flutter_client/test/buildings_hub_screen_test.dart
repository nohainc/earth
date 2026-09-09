import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/buildings_hub_screen.dart';

void main() {
  const testState = EarthState({
    'clock': {'day': 184, 'minute': 100},
    'human': {'id': 'H-0044', 'credits': 50000},
    'membership': {'city_id': 'CITY-0084'},
    'districtZoning': {
      'cityId': 'CITY-0084',
      'cityName': 'New Carthage',
      'population': 15,
      'totalSlots': 12,
      'civicReservedSlots': 4,
      'usedPrivateSlots': 2,
      'usedCivicSlots': 2,
      'availablePrivateSlots': 6,
      'availableCivicSlots': 2,
    },
    'resources': {
      'materials': 500.0,
      'energy': 100.0,
    },
    'buildings': [
      {
        'id': 'BLD-01',
        'city_id': 'CITY-0084',
        'owner_id': 'H-0044',
        'ownership_class': 'private',
        'building_type': 'restaurant',
        'name': 'Nova Molecular Bistro',
        'tier': 1,
        'condition': 95,
        'slot_footprint': 1,
        'operating_policy': 'balanced',
        'auto_repair_enabled': true,
        'daily_operating_credits': 60,
        'upkeep_energy': 0.5,
        'upkeep_food': 0.25,
        'resource_output_type': 'credits',
        'resource_output_amount': 620.0,
        'status': 'active',
      },
      {
        'id': 'BLD-02',
        'city_id': 'CITY-0084',
        'owner_id': 'H-0044',
        'ownership_class': 'private',
        'building_type': 'restaurant',
        'name': 'Nova Molecular Bistro',
        'tier': 2,
        'condition': 75,
        'slot_footprint': 1,
        'operating_policy': 'balanced',
        'auto_repair_enabled': true,
        'daily_operating_credits': 80,
        'upkeep_energy': 0.5,
        'upkeep_food': 0.25,
        'resource_output_type': 'credits',
        'resource_output_amount': 800.0,
        'status': 'active',
      },
      {
        'id': 'BLD-CIVIC-01',
        'city_id': 'CITY-0084',
        'owner_id': 'CITY-0084',
        'ownership_class': 'civic',
        'building_type': 'geothermal-grid',
        'name': 'New Carthage Geothermal Core',
        'tier': 2,
        'condition': 98,
        'slot_footprint': 2,
        'operating_policy': 'balanced',
        'daily_operating_credits': 100,
        'upkeep_materials': 1.5,
        'resource_output_type': 'credits',
        'resource_output_amount': 850.0,
        'status': 'active',
      },
      {
        'id': 'BLD-PUB-01',
        'city_id': 'CITY-0084',
        'owner_id': 'CITY-0084',
        'ownership_class': 'public_investment',
        'building_type': 'transit-hyperloop',
        'name': 'Hyperloop Terminal Express',
        'tier': 3,
        'condition': 100,
        'slot_footprint': 3,
        'total_shares': 100,
        'price_per_share_crd': 500,
        'operating_policy': 'high_output',
        'resource_output_type': 'credits',
        'resource_output_amount': 1800.0,
        'status': 'active',
      },
    ],
    'investmentShares': [
      {
        'building_id': 'BLD-PUB-01',
        'investor_id': 'H-0044',
        'shares_owned': 10,
        'invested_credits': 5000,
      },
    ],
    'civicDividends': [
      {
        'day': 183,
        'city_id': 'CITY-0084',
        'total_surplus_crd': 12000,
        'base_ubi_per_resident_crd': 560,
        'participation_bonus_per_resident_crd': 240,
      },
    ],
    'buildingCatalog': [
      {
        'type': 'restaurant',
        'name': 'Bistro & Molecular Restaurant',
        'category': 'commercial',
        'defaultOwnershipClass': 'private',
        'slotFootprint': 1,
        'baseCreditCost': 8500,
        'baseMaterialCost': 120,
        'dailyOperatingCredits': 120,
        'dailyCreditRevenue': 620,
        'estimatedPaybackDays': 17,
        'resourceSensitivity': 'medium',
        'maintenanceRisk': 'low',
        'primaryEconomicPurpose': 'Liquid Credit Profit',
        'description': 'Molecular dining eatery.',
      },
      {
        'type': 'geothermal-grid',
        'name': 'Geothermal Sub-Surface Well',
        'category': 'energy',
        'defaultOwnershipClass': 'civic',
        'slotFootprint': 2,
        'baseCreditCost': 25000,
        'baseMaterialCost': 450,
        'dailyOperatingCredits': 150,
        'dailyCreditRevenue': 0,
        'dailyOutputResourceType': 'energy',
        'dailyOutputResourceAmount': 18.0,
        'primaryEconomicPurpose': 'Civic Base Energy',
        'description': 'Municipal geothermal power generation.',
      },
    ],
  });

  group('BuildingsHubScreen Comprehensive Unit & UI Tests', () {
    testWidgets('Grouped buildings display aggregated count, total spaces, and combined output', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Verify grouped header shows 2 instances
      expect(find.text('Nova Molecular Bistro × 2'), findsOneWidget);
      // Total space is 1 + 1 = 2 spaces
      expect(find.textContaining('2 SPACES'), findsOneWidget);
      // Aggregated resource items exist in the widget tree
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsWidgets);
      expect(find.byIcon(Icons.bolt_rounded), findsWidgets);
    });

    testWidgets('Expanding grouped buildings reveals per-item individual details and collapse hides them', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Prior to expansion, individual #1 / #2 headers are not rendered
      expect(find.textContaining('#1  ·  1 space'), findsNothing);
      expect(find.textContaining('#2  ·  1 space'), findsNothing);

      // Tap on the group row to expand
      await tester.tap(find.text('Nova Molecular Bistro × 2'));
      await tester.pumpAndSettle();

      // Now individual items #1 and #2 are visible
      expect(find.textContaining('#1  ·  1 space'), findsOneWidget);
      expect(find.textContaining('#2  ·  1 space'), findsOneWidget);

      // Tap again to collapse
      await tester.tap(find.text('Nova Molecular Bistro × 2'));
      await tester.pumpAndSettle();

      expect(find.textContaining('#1  ·  1 space'), findsNothing);
      expect(find.textContaining('#2  ·  1 space'), findsNothing);
    });

    testWidgets('Common operating policy buttons invoke action callback with correct parameters', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int actionCallCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async {
                  actionCallCount++;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Frugal −30%'), findsOneWidget);
      expect(find.text('High output +30%'), findsOneWidget);

      // Tap Frugal policy
      await tester.tap(find.text('Frugal −30%'));
      await tester.pumpAndSettle();

      // Invocations executed for both items in the group
      expect(actionCallCount, 2);
    });

    testWidgets('Controls are disabled when busy is true', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int actionsTriggered = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: true, // BUSY
                action: (cb) async {
                  actionsTriggered++;
                },
              ),
            ),
          ),
        ),
      );

      // Tapping Frugal policy when busy should not invoke callback
      await tester.tap(find.text('Frugal −30%'));
      await tester.pumpAndSettle();
      expect(actionsTriggered, 0);
    });

    testWidgets('Information dialogs open on info button tap', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Tap Operating policy info button
      await tester.tap(find.byTooltip('Policy information'));
      await tester.pumpAndSettle();

      expect(find.text('Operating policy'), findsOneWidget);
      expect(find.textContaining('Normal uses standard output and operating cost'), findsOneWidget);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Normal uses standard output and operating cost'), findsNothing);
    });

    testWidgets('Ownership tabs correctly isolate Private, Civic, and Public Investment buildings', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // 1. Private tab (Default)
      expect(find.text('PRIVATE'), findsOneWidget);
      expect(find.text('Nova Molecular Bistro × 2'), findsOneWidget);
      expect(find.text('BUILT'), findsWidgets);
      expect(find.text('CATALOG'), findsWidgets);

      // 2. Switch to combined Civic tab
      expect(find.text('CIVIC'), findsOneWidget);
      await tester.tap(find.text('CIVIC'));
      await tester.pumpAndSettle();

      expect(find.text('CIVIC'), findsOneWidget);
      expect(find.text('BUILT'), findsWidgets);
      expect(find.text('CATALOG'), findsWidgets);

      // Both civic and public investment buildings appear under Civic tab
      expect(find.text('New Carthage Geothermal Core × 1'), findsOneWidget);
      expect(find.text('Hyperloop Terminal Express × 1'), findsOneWidget);

      // Verify portfolio summary header metrics
      expect(find.text('SHARES HELD'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('INVESTED'), findsOneWidget);
      expect(find.text('5000 C'), findsOneWidget);

      // Both civic and public investment buildings appear directly under Civic tab without chip filters
      expect(find.text('ALL (2)'), findsNothing);
      expect(find.text('CIVIC (1)'), findsNothing);
      expect(find.text('INVEST (1)'), findsNothing);

      // Expand public investment group to verify individual details
      await tester.tap(find.text('Hyperloop Terminal Express × 1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Available shares: 90 / 100'), findsOneWidget);
      expect(find.textContaining('You hold: 10'), findsOneWidget);
      expect(find.text('INVEST IN SHARES'), findsOneWidget);
    });

    testWidgets('Narrow viewport (375px mobile) switches to single-column layout with sub-tabs', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: testState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // On narrow viewport, sub-tabs BUILT and CATALOG are present
      expect(find.text('BUILT'), findsOneWidget);
      expect(find.text('CATALOG'), findsOneWidget);
      expect(find.text('Nova Molecular Bistro × 2'), findsOneWidget);

      // Switch to CATALOG sub-tab
      await tester.tap(find.text('CATALOG'));
      await tester.pumpAndSettle();

      expect(find.text('Bistro & Molecular Restaurant'), findsOneWidget);
    });

    testWidgets('Independent citizen sees only private buildings and no ownership tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const independentState = EarthState({
        'clock': {'day': 184, 'minute': 100},
        'human': {'id': 'H-0044', 'credits': 50000},
        'membership': null, // Independent
        'institutions': {},
        'districtZoning': {},
        'resources': {},
        'buildings': [
          {
            'id': 'BLD-01',
            'city_id': 'CITY-0084',
            'owner_id': 'H-0044',
            'ownership_class': 'private',
            'building_type': 'restaurant',
            'name': 'Nova Molecular Bistro',
            'tier': 1,
            'slot_footprint': 1,
            'operating_policy': 'balanced',
            'daily_operating_credits': 60,
            'resource_output_type': 'credits',
            'resource_output_amount': 620.0,
            'status': 'active',
          },
        ],
        'investmentShares': [],
        'civicDividends': [],
        'buildingCatalog': [
          {
            'type': 'restaurant',
            'name': 'Bistro & Molecular Restaurant',
            'category': 'commercial',
            'defaultOwnershipClass': 'private',
            'slotFootprint': 1,
            'baseCreditCost': 8500,
            'baseMaterialCost': 120,
            'dailyOperatingCredits': 120,
            'dailyCreditRevenue': 620,
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: independentState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Ownership tabs should not exist for independent citizen
      expect(find.text('PRIVATE (1)'), findsNothing);
      expect(find.text('CIVIC (0)'), findsNothing);
      expect(find.text('INVEST (0)'), findsNothing);

      // Private content is rendered directly
      expect(find.text('Nova Molecular Bistro × 1'), findsOneWidget);
      expect(find.text('BUILT'), findsWidgets);
      expect(find.text('CATALOG'), findsWidgets);

      // Open spaces shows 9 (10 from default Tier 1 estate deed minus 1 slot used)
      expect(find.text('OPEN SPACES'), findsOneWidget);
      expect(find.text('9'), findsWidgets);
      expect(find.text('SPACES USED'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      // District zoning & capacity widget is not displayed
      expect(find.text('BUILDING CAPACITY & DISTRICT ZONING'), findsNothing);
    });

    testWidgets('Unresearched upgrade shows RESEARCH TIER button and opens research dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Create state where Tier 2 is in catalog, but Tier 3 is not
      final customState = EarthState({
        ...testState.json,
        'buildingCatalog': [
          ...testState.buildingCatalog,
          {
            'type': 'restaurant',
            'tier': 2,
            'name': 'Nova Molecular Bistro (Tier 2)',
            'category': 'commercial',
            'defaultOwnershipClass': 'private',
            'slotFootprint': 1,
            'baseCreditCost': 9500,
            'baseMaterialCost': 140,
            'dailyOperatingCredits': 140,
            'dailyCreditRevenue': 800,
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: customState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Expand the bistro group
      await tester.tap(find.text('Nova Molecular Bistro × 2'));
      await tester.pumpAndSettle();

      // Item #1 is tier 1 -> tier 2 exists in catalog -> shows UPGRADE TO TIER 2
      // Item #2 is tier 2 -> tier 3 is NOT in catalog -> shows RESEARCH TIER 3
      expect(find.text('UPGRADE TO TIER 2'), findsOneWidget);
      expect(find.text('RESEARCH TIER 3'), findsOneWidget);

      // Tap RESEARCH TIER 3 button
      await tester.ensureVisible(find.text('RESEARCH TIER 3'));
      await tester.tap(find.text('RESEARCH TIER 3'));
      await tester.pumpAndSettle();

      // Research dialog opens
      expect(find.text('Initiate R&D Project'), findsOneWidget);
      expect(find.textContaining('Nova Molecular Bistro · Tier 2 → Tier 3'), findsOneWidget);
      expect(find.text('CONFIRM R&D PROJECT'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
    });

    testWidgets('Civic building tab displays urban district module with research or propose upgrade button', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final civicState = EarthState({
        ...testState.json,
        'buildings': [
          {
            'id': 'b-civic-1',
            'owner_id': 'city-gov-1',
            'city_id': 'CITY-0084',
            'name': 'Urban District Module',
            'building_type': 'urban-district-module',
            'tier': 1,
            'status': 'active',
            'condition': 100,
            'slot_footprint': 1,
            'ownership_class': 'civic',
            'daily_operating_credits': 0,
            'resource_output_type': 'housing',
            'resource_output_amount': 25,
            'upkeep_energy': 0.0,
            'upkeep_food': 0.0,
            'upkeep_materials': 0.0,
            'upkeep_components': 0.0,
            'upkeep_compute': 0.0,
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuildingsHubScreen(
                state: civicState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Switch to Civic tab
      await tester.tap(find.text('CIVIC'));
      await tester.pumpAndSettle();

      // Urban District Module is displayed in group header
      expect(find.text('Urban District Module × 1'), findsOneWidget);

      // Expand group
      await tester.tap(find.text('Urban District Module × 1'));
      await tester.pumpAndSettle();

      // Tier 2 is not in catalog -> displays PROPOSE CIVIC RESEARCH TIER 2 button for civic building
      expect(find.text('PROPOSE CIVIC RESEARCH TIER 2'), findsOneWidget);

      // Tap PROPOSE CIVIC RESEARCH TIER 2 button
      await tester.tap(find.text('PROPOSE CIVIC RESEARCH TIER 2'));
      await tester.pumpAndSettle();

      // Research dialog opens
      expect(find.text('Propose Civic Research'), findsOneWidget);
      expect(find.textContaining('Urban District Module · Tier 1 → Tier 2'), findsOneWidget);
    });
  });
}

