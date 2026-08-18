import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/auth/auth_gate.dart';

void main() {
  testWidgets('AuthGate builds and displays loading state or auth screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(),
      ),
    );

    expect(find.byType(AuthGate), findsOneWidget);
    await tester.pump();
  });
}
