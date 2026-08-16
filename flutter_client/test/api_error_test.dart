import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/earth_http_client.dart';

void main() {
  test('API errors preserve stable code and correlation ID', () {
    const error = EarthApiException(
      'Authentication required',
      code: 'AUTHENTICATION_REQUIRED',
      correlationId: 'request-123',
      statusCode: 401,
    );

    expect(error.code, 'AUTHENTICATION_REQUIRED');
    expect(error.correlationId, 'request-123');
    expect(error.statusCode, 401);
    expect(error.toString(), contains('AUTHENTICATION_REQUIRED'));
  });
}
