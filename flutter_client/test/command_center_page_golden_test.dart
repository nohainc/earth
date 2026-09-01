import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/executive_command_summary.dart';

void main() {
  testWidgets('Tier 2 command center page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const state = EarthState({
      'clock': {'day': 184, 'minute': 720},
      'human': {'credits': 18420, 'standing': 742, 'vitality': 95},
      'world': {'health': 100, 'serviceRatios': {'housing': .85, 'energy': .9, 'connectivity': .95, 'health': .92}},
      'institutions': {'city': {'name': 'New Kyoto'}},
      'business': {'name': 'Kline Works', 'condition': 95},
      'resources': {'energy': 340, 'material': 560, 'compute': 80},
      'market': {'products': {}, 'orders': []},
      'machines': [], 'contracts': [], 'opportunities': [],
    });
    await tester.pumpWidget(MaterialApp(theme: createEarthTheme(), home: const Scaffold(body: SingleChildScrollView(child: ExecutiveCommandSummary(state: state)))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/qa/command_center_1440.png'));
  });
}
