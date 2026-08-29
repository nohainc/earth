import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/features/auth/auth_screen.dart';

void main() {
  test('auth validation rejects incomplete credentials before transport', () {
    expect(
      validateAuthInput(email: '', password: 'short'),
      'Email is required',
    );
    expect(
      validateAuthInput(email: 'human@example.com', password: 'short'),
      'Password must be at least 12 characters',
    );
    expect(
      validateAuthInput(
        email: 'human@example.com',
        password: 'a' * 12,
        personName: '',
        houseSurname: 'Vance',
        passwordConfirmation: 'a' * 12,
        registration: true,
      ),
      'Given name must be at least 2 characters',
    );
  });

  testWidgets(
      'AuthScreen renders sign-in form by default and toggles registration',
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
    expect(find.text('The United Corporations'), findsOneWidget);
    expect(find.text('Enter EARTH'), findsOneWidget);
    expect(find.text('Create an identity'), findsOneWidget);

    // Toggle to registration mode
    await tester.tap(find.text('Create an identity'));
    await tester.pump();

    expect(find.text('Create an identity'), findsOneWidget);
    expect(find.text('Create identity'), findsOneWidget);
    expect(find.text('Given name'), findsOneWidget);
    expect(find.text('House surname'), findsOneWidget);
    expect(find.text('Repeat password'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
  });

  testWidgets(
      'AuthScreen renders password reset mode when initialResetToken is given',
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

  testWidgets('AuthScreen renders recovery mode and initialMessage banner',
      (tester) async {
    const api = EarthApi(baseUrl: 'http://127.0.0.1:8899');

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          api: api,
          onAuthenticated: (_) {},
          initialMessage: 'Email verified. Please sign in.',
        ),
      ),
    );

    expect(find.text('Email verified. Please sign in.'), findsOneWidget);

    // Toggle forgot password mode
    final forgotBtn = find.text('Forgot password?');
    if (forgotBtn.evaluate().isNotEmpty) {
      await tester.tap(forgotBtn);
      await tester.pump();
      expect(find.text('Send recovery email'), findsOneWidget);
    }
  });
}
