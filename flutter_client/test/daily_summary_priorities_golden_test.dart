import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/command_center/daily_summary_dialog.dart';

void main() {
  testWidgets('Tier 2 daily priorities golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((_) async => http.Response(NanoMarkupHelper.encode({
      'ok': true, 'gameDay': 185, 'daysElapsed': 1, 'sinceDay': 184,
      'netWealthDelta': {'current': 158000, 'previous': 152400, 'delta': 5600, 'deltaPct': 3.67},
      'financial': {'income': 0, 'expenses': 0, 'net': 0, 'taxes': 0},
      'marketMovements': [],
      'buildings': {'activeBusinesses': 2, 'totalDailyOutput': 3840, 'activeMachines': 4, 'degradedMachinesCount': 1, 'pendingContractsCount': 2},
      'governance': {'relevantEvents': []},
      'alerts': {'unreadNotifications': 2, 'unreadComms': 1, 'criticalAlertsCount': 0},
      'highlights': [{'id': 'rec_energy', 'title': 'Capitalize on Energy Rally', 'urgency': 'high', 'reason': 'Energy up', 'actionLabel': 'SELL ENERGY', 'targetSection': 'market'}],
    }), 200, headers: {'content-type': 'application/nanomarkup'}));
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://daily.test', client: client));
    await tester.pumpWidget(MaterialApp(theme: createEarthTheme(), home: Scaffold(body: DailySummaryDialog(api: api, onNavigate: (_) {}))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/daily_priorities_1440.png'));
  });
}
