import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/command_center/command_center_screen.dart';
import 'package:earth_client/features/command_center/dashboard.dart';

void main() {
  test('maps navigation topics to app section titles', () {
    expect(dashboardSectionTitle('market'), 'CENTRAL MARKET');
    expect(dashboardSectionTitle('technology'), 'TECHNOLOGY');
    expect(dashboardSectionTitle('life'), 'LIFE & LEGACY');
    expect(dashboardSectionTitle('contracts'), 'CONTRACTS');
    expect(dashboardSectionTitle('unknown'), 'COMMAND CENTER');
  });

  test('uses configured API origin for live events', () {
    expect(
      liveEventsUri(
        configuredBase: 'https://api.example.test',
        pageUri: Uri.parse('https://earthuc.com/app'),
      ).toString(),
      'wss://api.example.test/edge/events',
    );
  });

  test('uses same-origin web deployment when API base is unset', () {
    expect(
      liveEventsUri(
        configuredBase: '',
        pageUri: Uri.parse('https://earthuc.com/app'),
      ).toString(),
      'wss://earthuc.com/edge/events',
    );
  });

  test('does not create a socket URL for non-web origins', () {
    expect(
      liveEventsUri(
        configuredBase: '',
        pageUri: Uri.parse('file:///tmp/app.html'),
      ),
      isNull,
    );
  });

  testWidgets('CommandCenter state deduplicates incoming events by eventKey', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommandCenter(onLogout: () {}),
      ),
    );

    final dynamic state = tester.state(find.byType(CommandCenter));
    final first = state.handleLiveMessage('{"eventKey":"evt-1","type":"market_trade"}');
    expect(first, isTrue);

    // Duplicate delivery of the exact same event key
    final second = state.handleLiveMessage('{"eventKey":"evt-1","type":"market_trade"}');
    expect(second, isFalse);

    // Distinct event key
    final third = state.handleLiveMessage('{"eventKey":"evt-2","type":"market_trade"}');
    expect(third, isTrue);

    // Handles map payload directly
    final fourth = state.handleLiveMessage({'eventKey': 'evt-3', 'type': 'world_day_started'});
    expect(fourth, isTrue);

    // Duplicate map payload
    final fifth = state.handleLiveMessage({'eventKey': 'evt-3', 'type': 'world_day_started'});
    expect(fifth, isFalse);

    // Malformed JSON string does not crash
    final malformed = state.handleLiveMessage('{malformed-json-payload}');
    expect(malformed, isTrue);

    // Null and empty payloads do not crash
    expect(state.handleLiveMessage(null), isFalse);

    // Live event triggers world refresh
    final worldEvent = state.handleLiveMessage('{"eventKey":"evt-4","type":"world_tick"}');
    expect(worldEvent, isTrue);
  });
}
