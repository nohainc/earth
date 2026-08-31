import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../earth_http_client.dart';
import '../auth_storage.dart';
import '../nano_markup_helper.dart';

const _apiVersion = '2026-08';
final http.Client _sharedClient = createEarthHttpClient();

class EarthApiTransport {
  final String baseUrl;
  final http.Client? _clientOverride;
  http.Client get client => _clientOverride ?? _sharedClient;

  EarthApiTransport({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
        _clientOverride = client;

  static String _resolveDefaultBaseUrl() {
    const envUrl = String.fromEnvironment('EARTH_API_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        final port = Uri.base.port;
        if (port != 8788 && port != 8787) {
          return 'http://$host:8788';
        }
      }
    }
    return '';
  }

  Future<void> reportClientError({
    required String message,
    String? stack,
    String? endpoint,
    String? errorCode,
    int? statusCode,
    Map<String, dynamic>? context,
  }) async {
    if (endpoint == '/api/telemetry/error') return;
    try {
      final uri = Uri.parse('$baseUrl/api/telemetry/error');
      final headers = <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      };
      final token = await AuthStorage.getToken();
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }
      final payload = jsonEncode({
        'message': message,
        if (stack != null) 'stack': stack,
        if (endpoint != null) 'endpoint': endpoint,
        if (errorCode != null) 'errorCode': errorCode,
        if (statusCode != null) 'statusCode': statusCode,
        if (context != null) 'context': context,
        'source': 'client_flutter',
      });
      await client.post(uri, headers: headers, body: payload);
    } catch (_) {
      // Best-effort reporting
    }
  }

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
    final token = await AuthStorage.getToken();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final correlationId = body?['correlationId']?.toString().trim();
    if (method == 'POST' || method == 'DELETE' || method == 'PATCH') {
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
            : method == 'PATCH'
                ? await client.patch(uri, headers: headers, body: encodedBody)
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
      final errorMsg = '${payload['error'] ?? 'Request failed'}';
      final errorCode = '${payload['code'] ?? 'REQUEST_FAILED'}';
      unawaited(reportClientError(
        message: errorMsg,
        endpoint: path,
        errorCode: errorCode,
        statusCode: response.statusCode,
        context: {
          'method': method,
          if (correlationId != null) 'correlationId': correlationId,
        },
      ));
      throw EarthApiException(
        errorMsg,
        code: errorCode,
        correlationId: '${payload['correlationId'] ?? requestId ?? ''}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
