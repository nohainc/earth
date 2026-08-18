import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/map/planetary_map_dialog.dart';

void main() {
  testWidgets('PlanetaryMapDialog renders tactical grid, telemetry, and plot inspector', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/map/regions') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'regions': [
              {
                'id': 'REG-PACIFIC-RIM',
                'name': 'Pacific Rim Sprawl',
                'biome_type': 'coastal_megalopolis',
                'climate_status': 'temperate',
                'base_solar_index': 1.15,
                'base_geothermal_index': 1.30,
              },
              {
                'id': 'REG-SAHARAN-BASIN',
                'name': 'Saharan Solar Basin',
                'biome_type': 'hyper_arid_desert',
                'climate_status': 'arid',
                'base_solar_index': 2.40,
                'base_geothermal_index': 0.85,
              },
            ],
            'plots': [
              {
                'id': 'PLOT-PAC-01',
                'region_id': 'REG-PACIFIC-RIM',
                'plot_name': 'Neo-Tokyo High-Bay Terminal',
                'coord_x': 139.69,
                'coord_y': 35.68,
                'terrain_type': 'coastal',
                'primary_resource': 'compute',
                'base_yield_rate': '25.00',
                'development_level': 2,
                'max_level': 5,
                'infrastructure_name': 'Quantum Relay Server Bank',
                'lease_holder_id': null,
                'lease_holder_name': null,
                'daily_lease_fee': '75.00',
                'lease_expires_game_day': null,
                'accumulated_yield': '0.00',
                'last_harvested_game_day': null,
              },
              {
                'id': 'PLOT-PAC-02',
                'region_id': 'REG-PACIFIC-RIM',
                'plot_name': 'Yokohama Deepwater Dock',
                'coord_x': 139.63,
                'coord_y': 35.44,
                'terrain_type': 'marine',
                'primary_resource': 'energy',
                'base_yield_rate': '30.00',
                'development_level': 1,
                'max_level': 5,
                'infrastructure_name': 'Tidal Surge Generator',
                'lease_holder_id': 'H-0044',
                'lease_holder_name': 'Amara Vance',
                'daily_lease_fee': '60.00',
                'lease_expires_game_day': 214,
                'accumulated_yield': '120.00',
                'last_harvested_game_day': 180,
              },
            ],
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
          body: PlanetaryMapDialog(api: api, initialPlotId: 'PLOT-PAC-01'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PLANETARY TACTICAL GRID & CONCESSION LEASES'), findsOneWidget);
    expect(find.text('PACIFIC RIM SPRAWL'), findsOneWidget);
    expect(find.text('SAHARAN SOLAR BASIN'), findsOneWidget);

    // Initial plot inspected
    expect(find.text('Neo-Tokyo High-Bay Terminal'), findsOneWidget);
    expect(find.text('Quantum Relay Server Bank'), findsOneWidget);
    expect(find.text('CONCESSION AVAILABLE FOR LEASE'), findsOneWidget);
    expect(find.byKey(const Key('btn-claim-lease')), findsOneWidget);
  });

  testWidgets('PlanetaryMapDialog allows claiming concession lease', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/map/regions') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'regions': [
              {
                'id': 'REG-PACIFIC-RIM',
                'name': 'Pacific Rim Sprawl',
                'biome_type': 'coastal_megalopolis',
                'climate_status': 'temperate',
                'base_solar_index': 1.15,
                'base_geothermal_index': 1.30,
              },
            ],
            'plots': [
              {
                'id': 'PLOT-PAC-01',
                'region_id': 'REG-PACIFIC-RIM',
                'plot_name': 'Neo-Tokyo High-Bay Terminal',
                'coord_x': 139.69,
                'coord_y': 35.68,
                'terrain_type': 'coastal',
                'primary_resource': 'compute',
                'base_yield_rate': '25.00',
                'development_level': 2,
                'max_level': 5,
                'infrastructure_name': 'Quantum Relay Server Bank',
                'lease_holder_id': null,
                'lease_holder_name': null,
                'daily_lease_fee': '75.00',
                'lease_expires_game_day': null,
                'accumulated_yield': '0.00',
                'last_harvested_game_day': null,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/lease')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'totalPaid': '2250.00',
            'expiresGameDay': 214,
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
          body: PlanetaryMapDialog(api: api, initialPlotId: 'PLOT-PAC-01'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final claimBtn = find.byKey(const Key('btn-claim-lease'));
    expect(claimBtn, findsOneWidget);

    await tester.tap(claimBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Concession lease secured!'), findsOneWidget);
  });

  testWidgets('PlanetaryMapDialog allows harvesting yield on owned lease', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/map/regions') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'regions': [
              {
                'id': 'REG-PACIFIC-RIM',
                'name': 'Pacific Rim Sprawl',
                'biome_type': 'coastal_megalopolis',
                'climate_status': 'temperate',
                'base_solar_index': 1.15,
                'base_geothermal_index': 1.30,
              },
            ],
            'plots': [
              {
                'id': 'PLOT-PAC-02',
                'region_id': 'REG-PACIFIC-RIM',
                'plot_name': 'Yokohama Deepwater Dock',
                'coord_x': 139.63,
                'coord_y': 35.44,
                'terrain_type': 'marine',
                'primary_resource': 'energy',
                'base_yield_rate': '30.00',
                'development_level': 1,
                'max_level': 5,
                'infrastructure_name': 'Tidal Surge Generator',
                'lease_holder_id': 'H-0044',
                'lease_holder_name': 'Amara Vance',
                'daily_lease_fee': '60.00',
                'lease_expires_game_day': 214,
                'accumulated_yield': '120.00',
                'last_harvested_game_day': 180,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/harvest')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'harvestedAmount': 120.0,
            'resourceType': 'energy',
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
          body: PlanetaryMapDialog(
            api: api,
            initialPlotId: 'PLOT-PAC-02',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Yokohama Deepwater Dock'), findsOneWidget);
    expect(find.text('ACTIVE CONCESSION LEASE'), findsOneWidget);
    expect(find.byKey(const Key('btn-harvest-yield')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-harvest-yield')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Harvested 120.0 units of ENERGY'), findsOneWidget);
  });

  testWidgets('PlanetaryMapDialog allows upgrading infrastructure on owned lease', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/map/regions') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'regions': [
              {
                'id': 'REG-PACIFIC-RIM',
                'name': 'Pacific Rim Sprawl',
                'biome_type': 'coastal_megalopolis',
                'climate_status': 'temperate',
                'base_solar_index': 1.15,
                'base_geothermal_index': 1.30,
              },
            ],
            'plots': [
              {
                'id': 'PLOT-PAC-02',
                'region_id': 'REG-PACIFIC-RIM',
                'plot_name': 'Yokohama Deepwater Dock',
                'coord_x': 139.63,
                'coord_y': 35.44,
                'terrain_type': 'marine',
                'primary_resource': 'energy',
                'base_yield_rate': '30.00',
                'development_level': 1,
                'max_level': 5,
                'infrastructure_name': 'Tidal Surge Generator',
                'lease_holder_id': 'H-0044',
                'lease_holder_name': 'Amara Vance',
                'daily_lease_fee': '60.00',
                'lease_expires_game_day': 214,
                'accumulated_yield': '120.00',
                'last_harvested_game_day': 180,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/upgrade')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'newLevel': 2,
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
          body: PlanetaryMapDialog(
            api: api,
            initialPlotId: 'PLOT-PAC-02',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final upgBtn = find.byKey(const Key('btn-upgrade-plot'));
    expect(upgBtn, findsOneWidget);

    await tester.tap(upgBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Infrastructure upgraded to Mark 2!'), findsOneWidget);
  });
}
