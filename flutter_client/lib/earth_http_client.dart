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

  @override
  String toString() => 'EarthApiException($code): $message';
}
