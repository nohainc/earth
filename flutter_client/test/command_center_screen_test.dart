import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/command_center/command_center_screen.dart';

void main() {
  test('liveEventsUri handles http and https schemes', () {
    expect(
      liveEventsUri(
        configuredBase: 'https://earthuc.com',
        pageUri: Uri.parse('https://earthuc.com/app'),
      ).toString(),
      'wss://earthuc.com/edge/events',
    );

    expect(
      liveEventsUri(
        configuredBase: '',
        pageUri: Uri.parse('http://localhost:8787/app'),
      ).toString(),
      'ws://localhost:8787/edge/events',
    );

    expect(
      liveEventsUri(
        configuredBase: '',
        pageUri: Uri.parse('file:///path/index.html'),
      ),
      isNull,
    );
  });

  testWidgets('CommandCenter builds and shows initial loading or error state',
      (tester) async {
    bool loggedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CommandCenter(onLogout: () => loggedOut = true),
      ),
    );

    expect(find.byType(CommandCenter), findsOneWidget);
    await tester.pump();
  });
}
