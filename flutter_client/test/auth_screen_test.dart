import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/features/auth/auth_screen.dart';

void main() {
  testWidgets('AuthScreen renders sign-in form by default and toggles registration',
      (tester) async {
    const api = EarthApi(baseUrl: 'http://127.0.0.1:8899');

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          api: api,
          onAuthenticated: (_) {},
        ),
      ),
    );

    expect(find.text('EARTH'), findsOneWidget);
    expect(find.text('Enter the shared world'), findsOneWidget);
    expect(find.text('Enter EARTH'), findsOneWidget);
    expect(find.text('New to EARTH? Create an identity'), findsOneWidget);

    // Toggle to registration mode
    await tester.tap(find.text('New to EARTH? Create an identity'));
    await tester.pump();

    expect(find.text('Create your Human identity'), findsOneWidget);
    expect(find.text('Create identity'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Repeat password'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
  });

  testWidgets('AuthScreen renders password reset mode when initialResetToken is given',
      (tester) async {
    const api = EarthApi(baseUrl: 'http://127.0.0.1:8899');

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          api: api,
          onAuthenticated: (_) {},
          initialResetToken: 'reset-token-xyz',
        ),
      ),
    );

    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.text('Set new password'), findsOneWidget);
    expect(find.text('New password (12+ characters)'), findsOneWidget);
    expect(find.text('Repeat password'), findsOneWidget);
  });
}
