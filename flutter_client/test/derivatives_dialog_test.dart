import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/market/derivatives_dialog.dart';

void main() {
  testWidgets('DerivativesDialog renders orderbook, creates listing, and matches position', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/market/derivatives') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'commodity': 'energy',
            'ohlc': [
              {
                'game_day': 180,
                'open_price': 28.0,
                'high_price': 31.0,
                'low_price': 27.0,
                'close_price': 30.0,
                'volume': 1200.0,
              },
            ],
            'ma7': [29.0],
            'ma25': [28.0],
            'orderbook': [
              {
                'id': 'FUT-ENERGY-101',
                'seller_human_id': 'H-0012',
                'buyer_human_id': null,
                'commodity': 'energy',
                'contract_size': 250.0,
                'strike_price': 28.50,
                'expiry_game_day': 210,
                'collateral_locked': 250.0,
                'premium_paid': 0.0,
                'status': 'open',
              },
            ],
            'userPositions': [
              {
                'id': 'FUT-ENERGY-102',
                'seller_human_id': 'H-0044',
                'buyer_human_id': null,
                'commodity': 'energy',
                'contract_size': 100.0,
                'strike_price': 30.0,
                'expiry_game_day': 220,
                'collateral_locked': 100.0,
                'premium_paid': 0.0,
                'status': 'open',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path == '/api/market/futures/create') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'contractId': 'FUT-ENERGY-999',
            'commodity': 'energy',
            'size': 100.0,
            'strikePrice': 30.0,
            'expiryGameDay': 220,
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/buy')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'contractId': 'FUT-ENERGY-101',
            'totalPaid': '7125.00',
            'status': 'matched',
          }),
          200,
          headers: {'content-type': 'application/x-nano-markup'},
        );
      }

      if (path.endsWith('/cancel')) {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'contractId': 'FUT-ENERGY-102',
            'status': 'cancelled',
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
          body: DerivativesDialog(api: api),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('FINANCIAL DERIVATIVES & FUTURES TERMINAL'), findsOneWidget);
    expect(find.text('OPEN FORWARD CONTRACTS (ENERGY)'), findsOneWidget);

    // 1. Match / Buy contract
    final buyBtn = find.byKey(const Key('btn-buy-futures-FUT-ENERGY-101'));
    await tester.ensureVisible(buyBtn);
    await tester.pumpAndSettle();
    expect(buyBtn, findsOneWidget);
    await tester.tap(buyBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Futures position purchased'), findsOneWidget);

    // 2. Cancel listing
    final cancelBtn = find.byKey(const Key('btn-cancel-futures-FUT-ENERGY-102'));
    await tester.ensureVisible(cancelBtn);
    await tester.pumpAndSettle();
    expect(cancelBtn, findsOneWidget);
    await tester.tap(cancelBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('cancelled and collateral refunded'), findsOneWidget);

    // 3. Create listing
    final createBtn = find.byKey(const Key('btn-create-futures-listing'));
    await tester.ensureVisible(createBtn);
    await tester.pumpAndSettle();
    expect(createBtn, findsOneWidget);
    await tester.tap(createBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('created!'), findsOneWidget);
  });
}
