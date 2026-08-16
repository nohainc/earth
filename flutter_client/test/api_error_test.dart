import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/earth_http_client.dart';

void main() {
  test('API errors preserve stable code, correlation ID and classifiers', () {
    const authError = EarthApiException(
      'Authentication required',
      code: 'AUTHENTICATION_REQUIRED',
      correlationId: 'request-123',
      statusCode: 401,
    );

    expect(authError.code, 'AUTHENTICATION_REQUIRED');
    expect(authError.correlationId, 'request-123');
    expect(authError.statusCode, 401);
    expect(authError.isAuthenticationError, isTrue);
    expect(authError.isValidationError, isFalse);
    expect(authError.toString(), contains('AUTHENTICATION_REQUIRED'));

    const validationError = EarthApiException(
      'Invalid amount',
      code: 'VALIDATION_ERROR',
      correlationId: 'val-456',
      statusCode: 400,
    );
    expect(validationError.isValidationError, isTrue);

    const forbiddenError = EarthApiException(
      'Only owner can distribute dividends',
      code: 'FORBIDDEN',
      correlationId: 'forb-789',
      statusCode: 403,
    );
    expect(forbiddenError.isAuthorizationError, isTrue);

    const conflictError = EarthApiException(
      'Proposal under challenge',
      code: 'CONFLICT',
      statusCode: 409,
    );
    expect(conflictError.isConflictError, isTrue);

    const rateLimitError = EarthApiException(
      'Too many requests',
      code: 'RATE_LIMITED',
      statusCode: 429,
    );
    expect(rateLimitError.isRateLimitError, isTrue);

    const unavailableError = EarthApiException(
      'Service unavailable',
      code: 'SERVICE_UNAVAILABLE',
      statusCode: 503,
    );
    expect(unavailableError.isServiceUnavailable, isTrue);
  });
}
