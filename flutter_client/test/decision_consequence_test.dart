import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/decision_consequence.dart';
import 'package:earth_client/shared/widgets/consequence_preview_card.dart';
import 'package:earth_client/shared/widgets/decision_consequence_dialog.dart';

void main() {
  test('DecisionConsequence presets serialize and instantiate correctly', () {
    final c1 = DecisionConsequence.machineAcquisition(
      machineName: 'EXTRACTION RIG',
      costCredits: 600,
      outputYield: '120 Material',
      businessName: 'Helios Industrial',
    );

    expect(c1.actionTitle, contains('Acquire Industrial Machine'));
    expect(c1.immediateCost, contains('600.00 CR'));
    expect(c1.isPermanent, isTrue);
    expect(c1.affectedEntities, contains('Helios Industrial'));

    final c2 = DecisionConsequence.municipalTaxAdjustment(
      cityName: 'New Geneva',
      oldRatePct: 5.0,
      newRatePct: 8.0,
    );

    expect(c2.isPermanent, isFalse);
    expect(c2.actionCategory, 'MUNICIPAL CIVIC GOVERNANCE');
    expect(c2.expectedBenefit, contains('Municipal Treasury Budget'));

    final json = c1.toJson();
    final decoded = DecisionConsequence.fromJson(json);
    expect(decoded.actionTitle, c1.actionTitle);
    expect(decoded.isPermanent, isTrue);
  });

  testWidgets('ConsequencePreviewCard renders all 6 consequence pillars', (tester) async {
    final consequence = DecisionConsequence.dividendDistribution(
      businessName: 'OmniCorp',
      totalAmount: 5000,
      shareholderCount: 8,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsequencePreviewCard(consequence: consequence),
        ),
      ),
    );

    expect(find.text('EQUITY CAPITAL ALLOCATION'), findsOneWidget);
    expect(find.text('PERMANENT'), findsOneWidget);
    expect(find.text('Declare Corporate Dividend: OmniCorp'), findsOneWidget);
    expect(find.text('IMMEDIATE COST'), findsOneWidget);
    expect(find.text('5000.00 CR debited from corporate treasury'), findsOneWidget);
    expect(find.text('EXPECTED BENEFIT'), findsOneWidget);
    expect(find.text('SYSTEMIC & OPERATIONAL RISK'), findsOneWidget);
    expect(find.text('IMPACT HORIZON'), findsOneWidget);
    expect(find.text('AFFECTED ENTITIES & NETWORKS'), findsOneWidget);
    expect(find.text('OmniCorp'), findsOneWidget);
  });

  testWidgets('DecisionConsequenceDialog confirms decision on proceed', (tester) async {
    bool? confirmed;

    final consequence = DecisionConsequence.governanceVote(
      proposalTitle: 'Energy Grid Expansion',
      voteType: 'YES',
      votingPower: 12.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                confirmed = await showDecisionConsequenceDialog(
                  context,
                  consequence: consequence,
                );
              },
              child: const Text('OPEN DIALOG'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN DIALOG'));
    await tester.pumpAndSettle();

    expect(find.text('EXECUTIVE IMPACT ASSESSMENT'), findsOneWidget);
    expect(find.text('CAST SOVEREIGN BALLOT (YES)'), findsOneWidget);

    final confirmBtn = find.byKey(const Key('btn-confirm-consequence-decision'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });
}
