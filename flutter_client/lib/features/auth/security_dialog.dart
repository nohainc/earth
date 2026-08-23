import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../shared/widgets/format_helpers.dart';

const _securityDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
  side: BorderSide(color: Colors.white12),
);
const _securityTitleStyle = TextStyle(
  color: inkColor,
  fontSize: 15,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.4,
);
const _securitySectionStyle = TextStyle(
  color: inkColor,
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.7,
);

Future<void> showMfaDialog(BuildContext context, EarthApi api) async {
  final code = TextEditingController();
  try {
    final enrollment = await api.enrollMfa();
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: surfaceColor,
              surfaceTintColor: Colors.transparent,
              shape: _securityDialogShape,
              title: const Text('Enable authenticator MFA',
                  style: _securityTitleStyle),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Add this secret to your authenticator app, then enter the six-digit code.',
                        style: TextStyle(color: mutedColor, fontSize: 12)),
                    const SizedBox(height: 12),
                    SelectableText('${enrollment['secret']}',
                        style: const TextStyle(
                            color: inkColor,
                            fontSize: 13,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            color: inkColor, letterSpacing: 1.3),
                        decoration: const InputDecoration(
                            labelText: 'Authenticator code',
                            labelStyle: TextStyle(color: mutedColor))),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () async {
                      await api.confirmMfa(code.text);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('Enable'))
              ],
            ));
  } catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exception.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

Future<void> showDisableMfaDialog(BuildContext context, EarthApi api) async {
  final code = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: _securityDialogShape,
        title:
            const Text('Disable authenticator MFA', style: _securityTitleStyle),
        content: TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: inkColor, letterSpacing: 1.3),
            decoration: const InputDecoration(
                labelText: 'Current six-digit code',
                labelStyle: TextStyle(color: mutedColor))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () async {
              try {
                await api.disableMfa(code.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Authenticator MFA disabled.')));
                }
              } catch (exception) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                      content: Text(exception
                          .toString()
                          .replaceFirst('Exception: ', ''))));
                }
              }
            },
            child: const Text('DISABLE'),
          ),
        ],
      ),
    );
  } catch (_) {}
}

Future<void> showSecurityDialog(
    BuildContext context, EarthApi api, VoidCallback onLogout) async {
  List<dynamic> sessions;
  try {
    sessions = await api.sessions();
  } catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exception.toString().replaceFirst('Exception: ', ''))));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: _securityDialogShape,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: violetColor, size: 20),
            SizedBox(width: 10),
            Text('Account security', style: _securityTitleStyle),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active sessions', style: _securitySectionStyle),
                const SizedBox(height: 8),
                if (sessions.isEmpty)
                  const Text('No active sessions were found.',
                      style: TextStyle(color: mutedColor))
                else
                  ...sessions.map((raw) {
                    final session = Map<String, dynamic>.from(raw as Map);
                    final current = session['current'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: EarthColors.cardSurface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: Icon(
                            current ? Icons.devices : Icons.device_unknown,
                            color: current ? violetColor : mutedColor,
                            size: 19),
                        title: Text(current ? 'This device' : 'Other session',
                            style: const TextStyle(
                                color: inkColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4)),
                        subtitle: Text(
                            'Created ${formatSecurityDate(session['created_at'])}\nExpires ${formatSecurityDate(session['expires_at'])}',
                            style: const TextStyle(
                                color: mutedColor,
                                fontSize: 10,
                                height: 1.35,
                                letterSpacing: 0.3)),
                        trailing: current
                            ? const Chip(
                                label: Text('CURRENT',
                                    style: TextStyle(
                                        fontSize: 9,
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero)
                            : IconButton(
                                tooltip: 'Revoke session',
                                icon: const Icon(Icons.close,
                                    color: Colors.redAccent, size: 18),
                                onPressed: () async {
                                  try {
                                    await api.revokeSession(
                                        session['id'].toString());
                                    sessions = await api.sessions();
                                    if (dialogContext.mounted) {
                                      setDialogState(() {});
                                    }
                                  } catch (exception) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(SnackBar(
                                              content: Text(exception
                                                  .toString()
                                                  .replaceFirst(
                                                      'Exception: ', ''))));
                                    }
                                  }
                                },
                              ),
                      ),
                    );
                  }),
                const Divider(height: 28),
                const Text('Authenticator MFA', style: _securitySectionStyle),
                const SizedBox(height: 6),
                const Text(
                    'Enroll or disable authenticator verification from this account.',
                    style: TextStyle(
                        color: mutedColor, fontSize: 12, height: 1.35)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: violetColor,
                          side: const BorderSide(color: violetColor),
                          textStyle: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700)),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showMfaDialog(context, api);
                      },
                      icon: const Icon(Icons.add_moderator),
                      label: const Text('ENROLL MFA')),
                  OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: violetColor,
                          side: const BorderSide(color: violetColor),
                          textStyle: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700)),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showDisableMfaDialog(context, api);
                      },
                      icon: const Icon(Icons.remove_moderator),
                      label: const Text('DISABLE MFA')),
                ]),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: dialogContext,
                      builder: (confirmContext) => AlertDialog(
                        title: const Text('Revoke every session?'),
                        content: const Text(
                            'This signs out every device, including the current one.'),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(confirmContext, false),
                              child: const Text('CANCEL')),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.pop(confirmContext, true),
                              child: const Text('REVOKE ALL')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await api.revokeAllSessions();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      onLogout();
                    } catch (exception) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                                content: Text(exception
                                    .toString()
                                    .replaceFirst('Exception: ', ''))));
                      }
                    }
                  },
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text('REVOKE ALL OTHER ACCESS',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('DONE',
                  style: TextStyle(
                      color: violetColor,
                      fontSize: 10,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700)))
        ],
      ),
    ),
  );
}
