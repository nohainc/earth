import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/operations/business_dialogs.dart';

void main() {
  testWidgets('showBusinessManagerDialog appoints manager to business',
      (tester) async {
    bool appointed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showBusinessManagerDialog(
                context,
                (fn) async {
                  appointed = true;
                },
                'B-001',
              ),
              child: const Text('Open Manager Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Manager Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Appoint business manager'), findsOneWidget);
    expect(find.text('APPOINT'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Manager Human ID'), 'H-0099');
    await tester.pumpAndSettle();

    await tester.tap(find.text('APPOINT'));
    await tester.pumpAndSettle();

    expect(appointed, true);
  });

  testWidgets('showBusinessLiquidationDialog submits liquidation action',
      (tester) async {
    bool liquidated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showBusinessLiquidationDialog(
                context,
                (fn) async {
                  liquidated = true;
                },
                'B-001',
              ),
              child: const Text('Open Liquidate Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Liquidate Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Liquidate business?'), findsOneWidget);
    expect(find.text('LIQUIDATE'), findsOneWidget);

    await tester.tap(find.text('LIQUIDATE'));
    await tester.pumpAndSettle();

    expect(liquidated, true);
  });

  testWidgets('showBusinessConstitutionDialog updates threshold settings',
      (tester) async {
    bool updated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showBusinessConstitutionDialog(
                context,
                (fn) async {
                  updated = true;
                },
                {
                  'id': 'B-001',
                  'shareholder_vote_threshold': 0.6,
                  'board_approval_threshold': 0.6,
                  'dilution_notice_days': 7,
                },
              ),
              child: const Text('Open Constitution Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Constitution Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Business Constitution'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Dilution notice (days)'), '14');
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE CONSTITUTION'));
    await tester.pumpAndSettle();

    expect(updated, true);
  });

  testWidgets('showShareTransferDialog transfers shares to recipient',
      (tester) async {
    bool transferred = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showShareTransferDialog(
                context,
                (fn) async {
                  transferred = true;
                },
              ),
              child: const Text('Open Transfer Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Transfer Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer business shares'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Recipient Human ID'), 'H-0042');
    await tester.enterText(
        find.widgetWithText(TextField, 'Shares to transfer'), '5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(transferred, true);
  });

  testWidgets('showShareIssueDialog issues shares at price per share',
      (tester) async {
    bool issued = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showShareIssueDialog(
                context,
                (fn) async {
                  issued = true;
                },
                'B-001',
              ),
              child: const Text('Open Issue Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Issue Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Issue business shares'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Buyer Human ID'), 'H-0042');
    await tester.enterText(
        find.widgetWithText(TextField, 'Shares'), '20');
    await tester.enterText(
        find.widgetWithText(TextField, 'Price per share'), '50');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Issue'));
    await tester.pumpAndSettle();

    expect(issued, true);
  });

  testWidgets('showBusinessComposerDialog creates new business entity',
      (tester) async {
    bool registered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showBusinessComposerDialog(
                context,
                (fn) async {
                  registered = true;
                },
              ),
              child: const Text('Open Register Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Register Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Register a Business'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Business name'), 'Apex Semiconductors');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(registered, true);
  });

  testWidgets('showDividendDialog distributes business profit to shareholders',
      (tester) async {
    bool distributed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDividendDialog(
                context,
                (fn) async {
                  distributed = true;
                },
                'B-001',
              ),
              child: const Text('Open Dividend Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dividend Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Distribute dividends'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Total distribution (C)'), '5000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('DISTRIBUTE'));
    await tester.pumpAndSettle();

    expect(distributed, true);
  });

  testWidgets('showMergerDialog submits acquisition tender offer',
      (tester) async {
    bool proposed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showMergerDialog(
                context,
                (fn) async {
                  proposed = true;
                },
                'B-001',
              ),
              child: const Text('Open Merger Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Merger Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Propose merger tender offer'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Target business ID'), 'B-002');
    await tester.enterText(
        find.widgetWithText(TextField, 'Price per share (C)'), '150');
    await tester.pumpAndSettle();

    await tester.tap(find.text('PROPOSE'));
    await tester.pumpAndSettle();

    expect(proposed, true);
  });
}
