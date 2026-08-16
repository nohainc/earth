import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/command_center/opportunity_panel.dart';
import 'package:earth_client/features/command_center/command_center_screen.dart';

void main() {
  test('liveEventsUri constructs websocket URI from HTTP/HTTPS urls', () {
    final httpUri = liveEventsUri(
      configuredBase: 'http://api.earthuc.com',
      pageUri: Uri.parse('http://localhost:3000'),
    );
    expect(httpUri.toString(), 'ws://api.earthuc.com/edge/events');

    final httpsUri = liveEventsUri(
      configuredBase: 'https://earthuc.com',
      pageUri: Uri.parse('https://earthuc.com'),
    );
    expect(httpsUri.toString(), 'wss://earthuc.com/edge/events');

    final fallbackUri = liveEventsUri(
      configuredBase: '',
      pageUri: Uri.parse('https://staging.earthuc.com'),
    );
    expect(fallbackUri.toString(), 'wss://staging.earthuc.com/edge/events');

    final invalidUri = liveEventsUri(
      configuredBase: '',
      pageUri: Uri.parse('file:///index.html'),
    );
    expect(invalidUri, null);
  });

  testWidgets('OpportunityPanel renders high, medium, and low priority signals',
      (tester) async {
    final opportunities = [
      {
        'title': 'High Demand for Energy',
        'detail': 'Sector 4 is facing power deficits; sell energy at premium.',
        'signal': 'market',
        'priority': 'high',
      },
      {
        'title': 'Municipal Construction Proposal',
        'detail': 'Vote on New Kyoto transit expansion.',
        'signal': 'civic',
        'priority': 'medium',
      },
      {
        'title': 'Research Grant Available',
        'detail': 'UC R&D foundation is funding efficiency innovations.',
        'signal': 'technology',
        'priority': 'low',
      }
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpportunityPanel(opportunities: opportunities),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LIVE OPPORTUNITIES'), findsOneWidget);
    expect(find.text('High Demand for Energy'), findsOneWidget);
    expect(find.text('Municipal Construction Proposal'), findsOneWidget);
    expect(find.text('Research Grant Available'), findsOneWidget);
    expect(find.text('MARKET'), findsOneWidget);
    expect(find.text('CIVIC'), findsOneWidget);
    expect(find.text('TECHNOLOGY'), findsOneWidget);
  });
}
