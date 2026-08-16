part of '../../main.dart';

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
      if (mounted) setState(() => session = value);
    } catch (_) {
      if (mounted) setState(() => session = {'authenticated': false});
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    final resetToken = Uri.base.queryParameters['reset_token'];
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
