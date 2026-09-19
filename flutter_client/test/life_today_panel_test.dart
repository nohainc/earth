import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets(
      'LifeTodayPanel presents personal status without invented metrics',
      (tester) async {
    const state = EarthState({
      'humanProfile': {
        'id': 'H-1',
        'displayName': 'Ada Noha',
        'houseId': 'HOUSE-1',
        'houseName': 'Noha',
        'birthGameDay': 1200,
        'ageYears': 34,
        'status': 'ACTIVE',
        'standing': 120,
        'finalLegacy': 120,
        'corporationId': 'CORP-1',
        'corporationName': 'Nova',
      },
      'humanDailyNeeds': {
        'gameDay': 184,
        'foodRequiredUnits': '1',
        'foodConsumedUnits': '1',
        'foodShortfallUnits': '0',
        'energyRequiredUnits': '1',
        'energyConsumedUnits': '0',
        'energyShortfallUnits': '1',
        'status': 'PARTIAL',
      },
      'humanAuthoritySummary': [
        {
          'institutionType': 'CORPORATION',
          'institutionId': 'CORP-1',
          'institutionName': 'Nova',
          'roleCode': 'CORPORATION_TREASURER',
          'roleName': 'Corporation Treasurer',
          'effectiveFromDay': 172,
        },
      ],
      'recentLifeEvents': [
        {
          'game_day': 180,
          'title': 'Appointed Treasurer',
          'event_type': 'ROLE_APPOINTED',
        },
      ],
      'business': {'name': 'Northstar Robotics'},
      'residency': {},
      'membership': {'name': 'Civic Assembly'},
      'life': {},
    });

    String? selectedRoute;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        extensions: const [
          EarthThemeExtension(
            primary: Color(0xFF00FFAA),
            secondary: Color(0xFFAA00FF),
            canvas: Color(0xFF101010),
            surface: Color(0xFF202020),
            panel: Color(0xFF303030),
            card: Color(0xFF404040),
            accent: Color(0xFF00FFAA),
            gold: Color(0xFFFFCC00),
          ),
        ],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LifeTodayPanel(
            state: state,
            onNavigate: (route) => selectedRoute = route,
          ),
        ),
      ),
    ));

    expect(find.text('34'), findsOneWidget);
    expect(find.text('CIVIC STANDING'), findsOneWidget);
    expect(find.text('HOUSE'), findsOneWidget);
    expect(find.text('BIOMETRIC HEALTH'), findsNothing);
    expect(find.text('LIFE ENERGY'), findsNothing);
    expect(find.text('TERRITORY'), findsNothing);
    expect(find.text('DAILY NEEDS'), findsAtLeastNWidgets(1));
    expect(find.text('MET'), findsAtLeastNWidgets(1));
    expect(find.text('SHORTFALL'), findsAtLeastNWidgets(1));
    expect(find.text('DAY 184'), findsOneWidget);
    expect(find.text('ROLES & OFFICES'), findsOneWidget);
    expect(find.text('Corporation Treasurer'), findsOneWidget);
    expect(find.text('RECENT LIFE EVENTS'), findsOneWidget);
    expect(find.text('Appointed Treasurer'), findsOneWidget);
    expect(find.text('VIEW HOUSE'), findsOneWidget);
    expect(find.text('VIEW CORPORATION'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.cake_outlined)).color,
      const Color(0xFF00FFAA),
    );

    await tester.tap(find.text('VIEW HOUSE'));
    expect(selectedRoute, 'house');
    await tester.tap(find.text('VIEW CORPORATION'));
    expect(selectedRoute, 'my-corporation');
  });

  testWidgets('missing profile authority is not replaced with invented values',
      (tester) async {
    const state = EarthState({
      'humanProfile': {
        'id': 'H-2',
        'displayName': 'Unaffiliated Citizen',
        'houseId': 'HOUSE-2',
        'houseName': 'House Two',
        // Standing, status, and birthGameDay intentionally omitted.
      },
      'human': {
        'health': 82,
        'energy': 64,
        'life_status': 'ACTIVE',
      },
      'life': {'status': 'ACTIVE', 'vitality': 82},
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: LifeTodayPanel(state: state)),
      ),
    ));

    expect(find.text('CIVIC STANDING'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsAtLeastNWidgets(1));
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('ACTIVE HUMAN'), findsNothing);
    expect(find.text('BIOMETRIC HEALTH'), findsNothing);
    expect(find.text('LIFE ENERGY'), findsNothing);
    expect(find.text('DAILY NEEDS'), findsAtLeastNWidgets(1));
    expect(find.text('Birth Day'), findsNothing);
    expect(find.text('PRIMARY HEIR'), findsNothing);
    expect(find.text('HOUSE VAULT'), findsNothing);
    expect(find.text('COMMONS TRUST'), findsNothing);
  });
}
