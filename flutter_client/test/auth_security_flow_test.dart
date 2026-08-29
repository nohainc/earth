import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/auth/auth_screen.dart';

void main() {
  group('Authentication Validation and Security Checks', () {
    test('validates identity names and email during registration', () {
      expect(
        validateAuthInput(
          email: '',
          password: 'password123456',
          passwordConfirmation: 'password123456',
          personName: 'Amara',
          houseSurname: 'Vance',
          registration: true,
        ),
        'Email is required',
      );

      expect(
        validateAuthInput(
          email: 'amara@earthuc.com',
          password: 'short',
          passwordConfirmation: 'short',
          personName: 'Amara',
          houseSurname: 'Vance',
          registration: true,
        ),
        'Password must be at least 12 characters',
      );

      expect(
        validateAuthInput(
          email: 'amara@earthuc.com',
          password: 'password123456',
          passwordConfirmation: 'different123456',
          personName: 'Amara',
          houseSurname: 'Vance',
          registration: true,
        ),
        'Passwords do not match',
      );

      expect(
        validateAuthInput(
          email: 'amara@earthuc.com',
          password: 'password123456',
          passwordConfirmation: 'password123456',
          personName: '',
          houseSurname: 'Vance',
          registration: true,
        ),
        'Given name must be at least 2 characters',
      );

      expect(
        validateAuthInput(
          email: 'amara@earthuc.com',
          password: 'password123456',
          passwordConfirmation: 'password123456',
          personName: 'Amara',
          houseSurname: 'Kline',
          registration: true,
        ),
        isNull,
      );
    });

    test('validates password reset input', () {
      expect(
        validateAuthInput(
          email: '',
          password: 'newpassword123456',
          passwordConfirmation: 'newpassword123456',
          passwordReset: true,
        ),
        isNull,
      );

      expect(
        validateAuthInput(
          email: '',
          password: 'newpassword123456',
          passwordConfirmation: 'different123456',
          passwordReset: true,
        ),
        'Passwords do not match',
      );
    });
  });
}
