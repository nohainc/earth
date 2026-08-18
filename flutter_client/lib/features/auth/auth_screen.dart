import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import 'admin_email_deliveries_dialog.dart';

String? validateAuthInput({
  required String email,
  required String password,
  String displayName = '',
  String passwordConfirmation = '',
  bool registration = false,
  bool passwordReset = false,
}) {
  if (!passwordReset && email.trim().isEmpty) return 'Email is required';
  if (password.length < 12) return 'Password must be at least 12 characters';
  if ((registration || passwordReset) &&
      password != passwordConfirmation) {
    return 'Passwords do not match';
  }
  if (registration && displayName.trim().isEmpty) {
    return 'Display name is required';
  }
  return null;
}

class AuthScreen extends StatefulWidget {
  final EarthApi api;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final String? initialResetToken;
  final String? initialMessage;

  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
    this.initialResetToken,
    this.initialMessage,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  final displayName = TextEditingController();
  final otp = TextEditingController();
  bool registerMode = false;
  bool recoveryMode = false;
  late bool resetMode;
  late String? resetToken;
  bool verificationPending = false;
  bool busy = false;
  String? error;
  bool noticeIsSuccess = false;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    resetToken = widget.initialResetToken;
    resetMode = resetToken != null && resetToken!.isNotEmpty;
    error = widget.initialMessage;
    noticeIsSuccess = widget.initialMessage != null;
  }

  void _startCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
      noticeIsSuccess = false;
    });
    try {
      if (resetMode) {
        final validation = validateAuthInput(
          email: email.text,
          password: password.text,
          passwordConfirmation: passwordConfirmation.text,
          passwordReset: true,
        );
        if (validation != null) throw Exception(validation);
        final result =
            await widget.api.completePasswordReset(resetToken!, password.text);
        if (mounted) {
          setState(() {
            resetMode = false;
            resetToken = null;
            password.clear();
            passwordConfirmation.clear();
            error = result['message']?.toString() ??
                'Password reset. You can now sign in.';
            noticeIsSuccess = true;
          });
        }
        return;
      }
      if (recoveryMode) {
        if (_cooldownSeconds > 0) {
          throw Exception('Please wait $_cooldownSeconds seconds before requesting another recovery email.');
        }
        if (email.text.trim().isEmpty) throw Exception('Email is required');
        final res = await widget.api.requestPasswordReset(email.text.trim());
        if (mounted) {
          _startCooldown(res['cooldownSeconds'] as int? ?? 60);
          setState(() {
            error = res['message']?.toString() ??
                'If that identity exists, recovery instructions have been sent. Please wait at least 60 seconds before requesting another reset.';
            noticeIsSuccess = true;
            recoveryMode = false;
          });
        }
        return;
      }
      if (registerMode) {
        final validation = validateAuthInput(
          email: email.text,
          password: password.text,
          displayName: displayName.text,
          passwordConfirmation: passwordConfirmation.text,
          registration: true,
        );
        if (validation != null) throw Exception(validation);
        await widget.api.register(email.text.trim(), password.text,
            displayName.text.trim(),
            passwordConfirmation: passwordConfirmation.text);
        if (mounted) {
          _startCooldown(60);
          setState(() {
            registerMode = false;
            verificationPending = true;
            error =
                'Identity created. Check your email to verify it, then sign in.';
            noticeIsSuccess = true;
          });
        }
      } else {
        final validation = validateAuthInput(
          email: email.text,
          password: password.text,
        );
        if (validation != null) throw Exception(validation);
        final result = await widget.api.login(email.text.trim(), password.text,
            otp: otp.text.trim());
        if (mounted) {
          widget.onAuthenticated(
              {'authenticated': true, 'human': result['human']});
        }
      }
    } catch (exception) {
      final message = exception.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          error = message;
          noticeIsSuccess = false;
          verificationPending =
              message.toLowerCase().contains('verify your email');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendVerification() async {
    if (_cooldownSeconds > 0) return;
    if (email.text.trim().isEmpty) {
      setState(() {
        error = 'Email is required';
        noticeIsSuccess = false;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      noticeIsSuccess = false;
    });
    try {
      final result = await widget.api.resendVerification(email.text.trim());
      if (mounted) {
        _startCooldown(result['cooldownSeconds'] as int? ?? 60);
        setState(() {
          error = result['message']?.toString() ??
              'If the identity exists, a new verification email was sent.';
          noticeIsSuccess = true;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.toString().replaceFirst('Exception: ', '');
          noticeIsSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    email.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    displayName.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: surfaceColor.withValues(alpha: .85),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.white12),
                ),
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('EARTH',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(
                          resetMode
                              ? 'Set a new password'
                              : recoveryMode
                                  ? 'Recover your identity'
                                  : registerMode
                                      ? 'Create your Human identity'
                                      : 'Enter the shared world',
                          style: const TextStyle(color: mutedColor)),
                      const SizedBox(height: 24),
                      if (registerMode && !recoveryMode) ...[
                        TextField(
                            controller: displayName,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Display name')),
                        const SizedBox(height: 12),
                      ],
                      if (!resetMode)
                        TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration:
                                const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 12),
                      if (!recoveryMode)
                        TextField(
                            controller: password,
                            obscureText: true,
                            onSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                                labelText: resetMode
                                    ? 'New password (12+ characters)'
                                    : 'Password (12+ characters)')),
                      if ((registerMode || resetMode) && !recoveryMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: passwordConfirmation,
                            obscureText: true,
                            onSubmitted: (_) => submit(),
                            decoration: const InputDecoration(
                                labelText: 'Repeat password')),
                      ],
                      if (!registerMode && !recoveryMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: otp,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Authenticator code (if enabled)')),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!,
                            style: TextStyle(
                                color: noticeIsSuccess
                                    ? cyanAccentColor
                                    : Colors.redAccent))
                      ],
                      if (_cooldownSeconds > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF38BDF8).withAlpha(80)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Cooldown active: retry in ${_cooldownSeconds}s. Check your spam folder if no email arrives.',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: busy || (recoveryMode && _cooldownSeconds > 0) ? null : submit,
                          child: Text(busy
                              ? 'Connecting…'
                              : resetMode
                                  ? 'Set new password'
                                  : recoveryMode
                                      ? (_cooldownSeconds > 0
                                          ? 'Wait (${_cooldownSeconds}s)'
                                          : 'Send recovery email')
                                      : registerMode
                                          ? 'Create identity'
                                          : 'Enter EARTH')),
                      if (!resetMode &&
                          !registerMode &&
                          !recoveryMode &&
                          (verificationPending ||
                              (error
                                      ?.toLowerCase()
                                      .contains('verify your email') ??
                                  false)))
                        TextButton(
                            onPressed: busy || _cooldownSeconds > 0 ? null : resendVerification,
                            child: Text(_cooldownSeconds > 0
                                ? 'Resend verification (${_cooldownSeconds}s)'
                                : 'Resend verification email')),
                      if (!resetMode && !registerMode && !recoveryMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      recoveryMode = true;
                                      error = null;
                                    }),
                            child: const Text('Forgot password?')),
                      if (!resetMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      recoveryMode = false;
                                      registerMode = !registerMode;
                                      verificationPending = false;
                                      error = null;
                                    }),
                            child: Text(recoveryMode || registerMode
                                ? 'Back to sign in'
                                : 'New to EARTH? Create an identity')),
                      if (resetMode)
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      resetMode = false;
                                      resetToken = null;
                                      error = null;
                                    }),
                            child: const Text('Back to sign in')),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => showAdminEmailDeliveriesDialog(context, api: widget.api),
                        icon: const Icon(Icons.mark_email_read_outlined, size: 13, color: EarthColors.textMuted),
                        label: const Text('Email Observability & Audit', style: TextStyle(color: EarthColors.textMuted, fontSize: 10)),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
}
