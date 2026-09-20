import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets(
      'Lifecycle panels render V5 profile-adjacent world panels, liquidity, memorial, history and rankings',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {
        'id': 'H-0044',
        'display_name': 'Amara Kline',
        'credits': 18420,
      },
      'humanProfile': {
        'id': 'H-0044',
        'displayName': 'Amara Kline',
        'houseId': 'HOUSE-KLINE',
        'houseName': 'Kline',
        'birthGameDay': 10,
        'ageYears': 48,
        'status': 'ACTIVE',
        'standing': 742,
        'finalLegacy': 742,
        'corporationId': 'CORP-APEX',
        'corporationName': 'Apex Dynamics',
      },
      'humanDailyNeeds': {
        'gameDay': 184,
        'foodRequiredUnits': '1',
        'foodConsumedUnits': '1',
        'foodShortfallUnits': '0',
        'energyRequiredUnits': '1',
        'energyConsumedUnits': '1',
        'energyShortfallUnits': '0',
        'status': 'MET',
      },
      'world': {
        'health': 100,
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.90,
          'connectivity': 0.95,
          'health': 0.92,
        },
        'serviceStatus': {
          'housing': 'NORMAL',
          'energy': 'BASIC',
          'health': 'NORMAL',
        },
      },
      'finance': {
        'liquidity': {
          'moneySupply': 1000000.0,
          'target': 1000000.0,
          'status': 'inside-corridor',
          'cpi': 101.5,
          'gini': 0.32,
          'velocity': 2.1,
        },
      },
      'audit': {
        'm0_conservation': true,
        'ledger_balanced': true,
        'verified_epoch': 1420,
      },
      'resources': {'food': 500, 'energy': 1200},
      'business': {},
      'technology': {'research': {}},
      'institutions': {
        'solvency': {
          'reserves': 250000.0,
          'liabilities': 100000.0,
          'status': 'healthy',
        },
      },
      'life': {
        'birth_day': 10,
        'aging_stage': 'SENIOR',
      },
      'governance': {},
      'market': {'orders': []},
      'ledgerEntries': [
        {
          'id': 'TX-901',
          'type': 'DIVIDEND_PAYOUT',
          'amount': 450.0,
          'source': 'Apex Dynamics',
          'destination': 'H-0044',
          'timestamp': 'Day 184, 08:30',
        },
      ],
      'rankings': {
        'cities': [
          {
            'name': 'Neo Olympia',
            'score': 98.4,
            'population': 42000,
            'gdp': 1500000
          },
        ],
        'corporations': [
          {'name': 'Apex Dynamics Corp', 'valuation': 850000, 'standing': 94},
        ],
      },
      'history': {
        'events': [
          {
            'id': 'EV-01',
            'title': 'Constitutional Amendment Enacted',
            'description': '3-day judicial review cooling-off window ratified.',
            'timestamp': 'Day 180',
          },
        ],
      },
      'financeStatus': [
        {
          'cityId': 'city-01',
          'name': 'Neo Olympia',
          'budget': 500000,
          'surplus': 45000,
          'solvencyRatio': 1.45,
        },
      ],
    });

    final notifications = [
      {
        'id': 'notif-1',
        'title': 'Dividend Received',
        'body': 'Apex Dynamics deposited 450.00 Credits into your account.',
        'timestamp': '10 mins ago',
        'read': false,
      },
    ];

    final ownershipEvents = [
      {
        'id': 'own-1',
        'asset': 'Aero Turbine Facility',
        'previousOwner': 'State Trust',
        'newOwner': 'H-0044',
        'timestamp': 'Day 150',
      },
    ];

    final membershipEvents = [
      {
        'id': 'mem-1',
        'organization': 'Neo Olympia Citizens Guild',
        'role': 'SENIOR_MEMBER',
        'timestamp': 'Day 100',
      },
    ];

    final feedEvents = [
      {
        'id': 'feed-1',
        'headline': 'Macro Corridor Stabilization Confirmed by Stability Board',
        'category': 'MONETARY',
        'timestamp': 'Day 184, 09:00',
      },
    ];

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                LegacyPersonalFinancePanel(
                    state: state, busy: false, action: (cb) async {}),
                InstitutionSolvencyPanel(
                    state: state, busy: false, action: (cb) async {}),
                const WorldIntegrityPanel(state: state),
                const MacroLiquidityPanel(state: state),
                const HumanServicesPanel(state: state),
                const LedgerPanel(state: state),
                WorldFeedPanel(events: feedEvents),
                NotificationsPanel(
                    state: state,
                    notifications: notifications,
                    unreadNotifications: 1,
                    busy: false,
                    action: (cb) async {}),
                OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
                CivicMembershipHistoryPanel(membershipEvents: membershipEvents),
                const WorldRankingsPanel(state: state),
                const HistoryArchivePanel(state: state),
              ],
            ),
          ),
        ),
      ),
    );

    // LegacyPersonalFinancePanel
    expect(find.text('PERSONAL FINANCE / PROTECTED MINIMUM'), findsOneWidget);

    // InstitutionSolvencyPanel
    expect(find.text('INSTITUTION SOLVENCY / RECOVERY'), findsOneWidget);

    // WorldIntegrityPanel
    expect(find.text('WORLD INTEGRITY / AUDIT'), findsOneWidget);
    expect(find.textContaining('m0_conservation: OK'), findsOneWidget);

    // MacroLiquidityPanel
    expect(
        find.text('UC MONETARY STABILITY BOARD / MACRO BASE'), findsOneWidget);
    expect(find.text('100% Reserve Conserved'), findsOneWidget);

    // HumanServicesPanel
    expect(find.text('HUMAN SERVICES / CURRENT ACCESS'), findsOneWidget);

    // Historical archive ownership belongs to the canonical Memorial page.
    expect(find.text('PANTHEON / HOUSE ARCHIVE & LEGACY'), findsNothing);
  });
}
