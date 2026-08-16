import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/auth/auth_gate.dart';

void main() {
  testWidgets('AuthGate renders a retryable state when bootstrap fails',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('RECONNECT'), findsOneWidget);
  });
}
