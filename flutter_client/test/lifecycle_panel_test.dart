import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets(
      'SuccessionPanel renders active human life, political status, and registered successor',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {
        'id': 'H-0044',
        'display_name': 'Amara Kline',
        'credits': 18420,
        'standing': 742,
        'legacy': 31,
        'age_years': 31,
        'life_status': 'active',
      },
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {
        'status': 'active',
        'ageYears': 31,
        'estatePeriodDays': 30,
        'successor': {
          'successor_name': 'Mira Kline',
          'successor_human_id': 'H-0088',
          'registered_game_day': 180,
          'estate_period_days': 30,
        },
      },
      'governance': {},
    });

    bool planTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SuccessionPanel(
              state: state,
              busy: false,
              action: (cb) async {
                planTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('LIFE & LEGACY / SUCCESSION PLAN'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.textContaining('Life stage and succession readiness'),
        findsOneWidget);
    expect(
        find.textContaining('SUCCESSOR: Mira Kline (H-0088)'), findsOneWidget);
    expect(
        find.textContaining('Registered on Day 180 · Estate buffer: 30 days'),
        findsOneWidget);
    expect(find.textContaining('Estate state: PENDING'), findsOneWidget);
    expect(find.text('UPDATE WILL & SUCCESSOR'), findsOneWidget);

    // Open plan dialog
    await tester.tap(find.text('UPDATE WILL & SUCCESSOR'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plan succession'), findsOneWidget);
    expect(find.text('Save plan'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Mira Kline');
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();

    expect(planTriggered, isTrue);
  });

  testWidgets(
      'SuccessionPanel renders estate period and enables inheritance settlement',
      (tester) async {
    const estateState = EarthState({
      'clock': {'day': 200, 'minute': 100},
      'human': {
        'id': 'H-0044',
        'display_name': 'Amara Kline',
        'credits': 18420,
        'standing': 742,
        'legacy': 31,
        'age_years': 95,
        'life_status': 'estate',
      },
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {
        'status': 'estate',
        'ageYears': 95,
        'estatePeriodDays': 30,
        'successor': {
          'successor_name': 'Mira Kline',
          'successor_human_id': 'H-0088',
          'registered_game_day': 180,
          'estate_period_days': 30,
        },
      },
      'governance': {},
    });

    bool settleTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SuccessionPanel(
              state: estateState,
              busy: false,
              action: (cb) async {
                settleTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('ESTATE'), findsOneWidget);
    expect(find.textContaining('Estate state: ACTIVE ESTATE PERIOD'),
        findsOneWidget);
    expect(find.text('SETTLE ESTATE INHERITANCE'), findsOneWidget);

    // Open settle inheritance dialog
    await tester.tap(find.text('SETTLE ESTATE INHERITANCE'));
    await tester.pumpAndSettle();

    expect(find.text('Settle Estate Inheritance'), findsOneWidget);
    expect(find.text('Execute inheritance'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Mira Kline');
    await tester.enterText(find.byType(TextField).last, 'H-0088');
    await tester.tap(find.text('Execute inheritance'));
    await tester.pumpAndSettle();

    expect(settleTriggered, isTrue);
  });
}
