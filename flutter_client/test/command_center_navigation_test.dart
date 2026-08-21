import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/dashboard.dart';

void main() {
  EarthState buildMockState() {
    return const EarthState({
      'clock': {
        'day': 185,
        'gameDay': 185,
        'year': 1,
        'hour': 12,
        'minute': 0,
        'formatted': 'Day 185, 12:00'
      },
      'world': {
        'id': 'WORLD',
        'batch': 185,
        'name': 'EARTH Simulator',
        'population': 1000,
        'health': 94,
      },
      'human': {
        'id': 'H-0044',
        'name': 'Amara Vance',
        'credits': 150000.0,
        'standing': 'High Standing',
        'legacy': 'Legend',
        'politicalMaturity': true,
        'civicScore': 85.0,
        'alive': true,
      },
      'resources': {
        'energy': 100.0,
        'food': 50.0,
        'materials': 20.0,
        'computing': 10.0
      },
      'life': {
        'alive': true,
        'ageDays': 42,
        'politicalStatus': 'eligible',
        'successor': {
          'registered': true,
          'name': 'Kaelen Vance',
          'humanId': 'H-0089'
        },
      },
      'market': {
        'products': {
          'energy': 1.0,
          'food': 1.2,
          'materials': 1.5,
          'computing': 2.0
        },
        'orders': <dynamic>[],
        'trades': <dynamic>[],
        'book': <dynamic>[],
      },
      'business': {
        'businesses': <dynamic>[],
        'myShares': <dynamic>[],
        'financials': {
          'revenue': 50000.0,
          'netProfit': 12000.0,
          'taxObligations': 1500.0
        },
      },
      'governance': {
        'proposals': <dynamic>[],
        'roles': <dynamic>[],
      },
      'technology': {
        'research': {'progress': 75.0, 'target': 100.0, 'budget': 5000.0},
        'patents': <dynamic>[],
        'licenses': <dynamic>[],
      },
      'institutions': {
        'city': {'name': 'New Kyoto'},
        'corporation': {'name': 'Aether Dynamics'},
        'community': {'name': 'Carthage Makers'},
        'communities': <dynamic>[],
        'cities': <dynamic>[],
        'corporations': <dynamic>[],
      },
      'machines': <dynamic>[],
      'productionEvents': <dynamic>[],
      'aiAssistants': <dynamic>[],
      'aiRecommendations': <dynamic>[],
    });
  }

  testWidgets('Dashboard renders panels and sections seamlessly',
      (tester) async {
    final state = buildMockState();
    final keys = <String, GlobalKey>{
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Dashboard(
              state: state,
              busy: false,
              events: const <dynamic>[],
              notifications: const <dynamic>[],
              ownershipEvents: const <dynamic>[],
              businessOwnership: const <String, dynamic>{},
              businessFinancials: const <String, dynamic>{},
              businessProfile: const <String, dynamic>{},
              membershipEvents: const <dynamic>[],
              authorityEvents: const <dynamic>[],
              productionCatalog: const <dynamic>[],
              marketHistory: const <String, dynamic>{},
              pantheon: const <String, dynamic>{},
              personalFinanceData: const <String, dynamic>{},
              contracts: const <dynamic>[],
              isLiveConnected: true,
              isReconnecting: false,
              unreadNotifications: 0,
              sectionKeys: keys,
              selectedSection: 'command',
              action: (fn) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EXECUTIVE OVERVIEW'), findsOneWidget);
    expect(find.text('CREDITS'), findsOneWidget);
  });
}
