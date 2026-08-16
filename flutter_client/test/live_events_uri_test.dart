import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/command_center/command_center_screen.dart';
import 'package:earth_client/features/command_center/dashboard.dart';

void main() {
  test('maps navigation topics to app section titles', () {
    expect(dashboardSectionTitle('market'), 'CENTRAL MARKET');
    expect(dashboardSectionTitle('technology'), 'TECHNOLOGY');
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
}
