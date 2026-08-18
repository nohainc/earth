import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/features/auth/admin_email_deliveries_dialog.dart';

void main() {
  testWidgets('AdminEmailDeliveriesDialog renders metrics and delivery rows', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path.startsWith('/api/admin/email-deliveries')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'bindingConfigured': true,
            'metrics': {
              'totalAccepted': 15,
              'totalFailed': 2,
              'lastDeliveryAt': '2026-08-18T14:30:00.000Z',
              'successRatePct': 88.24,
            },
            'deliveries': [
              {
                'id': 'DEL-101',
                'correlationId': 'corr-abc-123',
                'humanId': 'H-0044',
                'recipientMasked': 'c***e@earthuc.com',
                'action': 'reset_password',
                'status': 'accepted',
                'providerMessageId': 'msg-rec-101',
                'errorCode': null,
                'errorMessage': null,
                'createdAt': '2026-08-18T14:30:00.000Z',
              },
              {
                'id': 'DEL-102',
                'correlationId': 'corr-abc-124',
                'humanId': 'H-0045',
                'recipientMasked': 'b***b@earthuc.com',
                'action': 'verify_email',
                'status': 'failed',
                'providerMessageId': null,
                'errorCode': 'RATE_LIMITED',
                'errorMessage': 'Upstream rate limit exceeded',
                'createdAt': '2026-08-18T14:25:00.000Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.startsWith('/api/health/email')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'status': 'healthy',
            'bindingConfigured': true,
            'emailFromConfigured': true,
            'recentDeliveries': {
              'totalAccepted': 15,
              'totalFailed': 2,
              'lastDeliveryAt': '2026-08-18T14:30:00.000Z',
              'successRatePct': 88.24,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    });

    final transport = EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAdminEmailDeliveriesDialog(context, api: api),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('TRANSACTIONAL EMAIL OBSERVABILITY'), findsOneWidget);
    expect(find.text('BINDING HEALTHY'), findsOneWidget);
    expect(find.text('ACCEPTED'), findsNWidgets(2));
    expect(find.text('15'), findsOneWidget);
    expect(find.text('FAILED'), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('SUCCESS RATE'), findsOneWidget);
    expect(find.text('88.24%'), findsOneWidget);

    // Verify delivery rows
    expect(find.text('RESET PASSWORD'), findsOneWidget);
    expect(find.text('VERIFY EMAIL'), findsOneWidget);
    expect(find.text('Correlation: corr-abc-123'), findsOneWidget);
    expect(find.text('Correlation: corr-abc-124'), findsOneWidget);
    expect(find.text('Error [RATE_LIMITED]: Upstream rate limit exceeded'), findsOneWidget);
  });

  test('EarthApiEmailObservability methods query endpoints', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path.startsWith('/api/admin/email-deliveries')) {
        return http.Response(
          jsonEncode({'ok': true, 'bindingConfigured': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.startsWith('/api/health/email')) {
        return http.Response(
          jsonEncode({'ok': true, 'status': 'healthy'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    });

    final transport = EarthApiTransport(baseUrl: 'http://earth.test', client: mockClient);
    final api = EarthApi(baseUrl: 'http://earth.test', transport: transport);

    final deliveries = await api.getEmailDeliveries(limit: 10);
    expect(deliveries['ok'], true);
    expect(deliveries['bindingConfigured'], true);

    final health = await api.getEmailHealth();
    expect(health['ok'], true);
    expect(health['status'], 'healthy');
  });
}
