import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/buildings_hub_screen.dart';

void main() {
  final state = EarthState({
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
        'condition': 80,
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
        'estimatedPaybackDays': 17,
        'resourceSensitivity': 'medium',
        'maintenanceRisk': 'low',
        'primaryEconomicPurpose': 'Liquid Credit Profit',
        'description': 'Molecular dining eatery.',
      },
    ],
  });

  for (final viewport in [const Size(375, 812), const Size(768, 1024), const Size(1440, 900)]) {
    testWidgets('Buildings page golden ${viewport.width.toInt()}px', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        theme: createEarthTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuildingsHubScreen(state: state, busy: false, action: (_) async {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/qa/buildings_${viewport.width.toInt()}.png'),
      );
    });
  }
}
