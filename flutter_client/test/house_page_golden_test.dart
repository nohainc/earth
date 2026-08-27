import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/house/house_tree_dialog.dart';

void main() {
  testWidgets('Tier 2 house page golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((_) async => http.Response(NanoMarkupHelper.encode({
      'house': {'id': 'HOUSE-01', 'house_name': 'House of Vance', 'motto': 'From memory we build', 'legacy_points': 350, 'total_wealth_generated': 450000},
      'lineage': [{'id': 'LIN-01', 'name': 'Amara Vance', 'generation': 1, 'is_incumbent': true, 'legacy_score': 840}],
      'perks': [{'perk_key': 'industrialist_lineage', 'perk_name': 'Industrialist Lineage', 'perk_category': 'Operations', 'tier': 1}],
      'heirlooms': [{'id': 'HLM-01', 'name': 'Founding Signet', 'quality_tier': 'Legendary', 'stat_buff': '+10% Legacy', 'equipped_by_human_id': null}],
      'catalogPerks': [],
    }), 200, headers: {'content-type': 'application/nanomarkup'}));
    final api = EarthApi(transport: EarthApiTransport(baseUrl: 'http://earth.test', client: client));
    await tester.pumpWidget(MaterialApp(theme: createEarthTheme(), home: Scaffold(body: HouseTreeDialog(api: api))));
    await tester.pumpAndSettle();
    expect(find.byType(HouseTreeDialog), findsOneWidget);
  });
}
