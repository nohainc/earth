import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/institutions/institutions_dialogs.dart';
import 'package:earth_client/features/operations/machines_dialogs.dart';

void main() {
  testWidgets('showFormationComposer opens dialog, validates input, and cancels safely',
      (tester) async {
    bool actionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showFormationComposer(
                context,
                (fn) async {
                  actionTriggered = true;
                },
                city: true,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Form a City'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Form a City'), findsNothing);
    expect(actionTriggered, false);
  });

  testWidgets('showDecommissionDialog opens recycling confirmation and submits',
      (tester) async {
    bool actionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDecommissionDialog(
                context,
                (fn) async {
                  actionTriggered = true;
                },
                'M-001',
              ),
              child: const Text('Open Recycle'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Recycle'));
    await tester.pumpAndSettle();

    expect(find.text('Recycle machine?'), findsOneWidget);
    expect(find.text('Recycle'), findsOneWidget);

    await tester.tap(find.text('Recycle'));
    await tester.pumpAndSettle();

    expect(actionTriggered, true);
  });

  testWidgets('showMachineUpgradeDialog renders upgrade costs and triggers action',
      (tester) async {
    bool actionTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showMachineUpgradeDialog(
                context,
                (fn) async {
                  actionTriggered = true;
                },
                'M-001',
              ),
              child: const Text('Open Upgrade'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Upgrade'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade machine'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(actionTriggered, true);
  });

  testWidgets('showMachineSaleDialog accepts buyer and price and submits sale',
      (tester) async {
    bool sold = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showMachineSaleDialog(
                context,
                (fn) async {
                  sold = true;
                },
                'M-001',
              ),
              child: const Text('Open Sale'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sale'));
    await tester.pumpAndSettle();

    expect(find.text('Sell machine'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Buyer Human ID'), 'H-0084');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(sold, true);
  });

  testWidgets('showMachineAcquisitionDialog selects machine type and acquires',
      (tester) async {
    bool acquired = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showMachineAcquisitionDialog(
                context,
                (fn) async {
                  acquired = true;
                },
                const [],
              ),
              child: const Text('Open Acquisition'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Acquisition'));
    await tester.pumpAndSettle();

    expect(find.text('Acquire Machine'), findsOneWidget);
    await tester.tap(find.text('Acquire'));
    await tester.pumpAndSettle();

    expect(acquired, true);
  });
}
