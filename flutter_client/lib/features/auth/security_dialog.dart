import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showMfaDialog(BuildContext context, EarthApi api) async {
  final code = TextEditingController();
  try {
    final enrollment = await api.enrollMfa();
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Enable authenticator MFA'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Add this secret to your authenticator app, then enter the six-digit code.'),
                    const SizedBox(height: 12),
                    SelectableText('${enrollment['secret']}'),
                    const SizedBox(height: 12),
                    TextField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Authenticator code')),
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
          content:
              Text(exception.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

Future<void> showDisableMfaDialog(BuildContext context, EarthApi api) async {
  final code = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disable authenticator MFA'),
        content: TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Current six-digit code')),
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
          content:
              Text(exception.toString().replaceFirst('Exception: ', ''))));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Account security'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active sessions',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (sessions.isEmpty)
                  const Text('No active sessions were found.',
                      style: TextStyle(color: mutedColor))
                else
                  ...sessions.map((raw) {
                    final session = Map<String, dynamic>.from(raw as Map);
                    final current = session['current'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          current ? Icons.devices : Icons.device_unknown,
                          color: current ? violetColor : mutedColor),
                      title: Text(current ? 'This device' : 'Other session'),
                      subtitle: Text(
                          'Created ${formatSecurityDate(session['created_at'])}\nExpires ${formatSecurityDate(session['expires_at'])}'),
                      trailing: current
                          ? const Chip(label: Text('CURRENT'))
                          : IconButton(
                              tooltip: 'Revoke session',
                              icon: const Icon(Icons.close),
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
                    );
                  }),
                const Divider(height: 28),
                const Text('Authenticator MFA',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                    'Enroll or disable authenticator verification from this account.',
                    style: TextStyle(color: mutedColor, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showMfaDialog(context, api);
                      },
                      icon: const Icon(Icons.add_moderator),
                      label: const Text('ENROLL MFA')),
                  OutlinedButton.icon(
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
                  icon: const Icon(Icons.logout),
                  label: const Text('REVOKE ALL OTHER ACCESS'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('DONE'))
        ],
      ),
    ),
  );
}
