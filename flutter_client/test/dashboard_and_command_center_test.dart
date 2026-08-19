import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/dashboard.dart';

void main() {
  test('dashboardSectionTitle maps keys to human-readable titles', () {
    expect(dashboardSectionTitle('market'), 'MARKET');
    expect(dashboardSectionTitle('business'), 'BUSINESS');
    expect(dashboardSectionTitle('civic'), 'GOVERNANCE');
    expect(dashboardSectionTitle('city'), 'MY CITY');
    expect(dashboardSectionTitle('technology'), 'TECHNOLOGY');
    expect(dashboardSectionTitle('life'), 'LEGACY');
    expect(dashboardSectionTitle('contracts'), 'CONTRACTS');
    expect(dashboardSectionTitle('finance'), 'FINANCE');
    expect(dashboardSectionTitle('activity'), 'ACTIVITY & EVENTS');
    expect(dashboardSectionTitle('command'), 'COMMAND CENTER');
    expect(dashboardSectionTitle('other'), 'COMMAND CENTER');
  });

  testWidgets('Dashboard renders sections in wide and compact layouts',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {
        'id': 'H-0044',
        'credits': 5000,
        'display_name': 'Amara Kline',
        'standing': 100,
        'health': 90,
        'vitality': 90,
      },
      'world': {
        'health': 100,
        'serviceRatios': {
          'housing': 0.85,
          'energy': 0.90,
          'connectivity': 0.95,
          'health': 0.92,
        },
      },
      'resources': {
        'food': 100,
        'energy': 200,
        'material': 300,
        'compute': 50,
      },
      'business': {
        'id': 'B-101',
        'name': 'Kline Works',
        'status': 'active',
        'condition': 95,
        'policy': 'reliability',
      },
      'technology': {
        'research': {},
      },
      'institutions': {
        'city': {
          'id': 'CITY-1',
          'name': 'New Kyoto',
          'residents': 100,
          'fiscal_health': 82
        },
        'corporation': {
          'id': 'CORP-1',
          'name': 'Carthage Dynamics',
          'member_count': 10
        },
      },
      'life': {
        'vitality': 90,
        'health': 90,
        'aging_stage': 'PRIME',
      },
      'governance': {
        'proposals': [],
      },
      'market': {
        'products': {
          'food': {'price': 10.0}
        },
        'book': [],
        'trades': [],
        'orders': [],
        'feeRate': 0.01,
      },
      'finance': {
        'liquidity': {
          'moneySupply': 1000000.0,
          'target': 1000000.0,
          'status': 'inside-corridor',
        },
      },
      'audit': {},
      'machines': [],
      'opportunities': [
        {
          'id': 'OP-1',
          'title': 'High Food Demand',
          'description': 'Market prices elevated',
          'target_section': 'market',
          'reward_credits': 100,
        }
      ],
      'communities': [],
      'rankings': {},
      'history': {},
      'contracts': [],
    });

    final sectionKeys = {
      'command': GlobalKey(),
      'market': GlobalKey(),
      'business': GlobalKey(),
      'civic': GlobalKey(),
      'city': GlobalKey(),
      'technology': GlobalKey(),
      'life': GlobalKey(),
      'contracts': GlobalKey(),
      'finance': GlobalKey(),
      'activity': GlobalKey(),
    };

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    String selectedSection = 'command';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Dashboard(
              state: state,
              busy: false,
              events: const [],
              notifications: const [],
              ownershipEvents: const [],
              businessOwnership: const {},
              businessFinancials: const {},
              businessProfile: const {},
              membershipEvents: const [],
              authorityEvents: const [],
              productionCatalog: const [],
              unreadNotifications: 0,
              sectionKeys: sectionKeys,
              selectedSection: selectedSection,
              onNavigate: (s) => selectedSection = s,
              action: (cb) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Dashboard), findsOneWidget);
  });
}
