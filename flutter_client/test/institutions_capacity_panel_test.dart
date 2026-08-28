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
          'member_count': 38,
          'treasury': 12500,
        },
      },
      'membership': {'corporation_id': 'CORP-001', 'city_id': 'CITY-0084'},
      'rankings': {
        'corporations': [
          {'id': 'CORP-001', 'name': 'Carthage Dynamics', 'member_count': 38},
        ],
      },
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CorporationOverviewPanel(state: state))),
    ));

    expect(find.text('CORPORATION'), findsNothing);
    expect(find.text('You belong to Carthage Dynamics.'), findsNothing);
    expect(find.text('LEAVE CORPORATION'), findsOneWidget);
    expect(find.text('CORPORATE CHARTER & BYLAWS'), findsOneWidget);
    expect(find.text('Internal Corporate Tax Levy'), findsOneWidget);
    expect(find.text('Shareholder Supermajority Protection'), findsOneWidget);
    expect(find.text('CORPORATION DECISIONS'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('12500 C'), findsOneWidget);
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
            'member_count': 38,
            'treasury': 12500,
            'capital_city_name': 'New Carthage',
          },
          {
            'id': 'CORP-002',
            'name': 'Aether Syndicate',
            'member_count': 94,
            'treasury': 45000,
            'capital_city_name': 'Sky Spire',
          },
        ],
        'cities': [
          {'id': 'CITY-1', 'name': 'New Carthage', 'corporation_id': 'CORP-001', 'residents': 150},
          {'id': 'CITY-2', 'name': 'Sky Spire', 'corporation_id': 'CORP-002', 'residents': 300},
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

    // Verify universal charter principles and inline expansion reveals details
    expect(find.text('UNIVERSAL CHARTER PRINCIPLES'), findsOneWidget);
    expect(find.text('Corporate Tax Protection'), findsOneWidget);
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

    bool budgetProposed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InstitutionsCapacityPanel(
              state: state,
              busy: false,
              action: (cb) async {
                budgetProposed = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('INSTITUTIONS / CITY & CORP'), findsNothing);
    expect(find.text('NEW CARTHAGE'), findsOneWidget);
    expect(find.text('142'), findsWidgets);
    expect(find.text('200'), findsWidgets);
    expect(find.text('300'), findsWidgets);
    expect(find.textContaining('CORPORATION: CARTHAGE DYNAMICS (CORP-001)'),
        findsNothing);
    expect(find.text('CHANGE CITY'), findsOneWidget);
    expect(find.text('PROPOSE BUDGET'), findsOneWidget);
    expect(find.text('TAX CHARTER'), findsOneWidget);

    await tester.pumpAndSettle();

    await tester.tap(find.text('PROPOSE BUDGET'));
    await tester.pumpAndSettle();

    expect(budgetProposed, isTrue);
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

    expect(find.text('CITY EFFECTS / LIFE & BUSINESS'), findsOneWidget);
    expect(find.text('CITY PRESSURE'), findsOneWidget);
    expect(find.text('BUSINESS EFFECT'), findsOneWidget);
    expect(find.text('CITY TAX'), findsOneWidget);
    expect(find.text('MUNICIPAL ORDINANCES & TARIFFS'), findsOneWidget);
    expect(find.text('Municipal Energy & Grid Tariff'), findsOneWidget);
    expect(find.text('Essential Services Minimum Standard'), findsOneWidget);
  });

  testWidgets('InstitutionsPanel renders planetary corporations with constitutional tax badges and charter dialog',
      (tester) async {
    const state = EarthState({
      'human': {'id': 'H-0044'},
      'membership': {'corporation_id': 'CORP-001', 'city_id': 'CITY-0084'},
      'institutions': {
        'corporation': {
          'id': 'CORP-001',
          'name': 'Carthage Dynamics',
          'member_count': 38,
          'treasury': 12500,
          'capital_city_name': 'New Carthage',
          'rules': {
            'incomeTaxBps': 250,
            'salesTaxBps': 100,
            'corporateTaxBps': 300,
          },
        },
      },
      'rankings': {
        'corporations': [
          {
            'id': 'CORP-001',
            'name': 'Carthage Dynamics',
            'member_count': 38,
            'treasury': 12500,
            'capital_city_name': 'New Carthage',
            'city_count': 3,
            'rules': {
              'incomeTaxBps': 250,
              'salesTaxBps': 100,
              'corporateTaxBps': 300,
            },
          },
          {
            'id': 'CORP-002',
            'name': 'Aether Syndicate',
            'member_count': 15,
            'treasury': 5400,
            'capital_city_name': 'Olympus Peak',
            'city_count': 1,
            'rules': {
              'incomeTaxBps': 180,
              'salesTaxBps': 80,
              'corporateTaxBps': 200,
            },
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

    expect(find.text('PLANETARY CORPORATIONS & CHARTERS'), findsOneWidget);
    expect(find.text('ACTIVE AFFILIATION: Carthage Dynamics'), findsOneWidget);
    expect(find.text('VIEW CONSTITUTION & TAX CHARTER'), findsOneWidget);
    expect(find.text('ALL PLANETARY CORPORATIONS'), findsOneWidget);

    expect(find.text('Carthage Dynamics'), findsOneWidget);
    expect(find.textContaining('2.5%'), findsWidgets);
    expect(find.textContaining('1.0%'), findsWidgets);
    expect(find.textContaining('1.8%'), findsWidgets);

    final charterBtn = find.text('CHARTER & PERKS').first;
    await tester.ensureVisible(charterBtn);
    await tester.tap(charterBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('Charter & Constitution'), findsOneWidget);
    expect(find.text('CONSTITUTIONAL TAX SCHEDULE'), findsOneWidget);
    expect(find.text('Corporate Tax Protection'), findsWidgets);
  });

  testWidgets('CivicRankingsPanel renders corporations and cities with tabs, formula dialogs and index badges',
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
    expect(find.text('CITIZENS (2)'), findsOneWidget);
    expect(find.text('HOUSES (1)'), findsOneWidget);
    expect(find.text('CORPS (2)'), findsOneWidget);
    expect(find.text('CITIES (1)'), findsOneWidget);

    // Currently on Citizens tab (default)
    expect(find.text('Amara Vance'), findsOneWidget);
    expect(find.text('120 Leg · 840 Std · 5k Cap'), findsOneWidget);
    expect(find.text('Carthage Dynamics · New Carthage'), findsNWidgets(2));
    expect(find.text('Dmitri Rostov'), findsOneWidget);
    expect(find.text('90 Leg · 650 Std · 4.2k Cap'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);

    // Switch to Houses tab
    await tester.tap(find.text('HOUSES (1)'));
    await tester.pumpAndSettle();

    expect(find.text('House of Vance'), findsOneWidget);
    expect(find.text('5.4k Leg · 980 Std · Gen 3'), findsOneWidget);
    expect(find.text('Founder: Marcus Vance · Heir: Amara Vance'), findsOneWidget);

    // Verify formula info dialog for Houses
    final infoIcons = find.byIcon(Icons.info_outline);
    expect(infoIcons, findsOneWidget);

    await tester.tap(infoIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('HOUSES RANKING FORMULA'), findsOneWidget);
    expect(find.textContaining('1 : 5 : 25 weighting ratio'), findsOneWidget);
    expect(find.textContaining('House Legacy (25x relative weight'), findsOneWidget);
    expect(find.text('GOT IT'), findsOneWidget);

    await tester.tap(find.text('GOT IT'));
    await tester.pumpAndSettle();

    // Switch to Corps tab
    await tester.tap(find.text('CORPS (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Carthage Dynamics'), findsOneWidget);
    expect(find.text('56.3k Cap · 0 Biz · 142 Res'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);

    // Switch to Cities tab
    await tester.tap(find.text('CITIES (1)'));
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
    expect(find.text('CITIZENS (2)'), findsOneWidget);
    expect(find.text('HOUSES (1)'), findsOneWidget);
    // Right Column: CORPS and CITIES
    expect(find.text('CORPS (2)'), findsOneWidget);
    expect(find.text('CITIES (1)'), findsOneWidget);

    // Both columns render simultaneously
    expect(find.text('Amara Vance'), findsOneWidget);
    expect(find.text('Carthage Dynamics'), findsOneWidget);
  });

  testWidgets('CivicRankingsPanel paginates long lists and supports Jump to My Rank', (tester) async {
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
    await tester.tap(find.text('CITIZENS (15)'));
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
  });
}
