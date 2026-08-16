import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/governance/governance_dialogs.dart';

void main() {
  testWidgets('showDelegateDialog accepts active human ID and delegates',
      (tester) async {
    bool delegated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDelegateDialog(
                context,
                (fn) async {
                  delegated = true;
                },
                'ROLE-001',
              ),
              child: const Text('Open Delegate'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Delegate'));
    await tester.pumpAndSettle();

    expect(find.text('Delegate authority'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Active Human ID'), 'H-0084');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delegate'));
    await tester.pumpAndSettle();

    expect(delegated, true);
  });

  testWidgets('showChallengeDialog accepts reason and files challenge',
      (tester) async {
    bool challenged = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showChallengeDialog(
                context,
                (fn) async {
                  challenged = true;
                },
                'PROP-001',
              ),
              child: const Text('Open Challenge'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Challenge'));
    await tester.pumpAndSettle();

    expect(find.text('File constitutional challenge'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Constitutional grounds (10–2000 characters)'),
        'Violation of Section 4 Article 2 of the United Corporations Charter');
    await tester.pumpAndSettle();

    await tester.tap(find.text('File challenge'));
    await tester.pumpAndSettle();

    expect(challenged, true);
  });

  testWidgets('showAppealRulingDialog issues High Court ruling',
      (tester) async {
    bool ruled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAppealRulingDialog(
                context,
                (fn) async {
                  ruled = true;
                },
                'PROP-001',
              ),
              child: const Text('Open Ruling'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Ruling'));
    await tester.pumpAndSettle();

    expect(find.text('Issue High Court ruling'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Judicial rationale (10–2000 characters)'),
        'The court finds no constitutional violation and upholds the proposal.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Issue ruling'));
    await tester.pumpAndSettle();

    expect(ruled, true);
  });

  testWidgets('showDisputeDialog opens arbitration dispute',
      (tester) async {
    bool disputed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDisputeDialog(
                context,
                (fn) async {
                  disputed = true;
                },
                'CONTRACT-001',
              ),
              child: const Text('Open Dispute'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dispute'));
    await tester.pumpAndSettle();

    expect(find.text('Open UC arbitration'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Reason (10–1000 characters)'),
        'Failure to deliver scheduled energy units within agreed timeframe');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit dispute'));
    await tester.pumpAndSettle();

    expect(disputed, true);
  });

  testWidgets('showResolveDialog resolves arbitration dispute',
      (tester) async {
    bool resolved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showResolveDialog(
                context,
                (fn) async {
                  resolved = true;
                },
                'CONTRACT-001',
              ),
              child: const Text('Open Resolve'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Resolve'));
    await tester.pumpAndSettle();

    expect(find.text('Resolve UC arbitration'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Resolution (10–1000 characters)'),
        'Arbitration board verifies partial fulfilment and grants resolution.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(resolved, true);
  });
}
