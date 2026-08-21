import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/daily_briefing.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/command_center/daily_briefing_dialog.dart';

void main() {
  test('DailyBriefingReport parses fromJson with all nested fields', () {
    final json = {
      'gameDay': 185,
      'daysElapsed': 1,
      'sinceDay': 184,
      'netWealthDelta': {
        'current': 158000.0,
        'previous': 152400.0,
        'delta': 5600.0,
        'deltaPct': 3.67,
      },
      'cashflow': {
        'totalIncome': 14250.0,
        'totalExpenses': 4820.0,
        'netProfit': 9430.0,
        'businessDividends': 6500.0,
        'marketSales': 7750.0,
        'machineMaintenance': 2620.0,
        'civicTaxes': 2200.0,
      },
      'marketMovements': [
        {
          'commodity': 'ENERGY',
          'currentPrice': 108.5,
          'previousPrice': 102.0,
          'deltaPct': 6.37,
          'trend': 'up',
          'volume24h': 14200,
        },
      ],
      'businessSummary': {
        'activeBusinesses': 2,
        'totalDailyOutput': 3840,
        'activeMachines': 4,
        'degradedMachinesCount': 1,
        'pendingContractsCount': 2,
      },
      'civicSummary': {
        'activeProposals': 3,
        'passedProposals24h': 1,
        'cityResidency': 'New Geneva',
        'cityTaxRatePct': 4.5,
        'recentCivicEvents': ['Passed: Energy Infrastructure Subsidy'],
      },
      'unreadAlerts': {
        'unreadNotifications': 2,
        'unreadComms': 1,
        'criticalAlertsCount': 0,
      },
      'recommendedDirectives': [
        {
          'id': 'rec_energy',
          'title': 'Capitalize on Energy Rally',
          'urgency': 'high',
          'reason': 'Energy spot price up +6.37%',
          'actionLabel': 'SELL ENERGY',
          'targetSection': 'market',
        },
      ],
    };

    final report = DailyBriefingReport.fromJson(json);
    expect(report.gameDay, 185);
    expect(report.netWealthDelta.delta, 5600.0);
    expect(report.cashflow.netProfit, 9430.0);
    expect(report.marketMovements.length, 1);
    expect(report.businessSummary.activeBusinesses, 2);
    expect(report.civicSummary.cityResidency, 'New Geneva');
    expect(report.unreadAlerts.unreadNotifications, 2);
    expect(report.recommendedDirectives.length, 1);
  });

  testWidgets(
      'DailyBriefingDialog renders a unified briefing and triggers action',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    String? navigatedSection;

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/player/daily-briefing') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'gameDay': 185,
            'daysElapsed': 1,
            'sinceDay': 184,
            'netWealthDelta': {
              'current': 158000.0,
              'previous': 152400.0,
              'delta': 5600.0,
              'deltaPct': 3.67,
            },
            'cashflow': {
              'totalIncome': 14250.0,
              'totalExpenses': 4820.0,
              'netProfit': 9430.0,
              'businessDividends': 6500.0,
              'marketSales': 7750.0,
              'machineMaintenance': 2620.0,
              'civicTaxes': 2200.0,
            },
            'marketMovements': [
              {
                'commodity': 'ENERGY',
                'currentPrice': 108.5,
                'previousPrice': 102.0,
                'deltaPct': 6.37,
                'trend': 'up',
                'volume24h': 14200,
              },
              {
                'commodity': 'MATERIAL',
                'currentPrice': 42.1,
                'previousPrice': 44.8,
                'deltaPct': -6.03,
                'trend': 'down',
                'volume24h': 9800,
              },
            ],
            'businessSummary': {
              'activeBusinesses': 2,
              'totalDailyOutput': 3840,
              'activeMachines': 4,
              'degradedMachinesCount': 1,
              'pendingContractsCount': 2,
            },
            'civicSummary': {
              'activeProposals': 3,
              'passedProposals24h': 1,
              'cityResidency': 'New Geneva',
              'cityTaxRatePct': 4.5,
              'recentCivicEvents': ['Passed: Energy Infrastructure Subsidy'],
            },
            'unreadAlerts': {
              'unreadNotifications': 2,
              'unreadComms': 1,
              'criticalAlertsCount': 0,
            },
            'recommendedDirectives': [
              {
                'id': 'rec_energy',
                'title': 'Capitalize on Energy Rally',
                'urgency': 'high',
                'reason': 'Energy spot price up +6.37%',
                'actionLabel': 'SELL ENERGY',
                'targetSection': 'market',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200,
          headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport =
        EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyBriefingDialog(
            api: api,
            onNavigate: (section) => navigatedSection = section,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SINCE YOUR LAST VISIT'), findsOneWidget);
    expect(find.text('158000.00 CR'), findsOneWidget);
    expect(find.text('+5600.00 CR'), findsOneWidget);
    expect(
        find.textContaining('+3.67% since previous day close'), findsOneWidget);
    expect(find.text('WHAT REQUIRES ATTENTION'), findsOneWidget);
    expect(find.text('Capitalize on Energy Rally'), findsOneWidget);

    // Click directive action button
    final directiveBtn = find.byKey(const Key('btn-directive-rec_energy'));
    expect(directiveBtn, findsOneWidget);
    await tester.tap(directiveBtn);
    await tester.pump();

    expect(navigatedSection, 'market');
  });
}
