import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';

void main() {
  test('DELETE commands carry an idempotency key', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'x-earth-api-version': '2026-08'});
    });

    final result = await EarthApiTransport(
      baseUrl: 'https://earthuc.com',
      client: client,
    ).request('/api/market/orders/order-1', method: 'DELETE');

    expect(result, {'ok': true});
    expect(captured.method, 'DELETE');
    expect(captured.headers['idempotency-key'], startsWith('flutter-'));
  });
}
