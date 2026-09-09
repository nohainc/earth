import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/governance/governance_dialogs.dart';

void main() {
  testWidgets('showProposalComposer renders and submits proposal',
      (tester) async {
    bool submitted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showProposalComposer(
                context,
                (fn) async {
                  submitted = true;
                },
                institutionId: 'OUC-001',
                scopeLabel: 'UC',
              ),
              child: const Text('Open Composer'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Composer'));
    await tester.pumpAndSettle();

    expect(find.text('Create UC proposal'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Title (8–140 characters)'),
        'Municipal Solar Grid Expansion');
    await tester.enterText(
        find.widgetWithText(TextField, 'Policy proposal (20–4000 characters)'),
        'Invest in civic solar infrastructure to boost energy output across Carthage.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit proposal'));
    await tester.pumpAndSettle();

    expect(submitted, true);
  });
}
