import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/lifecycle/lifecycle_dialogs.dart';

void main() {
  testWidgets('showSuccessorComposerDialog opens form, updates inputs, and submits plan',
      (tester) async {
    bool saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSuccessorComposerDialog(
                context,
                (fn) async {
                  saved = true;
                },
              ),
              child: const Text('Open Succession Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Succession Dialog'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plan succession'), findsOneWidget);
    expect(find.text('Save plan'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Successor name'), 'Kaelen Vance');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();

    expect(saved, true);
  });

  testWidgets('showSettleInheritanceDialog opens settlement confirmation and executes',
      (tester) async {
    bool settled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSettleInheritanceDialog(
                context,
                (fn) async {
                  settled = true;
                },
                predecessorId: 'H-001',
                defaultSuccessorName: 'Kaelen Vance',
              ),
              child: const Text('Open Settle Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Settle Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Settle Estate Inheritance'), findsOneWidget);
    expect(find.text('Execute inheritance'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Successor Human ID'), 'H-0099');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Execute inheritance'));
    await tester.pumpAndSettle();

    expect(settled, true);
  });

  testWidgets('showRecoveryDialog authorizes institution recovery',
      (tester) async {
    bool recovered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showRecoveryDialog(
                context,
                (fn) async {
                  recovered = true;
                },
                'CITY-0084',
                'City',
              ),
              child: const Text('Open Recovery Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Recovery Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Recover City'), findsOneWidget);
    expect(find.text('AUTHORIZE RECOVERY'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Recovery contribution (Credits)'), '250');
    await tester.pumpAndSettle();

    await tester.tap(find.text('AUTHORIZE RECOVERY'));
    await tester.pumpAndSettle();

    expect(recovered, true);
  });
}
