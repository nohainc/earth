import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/contracts/contracts_panel.dart';

void main() {
  testWidgets('ContractsPanel renders parties, terms, amounts, and dispute actions',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 18420, 'standing': 742, 'legacy': 31},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'roles': [
        {'id': 'ROLE-OUC-DELEGATE', 'human_id': 'H-0044', 'assignment_status': 'active'}
      ],
    });

    final contracts = [
      {
        'id': 'CTR-001',
        'proposer_id': 'H-0045',
        'counterparty_id': 'H-0044',
        'title': 'Components supply agreement',
        'kind': 'supply',
        'amount': 450,
        'status': 'proposed',
        'start_day': 184,
        'end_day': 214,
        'dispute_id': null,
      },
      {
        'id': 'CTR-002',
        'proposer_id': 'H-0044',
        'counterparty_id': 'H-0046',
        'title': 'Compute power lease',
        'kind': 'capacity',
        'amount': 1200,
        'status': 'accepted',
        'start_day': 180,
        'end_day': 210,
        'dispute_id': 'DISP-001',
        'dispute_status': 'open',
        'dispute_reason': 'Failure to deliver contracted capacity',
      }
    ];

    bool actionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContractsPanel(
              state: state,
              busy: false,
              contracts: contracts,
              action: (cb) async {
                actionTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('NEGOTIATED CONTRACTS & ARBITRATION'), findsOneWidget);
    expect(find.text('ACTIVE AGREEMENTS'), findsOneWidget);
    expect(find.text('COMMITTED ESCROWS'), findsOneWidget);
    expect(find.text('OPEN DISPUTES'), findsOneWidget);

    expect(find.text('Components supply agreement (CTR-001)'), findsOneWidget);
    expect(find.text('PROPOSED'), findsOneWidget);
    expect(find.text('ACCEPT'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);

    expect(find.text('Compute power lease (CTR-002)'), findsOneWidget);
    expect(find.text('DISPUTED (open)'), findsOneWidget);
    expect(find.text('ARBITRATE & RESOLVE'), findsOneWidget);
    expect(find.text('PROPOSE NEW AGREEMENT'), findsOneWidget);

    // Verify info dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bilateral Agreements & Escrow'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    // Tap accept on CTR-001
    await tester.tap(find.text('ACCEPT'));
    await tester.pumpAndSettle();

    expect(actionTriggered, isTrue);
  });
}
