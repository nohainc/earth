import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/institutions/institutions_dialogs.dart';

void main() {
  testWidgets('showCommunityComposer accepts community name and submits',
      (tester) async {
    bool founded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showCommunityComposer(
                context,
                (fn) async {
                  founded = true;
                },
              ),
              child: const Text('Open Community Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Community Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Found New Community'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Community Name (Required)'), 'Pacific Syndicate');
    await tester.enterText(
        find.widgetWithText(TextField, 'Manifesto & Purpose (Required)'), 'Pacific oceanic clean energy consortium.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Found Community'));
    await tester.pumpAndSettle();

    expect(founded, true);
  });

  testWidgets('showTaxCharterDialog accepts tax rates and submits',
      (tester) async {
    bool saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showTaxCharterDialog(
                context,
                (fn) async {
                  saved = true;
                },
                'CITY-0084',
              ),
              child: const Text('Open Tax Charter Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Tax Charter Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Set city tax charter'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Income tax (%)'), '4.5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Sales tax (%)'), '2.5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE CHARTER'));
    await tester.pumpAndSettle();

    expect(saved, true);
  });
}
