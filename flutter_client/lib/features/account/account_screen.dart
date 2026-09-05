import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';
import '../auth/security_dialog.dart';

class AccountScreen extends StatefulWidget {
  final EarthState state;
  final EarthApi api;
  final VoidCallback? onLogout;
  final ValueChanged<String>? onNavigate;

  const AccountScreen({
    super.key,
    required this.state,
    required this.api,
    this.onLogout,
    this.onNavigate,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loading = false;
  bool _mfaEnabled = false;
  String _email = '';
  List<dynamic> _sessions = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAccountData();
  }

  Future<void> _loadAccountData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final sessionInfo = await widget.api.session();
      final human = sessionInfo['human'] as Map<String, dynamic>? ?? {};
      final sessions = await widget.api.sessions();

      if (mounted) {
        setState(() {
          _email = human['email']?.toString() ??
              widget.state.human['email']?.toString() ??
              '';
          _mfaEnabled = human['mfa_enabled'] == true;
          _sessions = sessions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    EarthAudioEngine.instance.playClick();
    try {
      await widget.api.revokeSession(sessionId);
      await _loadAccountData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: context.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _revokeAllSessions() async {
    EarthAudioEngine.instance.playClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Revoke all sessions?',
          style: TextStyle(
            color: context.inkColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This will sign out all devices, including your current session.',
          style: TextStyle(color: context.mutedColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.errorColor,
            ),
            onPressed: () => Navigator.pop(confirmContext, true),
            child: const Text('REVOKE ALL'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.api.revokeAllSessions();
      widget.onLogout?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: context.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    EarthAudioEngine.instance.playClick();
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: context.errorColor.withValues(alpha: 0.5),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: context.errorColor),
              const SizedBox(width: 10),
              Text(
                'Delete Account Permanently',
                style: TextStyle(
                  color: context.inkColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete your account? This action cannot be undone.',
                  style: TextStyle(
                    color: context.inkColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: context.errorColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• All active login sessions will be immediately terminated.\n'
                        '• Your citizen credentials and email access will be removed.\n'
                        '• Personal buildings and assets will be vacated.',
                        style: TextStyle(
                          color: context.errorColor,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Type DELETE to confirm:',
                  style: TextStyle(
                    color: context.mutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationController,
                  autofocus: true,
                  style: TextStyle(color: context.inkColor),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: TextStyle(
                      color: context.mutedColor.withValues(alpha: 0.5),
                    ),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.errorColor,
              ),
              onPressed: confirmationController.text.trim() == 'DELETE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('PERMANENTLY DELETE'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await widget.api.deleteAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account has been deleted.')),
        );
      }
      widget.onLogout?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: context.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final human = widget.state.human;
    final citizenName = (human['display_name'] ?? human['name'] ?? 'Citizen')
        .toString();
    final citizenId = human['id']?.toString() ?? 'H-00000000';
    final houseName = (widget.state.life['houseName'] ??
            widget.state.life['dynastyName'] ??
            human['house_name'] ??
            human['houseName'] ??
            'House Unknown')
        .toString();
    final city = widget.state.institutions['city'];
    final cityName = city is Map ? city['name']?.toString() ?? 'Neo Tokyo' : 'Neo Tokyo';
    final standing = human['standing']?.toString() ?? '100';

    final cockpit = EarthPageCockpit(
      status: _mfaEnabled ? 'CREDENTIAL INTEGRITY' : 'MFA RECOMMENDED',
      statusColor: _mfaEnabled ? context.successColor : context.warningColor,
      infoTitle: 'CITIZEN SECURITY & ENCLAVE CREDENTIALS',
      infoDescription:
          '• Cryptographic MFA: Time-based One-Time Password (TOTP) enforcement securing citizen credentials against identity compromise.\n\n• Session Telemetry: Active device tokens and hardware sessions with instant revocation capabilities.\n\n• Civic Standing: Registered citizen charter and civil standing under planetary constitutional law.',
      title: 'ACCOUNT & SECURITY',
      subtitle:
          'Citizen credentials, multi-factor authentication, and active session telemetry',
      metrics: [
        CockpitMetric(
          label: 'Security',
          value: _mfaEnabled ? 'MFA Protected' : 'MFA Disabled',
          icon: _mfaEnabled ? Icons.shield_outlined : Icons.gpp_maybe_outlined,
          color: _mfaEnabled ? context.successColor : context.warningColor,
        ),
        CockpitMetric(
          label: 'Sessions',
          value: '${_sessions.length}',
          icon: Icons.devices_outlined,
          color: context.primaryColor,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cockpit,
        const SizedBox(height: 24),

          if (_errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.errorColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: context.errorColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: context.errorColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 1. Identity & Email Card
          _buildCard(
            context,
            title: 'CITIZEN IDENTITY & CREDENTIALS',
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  context,
                  label: 'Registered Email',
                  value: _email.isNotEmpty ? _email : (human['email']?.toString() ?? 'Loading...'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 15),
                    tooltip: 'Copy Email',
                    onPressed: _email.isNotEmpty
                        ? () {
                            Clipboard.setData(ClipboardData(text: _email));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Email copied to clipboard')),
                            );
                          }
                        : null,
                  ),
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  context,
                  label: 'Citizen ID',
                  value: citizenId,
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  context,
                  label: 'Display Name',
                  value: citizenName,
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  context,
                  label: 'House / Dynasty',
                  value: houseName,
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  context,
                  label: 'Jurisdiction & Standing',
                  value: 'Citizen of $cityName · Standing $standing',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Multi-Factor Authentication (MFA) Card
          _buildCard(
            context,
            title: 'MULTI-FACTOR AUTHENTICATION (MFA)',
            icon: Icons.shield_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Authenticator App (TOTP)',
                                style: TextStyle(
                                  color: context.inkColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _mfaEnabled
                                      ? context.primaryColor.withValues(alpha: 0.15)
                                      : context.mutedColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _mfaEnabled
                                        ? context.primaryColor.withValues(alpha: 0.4)
                                        : context.mutedColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  _mfaEnabled ? 'ENABLED' : 'DISABLED',
                                  style: TextStyle(
                                    color: _mfaEnabled
                                        ? context.primaryColor
                                        : context.mutedColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Protect your citizen account with a 6-digit TOTP code during sign in.',
                            style: TextStyle(
                              color: context.mutedColor,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!_mfaEnabled)
                      FilledButton.icon(
                        icon: const Icon(Icons.add_moderator, size: 16),
                        label: const Text('ENROLL MFA'),
                        onPressed: () async {
                          await showMfaDialog(context, widget.api);
                          await _loadAccountData();
                        },
                      )
                    else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.errorColor,
                          side: BorderSide(
                            color: context.errorColor.withValues(alpha: 0.5),
                          ),
                        ),
                        icon: const Icon(Icons.remove_moderator, size: 16),
                        label: const Text('DISABLE MFA'),
                        onPressed: () async {
                          await showDisableMfaDialog(context, widget.api);
                          await _loadAccountData();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Active Sessions Card
          _buildCard(
            context,
            title: 'ACTIVE SESSIONS',
            icon: Icons.devices,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Manage logged in sessions and authorized devices.',
                        style: TextStyle(
                          color: context.mutedColor,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_sessions.length > 1)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: context.errorColor,
                        ),
                        icon: const Icon(Icons.exit_to_app, size: 15),
                        label: const Text('REVOKE ALL SESSIONS'),
                        onPressed: _revokeAllSessions,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_sessions.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No active sessions found.',
                      style: TextStyle(color: context.mutedColor, fontSize: 12),
                    ),
                  ),
                ] else ...[
                  ..._sessions.map((raw) {
                    final session = Map<String, dynamic>.from(raw as Map);
                    final isCurrent = session['current'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.canvasColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrent
                              ? context.primaryColor.withValues(alpha: 0.4)
                              : context.mutedColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCurrent ? Icons.laptop_chromebook : Icons.devices_other,
                            color: isCurrent
                                ? context.primaryColor
                                : context.mutedColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isCurrent ? 'Current Device' : 'Other Session',
                                      style: TextStyle(
                                        color: context.inkColor,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.primaryColor
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: context.primaryColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Created: ${formatSecurityDate(session['created_at'])}',
                                  style: TextStyle(
                                    color: context.mutedColor,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isCurrent)
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: context.errorColor,
                                size: 18,
                              ),
                              tooltip: 'Revoke this session',
                              onPressed: () =>
                                  _revokeSession(session['id'].toString()),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Danger Zone: Delete Account
          _buildCard(
            context,
            title: 'DANGER ZONE',
            icon: Icons.warning_amber_rounded,
            borderColor: context.errorColor.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete Account Permanently',
                            style: TextStyle(
                              color: context.inkColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Permanently delete your citizen credentials, terminate all sessions, and vacate owned assets.',
                            style: TextStyle(
                              color: context.mutedColor,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.errorColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.delete_forever, size: 16),
                      label: const Text('DELETE ACCOUNT'),
                      onPressed: _loading ? null : _deleteAccount,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? context.primaryColor.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: context.inkColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
