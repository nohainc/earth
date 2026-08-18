import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/core/nano_markup_helper.dart';
import 'package:earth_client/features/contracts/supply_contracts_dialog.dart';

void main() {
  testWidgets('SupplyContractsDialog renders active agreements, proposals, ticks, and wizard',
      (tester) async {
    final mockClient = MockClient((request) async {
      final path = request.url.path;

      if (path == '/api/contracts/supply') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'supplyContracts': [
              {
                'contract_id': 'CTR-882',
                'title': 'Quantum Core Energy Supply Agreement',
                'proposer_id': 'H-0012',
                'counterparty_id': 'H-0044',
                'status': 'accepted',
                'starts_game_day': 160,
                'ends_game_day': 190,
                'proposer_display_name': 'Dmitri Rostov',
                'counterparty_display_name': 'Amara Vance',
                'resource_type': 'energy',
                'daily_quantity': '50.00',
                'unit_price': '14.50',
                'total_days': 30,
                'delivered_days': 18,
                'default_days': 1,
                'consecutive_defaults': 0,
                'max_consecutive_defaults': 3,
                'escrow_total': '21750.00',
                'escrow_remaining': '8700.00',
                'penalty_per_default': '100.00',
                'vault_id': 'VAULT-CTR-882',
                'vault_locked_amount': '21750.00',
                'vault_released_amount': '13050.00',
                'vault_refunded_amount': '0.00',
                'vault_status': 'locked',
              },
              {
                'contract_id': 'CTR-904',
                'title': 'High-Purity Silicon Supply Tender',
                'proposer_id': 'H-0089',
                'counterparty_id': 'H-0044',
                'status': 'proposed',
                'starts_game_day': 184,
                'ends_game_day': 214,
                'proposer_display_name': 'Elena Thorne',
                'counterparty_display_name': 'Amara Vance',
                'resource_type': 'material',
                'daily_quantity': '25.00',
                'unit_price': '28.00',
                'total_days': 30,
                'delivered_days': 0,
                'default_days': 0,
                'consecutive_defaults': 0,
                'max_consecutive_defaults': 3,
                'escrow_total': '21000.00',
                'escrow_remaining': '21000.00',
                'penalty_per_default': '250.00',
                'vault_id': 'VAULT-CTR-904',
                'vault_locked_amount': '21000.00',
                'vault_status': 'locked',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/contracts/CTR-882/ticks') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'ticks': [
              {
                'id': 'tick-184',
                'contract_id': 'CTR-882',
                'game_day': 184,
                'status': 'delivered',
                'quantity_delivered': '50.00',
                'credits_transferred': '725.00',
                'penalty_charged': '0.00',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/contracts/CTR-904/accept') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'status': 'accepted',
            'contractId': 'CTR-904',
            'escrowLocked': '21000.00',
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      if (path == '/api/contracts/supply/propose') {
        return http.Response(
          NanoMarkupHelper.encode({
            'ok': true,
            'contractId': 'CTR-999',
            'totalAmount': '15000.00',
            'status': 'proposed',
          }),
          200,
          headers: {'content-type': 'application/nanomarkup'},
        );
      }

      return http.Response('{}', 404);
    });

    final api = EarthApi(
      transport: EarthApiTransport(baseUrl: 'http://127.0.0.1:8899', client: mockClient),
    );

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplyContractsDialog(api: api),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Top Header & Active Tab
    expect(find.text('AUTOMATED SUPPLY CONTRACTS & ESCROW VAULT'), findsOneWidget);
    expect(find.text('ACTIVE (1)'), findsOneWidget);
    expect(find.text('PROPOSALS (1)'), findsOneWidget);

    // 2. Verify Active Agreement Card & Escrow Metrics
    expect(find.text('Quantum Core Energy Supply Agreement'), findsWidgets);
    expect(find.text('ESCROW VAULT METRICS'), findsOneWidget);
    expect(find.text('21750.00 CR'), findsWidgets);

    // 3. Switch to Proposals Tab
    await tester.tap(find.text('PROPOSALS (1)'));
    await tester.pumpAndSettle();

    expect(find.text('High-Purity Silicon Supply Tender'), findsWidgets);
    expect(find.text('ACCEPT AGREEMENT & LOCK ESCROW'), findsOneWidget);

    // 4. Accept Proposal
    await tester.tap(find.text('ACCEPT AGREEMENT & LOCK ESCROW'));
    await tester.pumpAndSettle();

    // 5. Switch to New Tender Wizard Tab
    await tester.tap(find.text('NEW TENDER'));
    await tester.pumpAndSettle();

    expect(find.text('TRANSMIT BINDING SUPPLY AGREEMENT TENDER'), findsOneWidget);
    expect(find.text('TRANSMIT BINDING SUPPLY TENDER'), findsOneWidget);

    // Tap to submit
    await tester.ensureVisible(find.text('TRANSMIT BINDING SUPPLY TENDER'));
    await tester.tap(find.text('TRANSMIT BINDING SUPPLY TENDER'));
    await tester.pumpAndSettle();
  });
}
