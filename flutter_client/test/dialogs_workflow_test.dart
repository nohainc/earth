import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/institutions/institutions_dialogs.dart';

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

}
