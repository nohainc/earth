import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/dashboard.dart';
import 'package:earth_client/features/finance/personal_finance_panel.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';
import 'package:earth_client/features/operations/buildings_hub_screen.dart';

void main() {
  group('Living Costs, City Budget & Corporate Budget Suite', () {
    testWidgets('Personal Living Costs displays maintenance deltas, protected reserve, and alert banner on unpaid shortfall', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const state = EarthState({
        'human': {'id': 'H-0044', 'credits': 50000},
        'buildings': [],
        'investmentShares': [],
        'finance': {},
      });

      final personalFinanceWithShortfall = {
        'protectedMinimum': {'credits': 100},
        'lifeMaintenance': {
          'unpaidTotal': 45.0,
          'lastSettlement': {
            'food_used': 1.0,
            'energy_used': 1.5,
            'compute_used': 0.5,
            'credits_for_resources': 12.0,
          },
        },
        'dailyProfile': {
          'status': 'clean',
          'credits_delta': -20.0,
          'food_delta': -1.0,
          'energy_delta': -1.5,
          'compute_delta': -0.5,
        },
        'taxes': {
          'rules': [
            {'category': 'basic_income', 'rate': 0.05},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalFinancePanel(
                state: state,
                busy: false,
                personalFinanceData: personalFinanceWithShortfall,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Section Headings
      expect(find.text('PERSONAL FINANCE'), findsOneWidget);
      expect(find.text('DAILY INCOME'), findsOneWidget);
      expect(find.text('LIFE MAINTENANCE'), findsOneWidget);
      expect(find.text('YOUR DAILY RESULT'), findsOneWidget);

      // Unpaid alert and status pill
      expect(find.text('NEEDS ATTENTION'), findsOneWidget);
      expect(find.textContaining('45 C of essential costs remain unpaid'), findsOneWidget);

      // Protected reserve notice
      expect(find.textContaining('Protected reserve: 100 C'), findsOneWidget);
    });

    testWidgets('InstitutionsCapacityPanel renders City Budget, municipal treasury, explanation, and service capacity ratios', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const cityState = EarthState({
        'human': {'id': 'H-0044', 'standing': 85},
        'membership': {'city_id': 'CITY-0084'},
        'institutions': {
          'city': {
            'id': 'CITY-0084',
            'name': 'New Carthage',
            'residents': 140,
            'housing_capacity': 180,
            'energy_capacity': 300,
            'treasury': 450000.0,
          },
        },
        'world': {
          'serviceRatios': {
            'housing': 0.78,
            'energy': 0.92,
            'connectivity': 0.85,
            'health': 0.64,
          },
        },
        'cityMembers': [],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstitutionsCapacityPanel(
                state: cityState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // City Name & Service Ratios Header
      expect(find.text('NEW CARTHAGE'), findsOneWidget);
      expect(find.textContaining('Housing: 78% · Energy: 92% · Connect: 85% · Health: 64%'), findsOneWidget);

      // Explicit CITY BUDGET Card and Amount
      expect(find.text('CITY BUDGET'), findsNWidgets(2)); // Attribute label + dedicated card header
      expect(find.text('450000 C'), findsNWidgets(2));
      expect(
        find.textContaining('Municipal funds for civic buildings, public services, maintenance, and explicitly approved resident subsidies.'),
        findsOneWidget,
      );
    });

    testWidgets('CorporationOverviewPanel renders Corporate Budget, treasury, explanation, tax policy, and chartered jurisdiction', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const corpState = EarthState({
        'human': {'id': 'H-0044'},
        'membership': {
          'corporation_id': 'CORP-001',
          'city_id': 'CITY-0084',
        },
        'institutions': {
          'corporation': {
            'id': 'CORP-001',
            'name': 'Solaris Conglomerate',
            'members': 42,
            'treasury': 8500000.0,
            'capital_city_name': 'New Carthage',
            'rules': {
              'incomeTaxBps': 250,
              'salesTaxBps': 150,
              'corporateTaxBps': 300,
            },
          },
        },
        'roles': [],
        'technology': {'corporationSharedPatents': []},
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CorporationOverviewPanel(
                state: corpState,
                busy: false,
                action: (cb) async => cb(),
              ),
            ),
          ),
        ),
      );

      // Corporation Header
      expect(find.text('Solaris Conglomerate'), findsOneWidget);

      // Explicit CORPORATE BUDGET Card, Amount, and Explanation
      expect(find.text('CORPORATE BUDGET'), findsNWidgets(2)); // Attribute label + dedicated card header
      expect(find.text('8500000 C'), findsNWidgets(2));
      expect(
        find.textContaining('Separate corporate funds for research, patents, payroll, and corporate projects. This budget is not the city budget or your personal account.'),
        findsOneWidget,
      );
    });

    testWidgets('Dashboard renders live Finance, City, Corporation, and Buildings routes directly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const fullState = EarthState({
        'human': {'id': 'H-0044', 'credits': 50000, 'standing': 100},
        'membership': {
          'corporation_id': 'CORP-001',
          'city_id': 'CITY-0084',
        },
        'institutions': {
          'city': {
            'id': 'CITY-0084',
            'name': 'New Carthage',
            'treasury': 450000.0,
          },
          'corporation': {
            'id': 'CORP-001',
            'name': 'Solaris Conglomerate',
            'treasury': 8500000.0,
          },
        },
        'buildings': [],
        'investmentShares': [],
        'finance': {},
      });

      Widget buildDashboardRoute(String section) {
        return MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Dashboard(
                state: fullState,
                selectedSection: section,
                busy: false,
                events: const [],
                notifications: const [],
                ownershipEvents: const [],
                businessOwnership: const {},
                businessFinancials: const {},
                businessProfile: const {},
                membershipEvents: const [],
                authorityEvents: const [],
                unreadNotifications: 0,
                action: (cb) async => cb(),
              ),
            ),
          ),
        );
      }

      // 1. Test 'finance' route
      await tester.pumpWidget(buildDashboardRoute('finance'));
      expect(find.byType(PersonalFinancePanel), findsOneWidget);

      // 2. Test 'city' route
      await tester.pumpWidget(buildDashboardRoute('city'));
      expect(find.byType(InstitutionsCapacityPanel), findsOneWidget);

      // 3. Test 'corporation' route
      await tester.pumpWidget(buildDashboardRoute('corporation'));
      expect(find.byType(CorporationOverviewPanel), findsOneWidget);

      // 4. Test 'buildings' route
      await tester.pumpWidget(buildDashboardRoute('buildings'));
      expect(find.byType(BuildingsHubScreen), findsOneWidget);
    });
  });
}
