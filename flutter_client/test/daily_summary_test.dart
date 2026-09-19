import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/models/daily_summary.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/command_center/daily_summary_dialog.dart';

void main() {
  test('DailySummaryReport parses fromJson with all nested fields', () {
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
      'financial': {
        'incomeUnits': '1425000',
        'expensesUnits': '482000',
        'netCashflowUnits': '943000',
        'taxesUnits': '220000',
        'marketSalesUnits': '775000',
        'marketPurchasesUnits': '0',
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
      'buildings': {
        'operatedBuildingCount': 4,
        'activeMachines': 4,
        'degradedMachinesCount': 1,
        'pendingContractsCount': 2,
      },
      'governance': {
        'eventCount': 1,
        'events': [
          {'id': 'gov-1', 'type': 'GOVERNANCE_POLICY_PASSED', 'title': 'Policy passed', 'details': 'Energy Infrastructure Subsidy', 'gameDay': 185},
        ],
      },
      'alerts': {
        'unreadNotifications': 2,
        'unreadComms': 1,
        'criticalAlertsCount': 0,
      },
      'highlights': [
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

    final report = DailySummaryReport.fromJson(json);
    expect(report.gameDay, 185);
    expect(report.netWealthDelta.delta, 5600.0);
    expect(report.financial.netCashflowUnits, '943000');
    expect(report.financial.incomeUnits, '1425000');
    expect(report.financial.expensesUnits, '482000');
    expect(report.marketMovements.length, 1);
    expect(report.buildings.operatedBuildingCount, 4);
    expect(report.governance.eventCount, 1);
    expect(report.alerts.unreadNotifications, 2);
    expect(report.highlights.length, 1);
  });

  testWidgets(
      'DailySummaryDialog renders a unified briefing and triggers action',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    String? navigatedSection;

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/house/daily-summary') {
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
            'financial': {
              'incomeUnits': '1425000',
              'expensesUnits': '482000',
              'netCashflowUnits': '943000',
              'marketSalesUnits': '775000',
              'marketPurchasesUnits': '0',
              'taxesUnits': '220000',
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
            'buildings': {
              'operatedBuildingCount': 4,
            },
            'governance': {
              'eventCount': 1,
              'events': [
                {'id': 'gov-1', 'type': 'GOVERNANCE_POLICY_PASSED', 'title': 'Policy passed', 'details': 'Energy Infrastructure Subsidy', 'gameDay': 185},
              ],
            },
            'alerts': {
              'unreadNotifications': 2,
              'unreadComms': 1,
              'criticalAlertsCount': 0,
            },
            'highlights': [
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
          body: DailySummaryDialog(
            api: api,
            onNavigate: (section) => navigatedSection = section,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('DAY 185 RESULTS'), findsOneWidget);
    expect(find.text('+9430.00 C'), findsNWidgets(2));
    expect(find.text('+14250.00 C'), findsNWidgets(3));
    expect(find.text('-4820.00 C'), findsNWidgets(2));
    expect(find.text('WHAT REQUIRES ATTENTION'), findsOneWidget);
    expect(find.text('Capitalize on Energy Rally'), findsOneWidget);

    // Click directive action button
    final directiveBtn = find.byKey(const Key('btn-directive-rec_energy'));
    expect(directiveBtn, findsOneWidget);
    await tester.ensureVisible(directiveBtn);
    await tester.tap(directiveBtn);
    await tester.pump();

    expect(navigatedSection, 'market');
  });
}
