import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/governance/governance_dialogs.dart';

void main() {
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
}
