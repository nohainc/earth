import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';
import 'package:earth_client/features/institutions/institutions_dialogs.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';
import 'package:earth_client/features/operations/buildings_hub_screen.dart';
import 'package:earth_client/features/operations/real_estate_dialogs.dart';

typedef OpenDialog = Future<void> Function(BuildContext context, ActionSpy spy);

class ActionSpy {
  int calls = 0;
  Future<void> invoke(Future<EarthState> Function() callback) async {
    calls++;
  }
}

Future<void> pumpLauncher(WidgetTester tester, OpenDialog open) async {
  final spy = ActionSpy();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => open(context, spy),
          child: const Text('OPEN'),
        );
      }),
    ),
  ));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<void> pumpWithAction(
    WidgetTester tester, Widget child, ActionSpy spy) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pumpAndSettle();
}

const baseState = EarthState({
  'human': {'id': 'H-01', 'credits': 100000, 'display_name': 'Test Human'},
  'membership': {'corporation_id': 'CORP-01', 'city_id': 'CITY-01'},
  'communities': [
    {
      'id': 'COM-01',
      'name': 'Makers',
      'description': 'A community',
      'member_count': 8
    },
  ],
  'rankings': {
    'cities': [
      {
        'id': 'CITY-01',
        'name': 'Alpha',
        'corporation_id': 'CORP-01',
        'residents': 10
      },
      {
        'id': 'CITY-02',
        'name': 'Beta',
        'corporation_id': 'CORP-01',
        'residents': 20
      },
    ],
    'corporations': [
      {
        'id': 'CORP-01',
        'name': 'Aether',
        'capital_city_name': 'Alpha',
        'member_count': 8
      },
    ],
  },
  'institutions': {
    'city': {
      'id': 'CITY-01',
      'name': 'Alpha',
      'residents': 10,
      'housing_capacity': 20,
      'energy_capacity': 30,
      'treasury': 5000
    },
    'corporation': {
      'id': 'CORP-01',
      'name': 'Aether',
      'capital_city_name': 'Alpha',
      'member_count': 8,
      'treasury': 9000
    },
  },
  'districtZoning': {
    'cityId': 'CITY-01',
    'availablePrivateSlots': 8,
    'availableCivicSlots': 4
  },
  'buildings': [
    {
      'id': 'BLD-01',
      'owner_id': 'H-01',
      'city_id': 'CITY-01',
      'ownership_class': 'private',
      'building_type': 'restaurant',
      'name': 'Bistro',
      'tier': 1,
      'slot_footprint': 1,
      'status': 'active',
      'resource_output_type': 'credits',
      'resource_output_amount': 500,
      'daily_operating_credits': 30
    },
    {
      'id': 'BLD-C',
      'owner_id': 'CITY-01',
      'city_id': 'CITY-01',
      'ownership_class': 'civic',
      'building_type': 'clinic',
      'name': 'Clinic',
      'tier': 1,
      'slot_footprint': 2,
      'status': 'active',
      'resource_output_type': 'health',
      'resource_output_amount': 3
    },
    {
      'id': 'BLD-P',
      'owner_id': 'CITY-01',
      'city_id': 'CITY-01',
      'ownership_class': 'public_investment',
      'building_type': 'transit',
      'name': 'Transit',
      'tier': 1,
      'slot_footprint': 2,
      'status': 'active',
      'total_shares': 100,
      'price_per_share_crd': 250,
      'resource_output_type': 'credits',
      'resource_output_amount': 800
    },
  ],
  'buildingCatalog': [
    {
      'type': 'restaurant',
      'name': 'Bistro',
      'defaultOwnershipClass': 'private',
      'slotFootprint': 1,
      'baseCreditCost': 1000,
      'baseMaterialCost': 10,
      'dailyOperatingCredits': 30,
      'dailyOutputCredits': 500
    },
    {
      'type': 'clinic',
      'name': 'Clinic',
      'defaultOwnershipClass': 'civic',
      'slotFootprint': 2,
      'baseCreditCost': 3000,
      'baseMaterialCost': 20,
      'dailyOutputResourceType': 'health',
      'dailyOutputResourceAmount': 3
    },
  ],
});

void main() {
  group('Community creation and participation action flows', () {
    for (var i = 1; i <= 20; i++) {
      testWidgets(
          'community flow $i performs an action and verifies its result',
          (tester) async {
        final spy = ActionSpy();
        await pumpLauncher(
            tester, (context, _) => showCommunityComposer(context, spy.invoke));
        expect(find.text('Found New Community'), findsOneWidget);
        if (i == 1) {
          await tester.tap(find.text('CANCEL'));
          await tester.pumpAndSettle();
          expect(find.text('Found New Community'), findsNothing);
          expect(spy.calls, 0);
        } else {
          await tester.enterText(
              find.widgetWithText(TextField, 'Community Name (Required)'),
              'Community $i');
          await tester.enterText(
              find.widgetWithText(TextField, 'Manifesto & Purpose (Required)'),
              'Purpose $i');
          if (i.isEven) {
            await tester.tap(find.text('APPROVAL REQUIRED'));
            await tester.pump();
            await tester.enterText(
                find.widgetWithText(
                    TextField, 'Application Question / Requirement (Required)'),
                'Why join?');
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Found Community'));
          await tester.pumpAndSettle();
          expect(spy.calls, 1);
        }
      });
    }
  });

  group('City, corporation, and residency action flows', () {
    for (var i = 1; i <= 20; i++) {
      testWidgets(
          'institution flow $i performs an action and verifies its result',
          (tester) async {
        final spy = ActionSpy();
        if (i <= 5) {
          await pumpLauncher(
              tester,
              (context, _) => showFormationComposer(context, spy.invoke,
                  city: i.isOdd, communityId: 'COM-01', cityId: 'CITY-01'));
          expect(find.text(i.isOdd ? 'Form a City' : 'Form a Corporation'),
              findsOneWidget);
          final field = find.byType(TextField);
          if (i == 1) {
            await tester.tap(find.text('Submit'));
            await tester.pump();
            expect(spy.calls, 0);
          } else if (i == 2) {
            await tester.enterText(field, 'New Institution');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            expect(spy.calls, 0);
          } else {
            await tester.enterText(field, 'Institution $i');
            await tester.tap(find.text('Submit'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        } else if (i <= 10) {
          await pumpLauncher(
              tester,
              (context, _) =>
                  showCorporationWithCapitalDialog(context, spy.invoke));
          final fields = find.byType(TextField);
          if (i == 6) {
            await tester.tap(find.text('FOUND CORPORATION'));
            expect(spy.calls, 0);
          } else if (i == 7) {
            await tester.enterText(fields.at(0), 'Corp');
            await tester.enterText(fields.at(1), 'City');
            await tester.tap(find.text('CANCEL'));
            await tester.pumpAndSettle();
            expect(spy.calls, 0);
          } else {
            await tester.enterText(fields.at(0), 'Corp $i');
            await tester.enterText(fields.at(1), 'City $i');
            await tester.tap(find.text('FOUND CORPORATION'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        } else {
          await pumpLauncher(
              tester,
              (context, _) => showCityChangeDialog(
                  context, baseState, 'CITY-01', spy.invoke));
          expect(find.text('Change City Jurisdiction'), findsOneWidget);
          if (i == 11) {
            expect(find.text('CURRENT JURISDICTION'), findsOneWidget);
            await tester.tap(find.text('CLOSE'));
            expect(spy.calls, 0);
          } else {
            await tester.tap(find.text('MOVE'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        }
      });
    }
  });

  group('Building construction, investment, and removal action flows', () {
    for (var i = 1; i <= 30; i++) {
      testWidgets('building flow $i performs an action and verifies its result',
          (tester) async {
        final spy = ActionSpy();
        if (i <= 10) {
          await pumpLauncher(
              tester,
              (context, _) => showBuildingAcquisitionDialog(context, spy.invoke,
                  baseState.buildingCatalog, 'CITY-01', 8));
          expect(
              find.text('Acquire District Plot & Construct'), findsOneWidget);
          if (i == 1) {
            await tester.tap(find.text('CANCEL'));
            expect(spy.calls, 0);
          } else {
            await tester.enterText(find.byType(TextField), 'Facility $i');
            await tester.tap(find.text('COMMENCE CONSTRUCTION'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        } else if (i <= 20) {
          await pumpLauncher(
              tester,
              (context, _) => showPublicShareInvestDialog(context, spy.invoke,
                  baseState.buildings[2] as Map<String, dynamic>));
          expect(find.text('Invest in Public Megaproject'), findsOneWidget);
          if (i.isOdd) {
            await tester.tap(find.byIcon(Icons.add_circle_outline));
            await tester.pump();
            expect(find.text('2'), findsOneWidget);
          }
          if (i == 12) {
            await tester.tap(find.text('CANCEL'));
            expect(spy.calls, 0);
          } else {
            await tester.tap(find.text('PURCHASE SHARES'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        } else {
          await pumpLauncher(
              tester,
              (context, _) => showDemolishConfirmDialog(context, spy.invoke,
                  baseState.buildings.first as Map<String, dynamic>));
          expect(find.text('Demolish Facility'), findsOneWidget);
          if (i == 21) {
            await tester.tap(find.text('CANCEL'));
            expect(spy.calls, 0);
          } else {
            await tester.tap(find.text('DEMOLISH & RECYCLE'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        }
      });
    }
  });

  group('Rendered building and finance results after actions', () {
    for (var i = 1; i <= 30; i++) {
      testWidgets(
          'result verification $i shows updated institution or finance information',
          (tester) async {
        final spy = ActionSpy();
        if (i <= 10) {
          await pumpWithAction(
              tester,
              BuildingsHubScreen(
                  state: baseState, busy: false, action: spy.invoke),
              spy);
          expect(find.textContaining('Bistro'), findsWidgets);
          if (i.isEven) {
            await tester.tap(find.textContaining('Bistro').first);
            await tester.pumpAndSettle();
            expect(find.textContaining('spaces'), findsWidgets);
          }
        } else if (i <= 20) {
          await pumpWithAction(
              tester,
              InstitutionsCapacityPanel(
                  state: baseState, busy: false, action: spy.invoke),
              spy);
          expect(find.text('CITY BUDGET'), findsWidgets);
          expect(find.textContaining('5000'), findsWidgets);
          if (i.isEven) {
            await tester.tap(find.text('PROPOSE BUDGET'));
            await tester.pumpAndSettle();
            expect(spy.calls, 1);
          }
        } else if (i <= 25) {
          await pumpWithAction(
              tester,
              CorporationOverviewPanel(
                  state: baseState, busy: false, action: spy.invoke),
              spy);
          expect(find.text('CORPORATE BUDGET'), findsWidgets);
          expect(find.textContaining('9000'), findsWidgets);
        } else {
          final finance = {
            'lifeMaintenance': {
              'lastSettlement': {'credits': -12, 'energy': -1}
            },
            'dailyProfile': {'status': 'clean', 'credits': 120, 'energy': -2},
            'taxes': {
              'rules': [
                {'category': 'basic_income', 'rate': 0.1}
              ]
            },
            'protectedMinimum': {'credits': 100},
          };
          await pumpWithAction(
              tester,
              PersonalFinancePanel(
                  state: baseState,
                  busy: false,
                  action: spy.invoke,
                  personalFinanceData: finance),
              spy);
          expect(find.text('PERSONAL FINANCE'), findsOneWidget);
          expect(find.textContaining('470'), findsWidgets);
          expect(find.text('FROM PRIVATE BUILDINGS'), findsOneWidget);
        }
      });
    }
  });
}
