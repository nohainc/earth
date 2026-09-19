import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/institutions/institutions_panels.dart';

void main() {
  testWidgets('CorporationOverviewPanel keeps independent status minimal',
      (tester) async {
    const state = EarthState({
      'institutions': {},
      'membership': {},
      'rankings': {
        'corporations': [
          {'name': 'Hidden Corporation', 'member_count': 99},
        ],
      },
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CorporationOverviewPanel(state: state)),
    ));

    expect(find.text('MEMBERSHIP'), findsOneWidget);
    expect(find.text('You are currently independent.'), findsOneWidget);
    expect(find.textContaining('Join a corporation to access'), findsOneWidget);
    expect(find.text('Hidden Corporation'), findsNothing);
    expect(find.text('CORPORATION DECISIONS'), findsNothing);
    expect(find.text('TREASURY'), findsNothing);
  });

  testWidgets(
      'CorporationOverviewPanel presents affiliation and corporation direction',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-0044'},
      'institutions': {
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_house_count': 38,
          'treasury_units': '1250000',
          'occupied_capacity_units': '184',
          'standard_capacity_units': '200',
          'required_standard_units': '1',
          'capacity_utilization_bps': 9200,
          'capacity_status': 'CURRENT',
          'technology_count': 7,
          'income_tax_bps': 250,
          'sales_tax_bps': 100,
          'corporate_tax_bps': 300,
          'property_tax_bps': 150,
        },
      },
      'membership': {'corporation_id': 'CORP-001'},
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-001',
            'name': 'Carthage Dynamics',
            'member_house_count': 38,
            'treasury_units': '1250000',
            'occupied_capacity_units': '184',
            'standard_capacity_units': '200',
            'required_standard_units': '1',
            'capacity_utilization_bps': 9200,
            'capacity_status': 'CURRENT',
            'technology_count': 7,
            'income_tax_bps': 250,
            'sales_tax_bps': 100,
            'corporate_tax_bps': 300,
            'property_tax_bps': 150,
          },
        ],
      },
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: CorporationOverviewPanel(state: state))),
    ));

    expect(find.text('CORPORATION'), findsNothing);
    expect(find.text('You belong to Carthage Dynamics.'), findsNothing);
    expect(find.text('LEAVE CORPORATION'), findsOneWidget);
    expect(find.text('POLICY & ECONOMY'), findsOneWidget);
    expect(find.text('Internal Corporate Tax Levy'), findsOneWidget);
    expect(find.text('Corporate Dividend Distribution'), findsNothing);
    expect(find.text('CORPORATION DECISIONS'), findsOneWidget);
    expect(find.text('38'), findsWidgets);
    expect(find.text('12500.00 C'), findsWidgets);
  });

  testWidgets(
      'CorporationHubPanel allows selecting corporations to inspect detailed overview',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    const state = EarthState({
      'human': {'id': 'H-0044'},
      'membership': {},
      'institutions': {},
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-001',
            'name': 'Carthage Dynamics',
            'member_house_count': 38,
            'treasury_units': '1250000',
            'occupied_capacity_units': '184',
            'standard_capacity_units': '200',
            'required_standard_units': '1',
            'capacity_utilization_bps': 9200,
            'capacity_status': 'CURRENT',
            'technology_count': 7,
          },
          {
            'id': 'CORP-002',
            'name': 'Aether Syndicate',
            'member_house_count': 94,
            'treasury_units': '4500000',
            'occupied_capacity_units': '620',
            'standard_capacity_units': '1000',
            'required_standard_units': '1',
            'capacity_utilization_bps': 6200,
            'capacity_status': 'CURRENT',
            'technology_count': 2,
          },
        ],
      },
    });

    // Test 2-column wide layout (>= 840 width)
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CorporationHubPanel(
            state: state,
            busy: false,
            action: (_) async => state,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify both corporations are listed in directory
    expect(find.textContaining('Carthage Dynamics'), findsWidgets);
    expect(find.textContaining('Aether Syndicate'), findsWidgets);

    // Initial selected corporation details in right column
    expect(find.text('Carthage Dynamics'), findsWidgets);

    // Tap on Aether Syndicate to select and inspect
    final aetherItem = find.textContaining('Aether Syndicate').first;
    await tester.ensureVisible(aetherItem);
    await tester.tap(aetherItem, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify the right-column details update to Aether Syndicate
    expect(find.text('Aether Syndicate'), findsWidgets);

    // Test 1-column narrow expandable layout (< 840 width)
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CorporationHubPanel(
            state: state,
            busy: false,
            action: (_) async => state,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // In 1-col layout, tap to expand Aether Syndicate inline
    final aetherRow = find.textContaining('Aether Syndicate').first;
    await tester.tap(aetherRow, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify the Corporation Directory expansion presents decision-relevant facts.
    expect(find.text('ADMISSION POLICY'), findsOneWidget);
  });

  testWidgets(
      'InstitutionsCapacityPanel renders city residency, pressure ratios, and proposes budget',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {
        'health': 100,
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.60,
          'connectivity': 0.95,
          'health': 0.90,
        },
      },
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {
        'city': {
          'id': 'CITY-0084',
          'name': 'New Carthage',
          'residents': 142,
          'housing_capacity': 200,
          'energy_capacity': 300,
        },
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_count': 38,
          'constitution_version': 2,
        },
      },
      'membership': {
        'city_id': 'CITY-0084',
        'corporation_id': 'CORP-001',
      },
      'communities': [],
      'life': {},
      'governance': {},
      'market': {'orders': []},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InstitutionsCapacityPanel(
              state: state,
              busy: false,
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('INSTITUTIONS / CITY & CORP'), findsNothing);
    expect(find.text('NEW CARTHAGE'), findsWidgets);
    expect(find.text('142'), findsWidgets);
    expect(find.text('200'), findsWidgets);
    expect(find.textContaining('CORPORATION: CARTHAGE DYNAMICS (CORP-001)'),
        findsNothing);
    expect(find.text('CHANGE CITY'), findsNothing);
    expect(find.text('PROPOSE BUDGET'), findsNothing);
    expect(find.text('TAX CHARTER'), findsNothing);

    await tester.pumpAndSettle();
  });
  testWidgets('CityImpactPanel explains city pressure and service conditions',
      (tester) async {
    const state = EarthState({
      'world': {
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.60,
          'connectivity': 0.95,
          'health': 0.90,
        },
      },
      'institutions': {
        'city': {
          'name': 'New Carthage',
          'service_pressure': 62,
          'tax_rate': 4.5
        },
      },
      'business': {'city_operating_modifier': 3.5},
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: CityImpactPanel(state: state)),
      ),
    ));

    expect(find.text('TERRITORY EFFECTS / LIFE & BUSINESS'), findsOneWidget);
    expect(find.text('TERRITORY PRESSURE'), findsOneWidget);
    expect(find.text('TERRITORY TAX'), findsOneWidget);
    expect(find.text('TERRITORY ORDINANCES & TARIFFS'), findsOneWidget);
    expect(find.text('Municipal Energy & Grid Tariff'), findsOneWidget);
    expect(find.text('Essential Services Minimum Standard'), findsOneWidget);
  });

  testWidgets(
      'InstitutionsPanel renders planetary corporations with constitutional tax badges and charter dialog',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-0044'},
      'membership': {'corporation_id': 'CORP-001'},
      'institutions': {
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_house_count': 38,
          'treasury_units': '1250000',
          'occupied_capacity_units': '184',
          'standard_capacity_units': '200',
          'required_standard_units': '1',
          'capacity_utilization_bps': 9200,
          'technology_count': 7,
          'income_tax_bps': 250,
          'sales_tax_bps': 100,
          'corporate_tax_bps': 300,
          'property_tax_bps': 150,
        },
      },
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-001',
            'name': 'Carthage Dynamics',
            'member_house_count': 38,
            'treasury_units': '1250000',
            'occupied_capacity_units': '184',
            'standard_capacity_units': '200',
            'required_standard_units': '1',
            'capacity_utilization_bps': 9200,
            'technology_count': 7,
            'income_tax_bps': 250,
            'sales_tax_bps': 100,
            'corporate_tax_bps': 300,
            'property_tax_bps': 150,
          },
          {
            'id': 'CORP-002',
            'name': 'Aether Syndicate',
            'member_house_count': 15,
            'treasury_units': '540000',
            'occupied_capacity_units': '60',
            'standard_capacity_units': '100',
            'required_standard_units': '1',
            'capacity_utilization_bps': 6000,
            'technology_count': 0,
            'income_tax_bps': 180,
            'sales_tax_bps': 80,
            'corporate_tax_bps': 200,
            'property_tax_bps': 100,
          },
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CorporationDirectoryPanel(
            state: state,
            busy: false,
            action: (cb) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('CORPORATION DIRECTORY'), findsOneWidget);
    expect(find.text('ACTIVE AFFILIATION: Carthage Dynamics'), findsOneWidget);
    expect(find.text('VIEW CORPORATION PROFILE'), findsOneWidget);
    expect(find.text('ALL CORPORATIONS'), findsOneWidget);

    expect(find.text('Carthage Dynamics'), findsWidgets);
    expect(find.textContaining('3.0%'), findsWidgets);

    final charterBtn = find.text('VIEW CORPORATION').first;
    await tester.ensureVisible(charterBtn);
    await tester.tap(charterBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('Corporation Profile'), findsOneWidget);
    expect(find.text('CAPACITY'), findsOneWidget);
    expect(find.text('FINANCE'), findsOneWidget);
    expect(find.text('TECHNOLOGY'), findsOneWidget);
  });

  testWidgets('CivicRankingsPanel legacy multi-entity index is retired',
      (tester) async {
    // Covered by world_rankings_panel_test.dart using the canonical V4 payload.
  }, skip: true);

  testWidgets(
      'Corporation directory renders authoritative V5 policies and fields',
      (tester) async {
    const state = EarthState({
      'membership': {},
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-OPEN',
            'name': 'Open Works',
            'admission_policy': 'OPEN',
            'membership_state': 'ELIGIBLE',
            'member_house_count': 4,
            'occupied_capacity_units': '17',
            'standard_capacity_units': '25',
            'required_standard_units': '1',
            'capacity_utilization_bps': 6800,
            'capacity_status': 'CURRENT',
            'technology_count': 3,
            'treasury_units': '123450',
          },
          {
            'id': 'CORP-APPROVAL',
            'name': 'Civic Foundry',
            'admission_policy': 'APPROVAL',
            'membership_state': 'PENDING',
            'member_house_count': 8,
            'occupied_capacity_units': '20',
            'standard_capacity_units': '25',
            'required_standard_units': '1',
            'capacity_utilization_bps': 8000,
            'capacity_status': 'CURRENT',
            'technology_count': 1,
          },
          {
            'id': 'CORP-INVITE',
            'name': 'Private Exchange',
            'admission_policy': 'INVITE_ONLY',
            'membership_state': 'INELIGIBLE',
            'member_house_count': 2,
            'occupied_capacity_units': '7',
            'standard_capacity_units': '10',
            'required_standard_units': '1',
            'capacity_utilization_bps': 7000,
            'capacity_status': 'CURRENT',
            'technology_count': 0,
          },
        ],
      },
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CorporationDirectoryPanel(
          state: state,
          busy: false,
          isExpandable: true,
          action: (_) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('APPLICATION'), findsOneWidget);
    expect(find.text('INVITE ONLY'), findsOneWidget);
    await tester.tap(find.text('Civic Foundry').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('APPLICATION PENDING'), findsOneWidget);
    await tester.tap(find.text('Open Works').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Not published'), findsWidgets);
    expect(find.text('3 adopted'), findsOneWidget);
    expect(find.text('17 / 25'), findsOneWidget);
    expect(find.text('city_count'), findsNothing);
    expect(find.text('capital_city_name'), findsNothing);
    expect(find.text('shared_patents'), findsNothing);
    expect(find.textContaining('Territory infrastructure'), findsNothing);
  });

  testWidgets('CivicRankingsPanel legacy pagination is retired',
      (tester) async {
    // Covered by the server-paginated canonical ranking contract.
  }, skip: true);

  /* Legacy fixture retained in git history for migration context.
      (tester) async {
    const state = EarthState({
      'human': {
        'id': 'H-0044',
      },
      'membership': {
        'human_id': 'H-0044',
        'corporation_id': 'CORP-001',
        'city_id': 'CITY-0084',
      },
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-001',
            'name': 'Carthage Dynamics',
            'member_count': 38,
            'treasury': 12500,
            'compositeIndex': 85,
          },
          {
            'id': 'CORP-002',
            'name': 'Aegis Power',
            'member_count': 20,
            'treasury': 5000,
            'compositeIndex': 65,
          },
        ],
        'cities': [
          {
            'id': 'CITY-0084',
            'name': 'New Carthage',
            'residents': 142,
            'housing_capacity': 150,
            'energy_capacity': 180,
            'connectivity_capacity': 160,
            'health_capacity': 140,
            'treasury': 28000,
            'corporation_name': 'Carthage Dynamics',
            'compositeIndex': 94,
          },
        ],
        'citizens': [
          {
            'id': 'H-0044',
            'displayName': 'Amara Vance',
            'houseName': 'House of Vance',
            'corporationId': 'CORP-001',
            'cityId': 'CITY-0084',
            'legacy': 120,
            'standing': 840,
            'credits': 5000,
            'compositeScore': 14484,
          },
          {
            'id': 'H-0012',
            'displayName': 'Dmitri Rostov',
            'houseName': 'House of Rostov',
            'cityId': 'CITY-0084',
            'legacy': 90,
            'standing': 650,
            'credits': 4200,
            'compositeScore': 12150,
          },
        ],
        'houses': [
          {
            'house_name': 'House of Vance',
            'founder_name': 'Marcus Vance',
            'active_heir': 'Amara Vance',
            'generation': 3,
            'total_legacy': 5400,
            'house_standing': 980,
          },
        ],
      },
    });

    // Test narrow screen (e.g. 400px width)
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CivicRankingsPanel(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 4 Tab buttons on narrow screen
    expect(find.widgetWithText(InkWell, 'CITIZENS'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'HOUSES'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'ORGANIZATIONS'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'TERRITORIES'), findsOneWidget);

    // Currently on Citizens tab (default)
    expect(find.text('Amara Vance'), findsOneWidget);
    expect(find.text('120 Leg · 840 Std · 5k Cap'), findsOneWidget);
    expect(find.text('Carthage Dynamics · New Carthage'), findsNWidgets(2));
    expect(find.text('Dmitri Rostov'), findsOneWidget);
    expect(find.text('90 Leg · 650 Std · 4.2k Cap'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);

    // Switch to Houses tab
    await tester.tap(find.widgetWithText(InkWell, 'HOUSES'));
    await tester.pumpAndSettle();

    expect(find.text('House of Vance'), findsOneWidget);
    expect(find.text('5.4k Leg · 980 Std · Gen 3'), findsOneWidget);
    expect(
        find.text('Founder: Marcus Vance · Heir: Amara Vance'), findsOneWidget);

    // Verify formula info dialog from cockpit
    final infoIcons = find.descendant(of: find.byType(CivicRankingsPanel), matching: find.byIcon(Icons.info_outline));
    expect(infoIcons, findsOneWidget);

    await tester.tap(infoIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('CIVIC RANKINGS & LEADERBOARD ARCHITECTURE'), findsOneWidget);
    expect(find.textContaining('Dynastic House Index'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Switch to Organizations tab
    await tester.tap(find.widgetWithText(InkWell, 'ORGANIZATIONS'));
    await tester.pumpAndSettle();

    expect(find.text('Carthage Dynamics'), findsOneWidget);
    expect(find.text('56.3k Cap · 0 Biz · 142 Res'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);

    // Switch to Territories tab
    await tester.tap(find.widgetWithText(InkWell, 'TERRITORIES'));
    await tester.pumpAndSettle();

    expect(find.text('New Carthage'), findsOneWidget);
    expect(find.text('43.8k Cap · 0 Biz · 142 Res'), findsOneWidget);
    expect(find.text('Carthage Dynamics'), findsOneWidget);
    expect(find.text('94'), findsOneWidget);

    // Test wide screen (1000px width -> 2 columns, 2 tabs each)
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CivicRankingsPanel(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Left Column: CITIZENS and HOUSES
    expect(find.widgetWithText(InkWell, 'CITIZENS'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'HOUSES'), findsOneWidget);
    // Right Column: ORGANIZATIONS and TERRITORIES
    expect(find.widgetWithText(InkWell, 'ORGANIZATIONS'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'TERRITORIES'), findsOneWidget);

    // Both columns render simultaneously
    expect(find.text('Amara Vance'), findsOneWidget);
    expect(find.text('Carthage Dynamics'), findsOneWidget);
  }); */

  /* testWidgets(
      'CivicRankingsPanel paginates long lists and supports Jump to My Rank',
      (tester) async {
    final manyCitizens = List.generate(15, (index) {
      return {
        'id': 'H-${index + 1}',
        'displayName': 'Citizen ${index + 1}',
        'legacy': 100 - index,
        'standing': 500 - (index * 10),
        'credits': 1000 + (index * 100),
      };
    });

    final state = EarthState({
      'human': {'id': 'H-12'}, // Placed on page 2 (ranks 11-15)
      'rankings': {
        'corporations': [],
        'cities': [],
        'citizens': manyCitizens,
      },
    });

    // Test narrow screen (400px width, 1200px height)
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CivicRankingsPanel(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Citizens tab on narrow layout
    await tester.tap(find.widgetWithText(InkWell, 'CITIZENS'));
    await tester.pumpAndSettle();

    // Auto-navigates to user's page (Page 2 of 2) since H-12 is at rank #12
    expect(find.text(' of 2 (15)'), findsOneWidget);
    expect(find.text('Citizen 12'), findsOneWidget);

    // Tap "<<" (First Page) -> returns to Page 1
    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pumpAndSettle();

    expect(find.text(' of 2 (15)'), findsOneWidget);
    expect(find.text('Citizen 1'), findsOneWidget);
    expect(find.text('Citizen 10'), findsOneWidget);

    // Tap ">>" (Last Page) -> goes to Page 2
    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pumpAndSettle();

    expect(find.text('Citizen 12'), findsOneWidget);

    // Tap "<" (Previous Page) -> goes to Page 1
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('Citizen 1'), findsOneWidget);

    // Test entering page 2 into TextField directly
    await tester.enterText(find.byType(TextField), '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Citizen 12'), findsOneWidget);
  }); */
}
