import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/real_estate_panel.dart';
import 'package:earth_client/features/operations/real_estate_dialogs.dart';

void main() {
  testWidgets('RealEstateDistrictPanel renders zoning visualizer, self-contained buildings, and civic dividends', (tester) async {
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
          'ownership_type': 'private',
          'building_type': 'restaurant',
          'name': 'Nova Molecular Bistro',
          'tier': 1,
          'condition': 95,
          'slot_footprint': 1,
          'operating_policy': 'balanced',
          'daily_operating_credits': 60,
          'upkeep_energy': 0.5,
          'upkeep_food': 0.25,
          'base_revenue_crd': 620.0,
          'status': 'active',
        },
        {
          'id': 'BLD-CIVIC-01',
          'city_id': 'CITY-0084',
          'owner_id': 'CITY-0084',
          'ownership_class': 'civic',
          'ownership_type': 'municipal',
          'building_type': 'geothermal-grid',
          'name': 'New Carthage Geothermal Core',
          'tier': 2,
          'condition': 98,
          'slot_footprint': 2,
          'operating_policy': 'balanced',
          'daily_operating_credits': 100,
          'upkeep_materials': 1.5,
          'base_revenue_crd': 850.0,
          'status': 'active',
        },
        {
          'id': 'BLD-PUB-01',
          'city_id': 'CITY-0084',
          'owner_id': 'CITY-0084',
          'ownership_class': 'public_investment',
          'ownership_type': 'public_investment',
          'building_type': 'transit-hyperloop',
          'name': 'Hyperloop Terminal Express',
          'tier': 3,
          'condition': 100,
          'slot_footprint': 3,
          'total_shares': 100,
          'price_per_share_crd': 500,
          'operating_policy': 'high_output',
          'base_revenue_crd': 1800.0,
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
          'name': 'Bistro & Molecular Diner',
          'category': 'commercial',
          'slotFootprint': 1,
          'baseCreditCost': 8500,
          'baseMaterialCost': 120,
          'dailyOperatingCredits': 60,
          'dailyInputEnergy': 0.50,
          'dailyInputFood': 0.25,
          'dailyOutputCredits': 620,
          'description': 'Molecular dining eatery.',
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

    // Verify Title & Metrics
    expect(find.text('URBAN DISTRICT & REAL ESTATE INFRASTRUCTURE'), findsOneWidget);
    expect(find.textContaining('1 SITES'), findsOneWidget);
    expect(find.text('+560 CRD'), findsOneWidget); // 620 - 60 net yield
    expect(find.textContaining('10 SHARES'), findsOneWidget);

    // Verify Zoning Visualizer
    expect(find.text('CITY DISTRICT LAND ZONING & FOOTPRINT MAP'), findsOneWidget);
    expect(find.textContaining('Formula: 8 + ⌊Pop/5⌋'), findsOneWidget);

    // Verify Building Cards
    expect(find.text('Nova Molecular Bistro'), findsOneWidget);
    expect(find.text('PRIVATE ESTATE'), findsOneWidget);
    expect(find.text('CIVIC UTILITY'), findsOneWidget);
    expect(find.text('PUBLIC INVESTMENT'), findsOneWidget);

    // Verify Policy Selectors & Buttons
    expect(find.text('Balanced (1.0x)'), findsNWidgets(1));
    expect(find.text('UPGRADE (TIER 2)'), findsOneWidget);
    expect(find.text('DEMOLISH / RECYCLE'), findsOneWidget);

    // Verify Civic Dividends Section
    expect(find.text('CIVIC DIVIDENDS & PUBLIC MEGAPROJECT SHARES'), findsOneWidget);
    expect(find.text('GAME DAY 183 PAYOUT'), findsOneWidget);
    expect(find.text('TOTAL SURPLUS: +12000 CRD'), findsOneWidget);
    expect(find.text('BASE UBI: +560 CRD'), findsOneWidget);
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
