import 'package:http/http.dart' as http;

import '../../earth_http_client.dart';
import '../nano_markup_helper.dart';

const _apiVersion = '2026-08';
final http.Client _sharedClient = createEarthHttpClient();

class EarthApiTransport {
  final String baseUrl;
  final http.Client? _clientOverride;
  http.Client get client => _clientOverride ?? _sharedClient;

  EarthApiTransport({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL', defaultValue: ''),
        _clientOverride = client;

  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestId =
        'flutter-${DateTime.now().microsecondsSinceEpoch}-${method.toLowerCase()}';
    final headers = <String, String>{
      'content-type': 'application/nanomarkup',
      'accept': 'application/nanomarkup, application/json',
      'X-Request-ID': requestId,
    };
    final correlationId = body?['correlationId']?.toString().trim();
    if (method == 'POST' || method == 'DELETE') {
      headers['Idempotency-Key'] =
          correlationId != null && correlationId.isNotEmpty
              ? correlationId
              : requestId;
    }
    final encodedBody = NanoMarkupHelper.encode(body ?? {});
    final response = method == 'POST'
        ? await client.post(uri, headers: headers, body: encodedBody)
        : method == 'DELETE'
            ? await client.delete(uri, headers: headers)
            : await client.get(uri, headers: headers);
    final apiVersion = response.headers['x-earth-api-version'];
    if (apiVersion != null && apiVersion != _apiVersion) {
      throw EarthApiException(
          'Incompatible EARTH API version $apiVersion (expected $_apiVersion)');
    }
    dynamic decoded;
    try {
      decoded = NanoMarkupHelper.decode(response.body);
    } catch (_) {
      throw EarthApiException(
          'The server returned an unexpected response (HTTP ${response.statusCode})',
          statusCode: response.statusCode);
    }
    if (response.statusCode >= 400) {
      final requestId = response.headers['x-request-id'];
      final payload = decoded is Map ? decoded : const <String, dynamic>{};
      throw EarthApiException(
        '${payload['error'] ?? 'Request failed'}',
        code: '${payload['code'] ?? 'REQUEST_FAILED'}',
        correlationId: '${payload['correlationId'] ?? requestId ?? ''}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
