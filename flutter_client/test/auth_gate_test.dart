import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/auth/auth_gate.dart';
import 'package:earth_client/features/auth/auth_screen.dart';

void main() {
  testWidgets('AuthGate renders AuthScreen on unauthenticated bootstrap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(),
      ),
    );
    await tester.pump();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('EARTH'), findsOneWidget);
  });
}
