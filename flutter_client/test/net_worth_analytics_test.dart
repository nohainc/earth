import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/finance/net_worth_chart_widget.dart';
import 'package:earth_client/features/finance/net_worth_analytics_dialog.dart';

void main() {
  testWidgets('NetWorthChartWidget renders empty and populated multi-asset snapshots', (tester) async {
    // Empty state
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NetWorthChartWidget(snapshots: []),
        ),
      ),
    );
    expect(find.text('No historical net-worth snapshots recorded yet.'), findsOneWidget);

    // Populated state
    final mockSnapshots = [
      {
        'game_day': 180,
        'liquid_credits': 15000.0,
        'commodity_valuation': 8000.0,
        'equity_valuation': 25000.0,
        'real_estate_valuation': 12000.0,
        'total_net_worth': 60000.0,
      },
      {
        'game_day': 181,
        'liquid_credits': 18000.0,
        'commodity_valuation': 9000.0,
        'equity_valuation': 28000.0,
        'real_estate_valuation': 13000.0,
        'total_net_worth': 68000.0,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetWorthChartWidget(snapshots: mockSnapshots),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('TOTAL WEALTH'), findsOneWidget);
    expect(find.text('68000.00 CR'), findsOneWidget);
    expect(find.text('DAY: '), findsOneWidget);
    expect(find.text('CASH: '), findsOneWidget);
  });

  testWidgets('NetWorthAnalyticsDialog renders KPI cards, chart, and asset breakdown', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/finance/net-worth-history') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'humanId': 'H-0044',
            'snapshots': [
              {
                'game_day': 155,
                'liquid_credits': 15000.0,
                'commodity_valuation': 8000.0,
                'equity_valuation': 25000.0,
                'real_estate_valuation': 12000.0,
                'total_net_worth': 60000.0,
              },
              {
                'game_day': 185,
                'liquid_credits': 40000.0,
                'commodity_valuation': 20000.0,
                'equity_valuation': 68000.0,
                'real_estate_valuation': 30000.0,
                'total_net_worth': 158000.0,
              },
            ],
            'summary': {
              'currentNetWorth': 158000.0,
              'liquidCredits': 40000.0,
              'commodityValuation': 20000.0,
              'equityValuation': 68000.0,
              'realEstateValuation': 30000.0,
              'growthRatePct': 163.33,
              'peakNetWorth': 158000.0,
              'peakDay': 185,
              'assetAllocation': {
                'cashPct': 25.3,
                'commodityPct': 12.7,
                'equityPct': 43.0,
                'realEstatePct': 19.0,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      return http.Response(NanoMarkupHelper.encode({'ok': true}), 200, headers: {'content-type': 'application/x-nano-markup'});
    });

    final transport = EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetWorthAnalyticsDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PERSONAL & MULTI-GENERATIONAL NET-WORTH ANALYTICS'), findsOneWidget);
    expect(find.text('TOTAL NET WORTH'), findsOneWidget);
    expect(find.text('158000.00 CR'), findsWidgets);
    expect(find.text('+163.33% (30D)'), findsOneWidget);
    expect(find.text('ASSET ALLOCATION BREAKDOWN'), findsOneWidget);
    expect(find.text('LIQUID CREDITS'), findsOneWidget);
    expect(find.text('COMMODITIES'), findsOneWidget);
    expect(find.text('CORPORATE EQUITY'), findsOneWidget);
    expect(find.text('OTHER ASSETS'), findsOneWidget);
  });
}
