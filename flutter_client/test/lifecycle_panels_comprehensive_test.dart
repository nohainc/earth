import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/lifecycle/lifecycle_panels.dart';

void main() {
  testWidgets('Lifecycle panels render health, liquidity, pantheon, history and rankings',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {
        'id': 'H-0044',
        'display_name': 'Amara Kline',
        'credits': 18420,
        'standing': 742,
        'health': 94,
        'vitality': 88,
        'lifespan_days': 1080,
        'age_years': 48,
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
        'vitality': 88,
        'health': 94,
        'ageYears': 48,
        'successor': {
          'successor_name': 'Kaelen Kline',
          'successor_human_id': 'H-0099',
          'heir_pct': 70,
          'trust_pct': 20,
          'family_pct': 10,
        },
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
          {'name': 'Neo Olympia', 'score': 98.4, 'population': 42000, 'gdp': 1500000},
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

    final authorityEvents = [
      {
        'id': 'auth-1',
        'authority': 'Public Works Commission',
        'action': 'APPOINTED',
        'timestamp': 'Day 120',
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

    final pantheonData = {
      'deceasedPantheon': [
        {
          'display_name': 'Founder Marcus Vance',
          'avatarInitials': 'MV',
          'lifespanYears': 82,
          'dynastyName': 'Vance Legacy',
          'final_legacy': 942,
          'bio': 'Pioneered zero-loss geothermal conversion grids across District 4.',
          'majorAchievements': ['Architect of the Geothermal Charter', 'Philanthropic Trust Founder'],
        },
      ],
      'livingLeaders': [
        {
          'display_name': 'Senator Elena Rostova',
          'roleTitle': 'High Chancellor',
          'age': 67,
          'wisdomBonus': 25,
          'composite_legacy_score': 875,
        },
      ],
      'achievements': [
        {
          'title': 'Grand Infrastructure Endowment',
          'category': 'PHILANTHROPY',
          'description': 'Endowed 50,000 Credits to municipal water reclamation.',
          'date': 'Day 140',
        },
      ],
    };

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SuccessionPanel(state: state, busy: false, action: (cb) async {}),
                LegacyPersonalFinancePanel(state: state, busy: false, action: (cb) async {}),
                InstitutionSolvencyPanel(state: state, busy: false, action: (cb) async {}),
                NegotiatedContractsPanel(state: state, busy: false, action: (cb) async {}),
                const WorldIntegrityPanel(state: state),
                const MacroLiquidityPanel(state: state),
                const HumanServicesPanel(state: state),
                const LedgerPanel(state: state),
                WorldFeedPanel(events: feedEvents),
                NotificationsPanel(state: state, notifications: notifications, unreadNotifications: 1, busy: false, action: (cb) async {}),
                OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
                CivicMembershipHistoryPanel(membershipEvents: membershipEvents),
                AuthorityHistoryPanel(authorityEvents: authorityEvents),
                const WorldRankingsPanel(state: state),
                const HistoryArchivePanel(state: state),
                PantheonPanel(pantheon: pantheonData),
              ],
            ),
          ),
        ),
      ),
    );

    // SuccessionPanel
    expect(find.text('LIFE & LEGACY / SUCCESSION PLAN'), findsOneWidget);
    expect(find.textContaining('Kaelen Kline'), findsOneWidget);

    // WorldIntegrityPanel
    expect(find.text('WORLD INTEGRITY / AUDIT'), findsOneWidget);
    expect(find.textContaining('m0_conservation: OK'), findsOneWidget);

    // MacroLiquidityPanel
    expect(find.text('UC MONETARY STABILITY BOARD / MACRO BASE'), findsOneWidget);
    expect(find.text('100% Reserve Conserved'), findsOneWidget);

    // HumanServicesPanel
    expect(find.text('HUMAN SERVICES / CURRENT ACCESS'), findsOneWidget);

    // Pantheon
    expect(find.text('PANTHEON / DYNASTIC ARCHIVE & LEGACY'), findsOneWidget);
    expect(find.textContaining('Founder Marcus Vance'), findsWidgets);
    expect(find.textContaining('Senator Elena Rostova'), findsWidgets);
  });
}
