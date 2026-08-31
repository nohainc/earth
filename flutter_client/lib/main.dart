import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app/earth_app.dart';
import 'core/api/earth_api_transport.dart';
import 'core/ui_style_tokens.dart';

export 'app/earth_app.dart';
export 'app/theme.dart';
export 'core/api/earth_api.dart';
export 'core/api/earth_api_transport.dart';
export 'core/models/earth_state.dart';
export 'features/auth/auth_gate.dart';
export 'features/auth/auth_screen.dart';
export 'features/command_center/command_center_screen.dart';
export 'features/command_center/hero_card.dart';
export 'shared/widgets/earth_primitives.dart';
export 'shared/widgets/format_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UiStyleTokens.load();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    EarthApiTransport().reportClientError(
      message: details.exceptionAsString(),
      stack: details.stack?.toString(),
      context: {'library': details.library},
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    EarthApiTransport().reportClientError(
      message: error.toString(),
      stack: stack.toString(),
    );
    return false;
  };

  runApp(const EarthApp());
}
