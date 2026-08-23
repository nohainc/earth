import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/real_estate_dialogs.dart';
import 'package:earth_client/features/operations/buildings_hub_screen.dart';
import 'package:earth_client/features/operations/building_detail_upgrade_dialog.dart';
import 'package:earth_client/features/operations/patent_licensing_dialog.dart';

void main() {
  const state = EarthState({
    'clock': {'day': 184, 'minute': 100},
    'human': {'id': 'H-0044', 'credits': 50000},
    'membership': {'city_id': 'CITY-0084'},
    'districtZoning': {
      'cityId': 'CITY-0084',
      'cityName': 'New Carthage',
      'population': 15,
      'totalSlots': 11,
      'civicReservedSlots': 4,
      'usedPrivateSlots': 1,
      'usedCivicSlots': 2,
      'availablePrivateSlots': 6,
      'availableCivicSlots': 2,
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
        'daily_operating_credits': 60,
        'upkeep_energy': 0.5,
        'upkeep_food': 0.25,
        'resource_output_type': 'credits',
        'resource_output_amount': 620.0,
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
        'tiers': [
          {
            'tier': 1,
            'name': 'Bistro & Molecular Diner',
            'upgradeCreditCost': 0,
            'upgradeMaterialCost': 0,
            'dailyCreditRevenue': 620,
            'dailyOperatingCredits': 120,
            'unlockedPerks': ['Basic Molecular Dining'],
            'description': 'Base tier.',
          },
          {
            'tier': 2,
            'name': 'Gourmet Gastronomy Lounge',
            'upgradeCreditCost': 7500,
            'upgradeMaterialCost': 90,
            'upgradeComponentsCost': 10,
            'dailyCreditRevenue': 1450,
            'dailyOperatingCredits': 220,
            'unlockedPerks': ['Premium Tasting Menu', 'Corporate Catering Contract'],
            'requiredCityPopulation': 10,
            'description': 'Tier 2 lounge.',
          },
        ],
      },
      {
        'type': 'solar-array-complex',
        'name': 'Solar Concentrator Array',
        'category': 'energy',
        'slotFootprint': 2,
        'baseCreditCost': 10500,
        'baseMaterialCost': 190,
        'dailyOperatingCredits': 80,
        'dailyCreditRevenue': 0,
        'dailyOutputResourceType': 'energy',
        'dailyOutputResourceAmount': 4.5,
        'estimatedPaybackDays': 15,
        'resourceSensitivity': 'low',
        'maintenanceRisk': 'low',
        'primaryEconomicPurpose': 'Clean Photovoltaic Energy',
        'description': 'Solar array field.',
      },
    ],
  });

  testWidgets('BuildingsHubScreen renders 3 tabs and switches between Estates, Planner, and Catalog', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
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
              state: state,
              busy: false,
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('BUILDINGS & URBAN INFRASTRUCTURE HUB'), findsOneWidget);
    expect(find.textContaining('MY DISTRICT ESTATES'), findsOneWidget);
    expect(find.textContaining('STRATEGIC CONSTRUCTION PLANNER'), findsOneWidget);
    expect(find.textContaining('GLOBAL BLUEPRINT CATALOG'), findsOneWidget);

    // Switch to Strategic Construction Planner tab
    await tester.tap(find.textContaining('STRATEGIC CONSTRUCTION PLANNER'));
    await tester.pumpAndSettle();

    expect(find.text('STRATEGIC CONSTRUCTION & ROI PLANNER'), findsOneWidget);
    expect(find.text('ESTIMATED PAYBACK'), findsOneWidget);
    expect(find.text('COMMENCE CONSTRUCTION ON PLOT'), findsOneWidget);

    // Switch to Global Blueprint Catalog tab
    await tester.tap(find.textContaining('GLOBAL BLUEPRINT CATALOG'));
    await tester.pumpAndSettle();

    expect(find.text('EARTH AUTHORITATIVE BLUEPRINT SPECIFICATIONS'), findsOneWidget);
    expect(find.text('Solar Concentrator Array'), findsOneWidget);
  });

  testWidgets('showBuildingDetailUpgradeDialog renders multi-tier tree and progression nodes', (tester) async {
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
              onPressed: () => showBuildingDetailUpgradeDialog(
                context,
                (cb) async => cb(),
                state.buildings.first as Map<String, dynamic>,
                state.buildingCatalog,
              ),
              child: const Text('OPEN TREE'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN TREE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Multi-Tier Upgrade Tree'), findsOneWidget);
    expect(find.textContaining('MULTI-TIER UPGRADE PROGRESSION'), findsOneWidget);
    expect(find.text('TIER 1: Bistro & Molecular Diner'), findsOneWidget);
    expect(find.text('TIER 2: Gourmet Gastronomy Lounge'), findsOneWidget);
    expect(find.text('COMMENCE TIER 2 UPGRADE'), findsOneWidget);
  });

  testWidgets('showPatentLicensingDialog opens with private, civic, and permanent options', (tester) async {
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
              onPressed: () => showPatentLicensingDialog(
                context,
                (cb) async => cb(),
                const {
                  'patentId': 'PAT-DAT-02',
                  'patentName': 'Photonic Neural Architecture',
                  'owningCorporationName': 'Aetheria Systems',
                  'owningCorporationId': 'CORP-001',
                  'privateLicenseCostCrd': 12000,
                  'privateDailyRoyaltyCrd': 150,
                  'cityCivicLicenseCostCrd': 45000,
                  'description': 'Advanced optical interconnect architecture.',
                },
              ),
              child: const Text('OPEN PATENT DIALOG'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN PATENT DIALOG'));
    await tester.pumpAndSettle();

    expect(find.text('Procure Corporate Patent License'), findsOneWidget);
    expect(find.text('Photonic Neural Architecture'), findsOneWidget);
    expect(find.textContaining('Aetheria Systems'), findsOneWidget);
    expect(find.text('30-Day Private Building License'), findsOneWidget);
    expect(find.text('30-Day Municipal City-Wide Civic License'), findsOneWidget);
    expect(find.text('Permanent Civic Sovereign License'), findsOneWidget);
    expect(find.text('PURCHASE & AUTHORIZE'), findsOneWidget);
  });

  testWidgets('Real estate acquisition dialog opens and displays blueprint details', (tester) async {
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
                5,
              ),
              child: const Text('CONSTRUCT BLUEPRINT'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('CONSTRUCT BLUEPRINT'));
    await tester.pumpAndSettle();

    expect(find.text('Acquire District Plot & Construct'), findsOneWidget);
    expect(find.text('ARCHITECTURAL BLUEPRINT'), findsOneWidget);
    expect(find.text('COMMENCE CONSTRUCTION'), findsOneWidget);
  });
}
