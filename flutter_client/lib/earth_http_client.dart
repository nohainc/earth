import 'package:http/http.dart' as http;
import 'earth_http_client_stub.dart'
    if (dart.library.html) 'earth_http_client_web.dart' as platform;

http.Client createEarthHttpClient() => platform.createEarthHttpClient();

class EarthApiException implements Exception {
  final String message;
  final String code;
  final String? correlationId;
  final int? statusCode;

  const EarthApiException(this.message,
      {this.code = 'REQUEST_FAILED', this.correlationId, this.statusCode});

  bool get isValidationError => statusCode == 400 || code == 'VALIDATION_ERROR';
  bool get isAuthenticationError => statusCode == 401 || code == 'AUTHENTICATION_REQUIRED';
  bool get isAuthorizationError => statusCode == 403 || code == 'FORBIDDEN';
  bool get isNotFoundError => statusCode == 404 || code == 'NOT_FOUND';
  bool get isConflictError => statusCode == 409 || code == 'CONFLICT';
  bool get isRateLimitError => statusCode == 429 || code == 'RATE_LIMITED';
  bool get isServiceUnavailable => statusCode == 503 || code == 'SERVICE_UNAVAILABLE';

  @override
  String toString() => 'EarthApiException($code): $message';
}
