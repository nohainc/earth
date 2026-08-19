import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/navigation_deep_link.dart';
import 'package:earth_client/features/command_center/dashboard.dart';
import 'package:earth_client/features/dynasty/dynasty_tree_dialog.dart';
import 'package:earth_client/features/contracts/supply_contracts_dialog.dart';
import 'package:earth_client/features/market/derivatives_dialog.dart';
import 'package:earth_client/features/finance/net_worth_analytics_dialog.dart';

void main() {
  final sampleState = EarthState({
    'status': {'phase': 'Operational'},
    'player': {
      'id': 'p1',
      'credits': 15000,
      'cash': 15000,
      'energy': 100,
      'name': 'Commander Vance',
    },
    'time': {'day': 42},
    'market': {'prices': {'energy': 10.5}},
    'business': {'balance': 5000, 'energy': 100},
  });

  group('NavigationDeepLink', () {
    test('stub defaults return null and allow section updates without throw', () {
      expect(NavigationDeepLink.getInitialSection(), isNull);
      NavigationDeepLink.updateSection('command');
      NavigationDeepLink.listen((_) {});
    });
  });

  group('Complex Systems Page Mode & Dashboard Full Pages', () {
    testWidgets('DynastyTreeDialog renders in page mode and triggers return to command', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DynastyTreeDialog(
                api: const EarthApi(),
                state: sampleState,
                isPageMode: true,
                onNavigate: (sec) => navigatedTo = sec,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('RETURN TO COMMAND'), findsOneWidget);
      await tester.tap(find.text('RETURN TO COMMAND'));
      await tester.pump();
      expect(navigatedTo, equals('command'));
    });

    testWidgets('SupplyContractsDialog renders in page mode and triggers return to command', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SupplyContractsDialog(
                api: const EarthApi(),
                state: sampleState,
                isPageMode: true,
                onNavigate: (sec) => navigatedTo = sec,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AUTOMATED SUPPLY CONTRACTS & ESCROW VAULT'), findsOneWidget);
      expect(find.text('RETURN TO COMMAND'), findsOneWidget);
      await tester.tap(find.text('RETURN TO COMMAND'));
      await tester.pump();
      expect(navigatedTo, equals('command'));
    });

    testWidgets('DerivativesDialog renders in page mode and triggers return to command', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DerivativesDialog(
                api: const EarthApi(),
                state: sampleState,
                isPageMode: true,
                onNavigate: (sec) => navigatedTo = sec,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('FINANCIAL DERIVATIVES & FUTURES TERMINAL'), findsOneWidget);
      expect(find.text('RETURN TO COMMAND'), findsOneWidget);
      await tester.tap(find.text('RETURN TO COMMAND'));
      await tester.pump();
      expect(navigatedTo, equals('command'));
    });

    testWidgets('NetWorthAnalyticsDialog renders in page mode and triggers return to command', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NetWorthAnalyticsDialog(
                api: const EarthApi(),
                isPageMode: true,
                onNavigate: (sec) => navigatedTo = sec,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('PERSONAL & MULTI-GENERATIONAL NET-WORTH ANALYTICS'), findsOneWidget);
      expect(find.text('RETURN TO COMMAND'), findsOneWidget);
      await tester.tap(find.text('RETURN TO COMMAND'));
      await tester.pump();
      expect(navigatedTo, equals('command'));
    });

    testWidgets('Dashboard renders derivatives section as full page', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Dashboard(
                state: sampleState,
                busy: false,
                selectedSection: 'derivatives',
                sectionKeys: const {},
                events: const [],
                notifications: const [],
                ownershipEvents: const [],
                businessOwnership: const {},
                businessFinancials: const {},
                businessProfile: const {},
                personalFinanceData: const {},
                pantheon: const {},
                contracts: const [],
                authorityEvents: const [],
                membershipEvents: const [],
                marketHistory: const {},
                productionCatalog: const [],
                unreadNotifications: 0,
                action: (_) async {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DerivativesDialog), findsOneWidget);
    });
  });
}
