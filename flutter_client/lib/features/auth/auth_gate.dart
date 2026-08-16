import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../command_center/command_center_screen.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final api = const EarthApi();
  Map<String, dynamic>? session;
  String? error;
  String? actionMessage;
  bool loadingSession = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final parameters = Uri.base.queryParameters;
    final verifyToken = parameters['verify_token'];
    if (verifyToken != null && verifyToken.isNotEmpty) {
      try {
        final result = await api.verifyEmail(verifyToken);
        actionMessage = result['message']?.toString() ??
            'Email verified. You can now sign in.';
      } catch (exception) {
        actionMessage = exception.toString().replaceFirst('Exception: ', '');
      }
    }
    try {
      final value = await api.session();
      if (mounted) {
        setState(() {
          session = value;
          loadingSession = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.toString().replaceFirst('Exception: ', '');
          loadingSession = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    final resetToken = Uri.base.queryParameters['reset_token'];
    if (loadingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (current == null && error != null) {
      return Scaffold(
        body: Center(
          child: EarthErrorState(
              message: error!,
              retry: () {
                setState(() {
                  loadingSession = true;
                  error = null;
                });
                _bootstrap();
              }),
        ),
      );
    }
    if (current == null) {
      return AuthScreen(
          api: api,
          onAuthenticated: (value) => setState(() => session = value),
          initialResetToken: resetToken,
          initialMessage: actionMessage);
    }
    if (current['authenticated'] != true) {
      return AuthScreen(
          api: api,
          onAuthenticated: (value) => setState(() => session = value),
          initialResetToken: resetToken,
          initialMessage: actionMessage);
    }
    return CommandCenter(
        onLogout: () => setState(() => session = {'authenticated': false}));
  }
}
