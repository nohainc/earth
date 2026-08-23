import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';

Future<void> showAdminEmailDeliveriesDialog(
  BuildContext context, {
  required EarthApi api,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AdminEmailDeliveriesDialog(api: api),
  );
}

class AdminEmailDeliveriesDialog extends StatefulWidget {
  final EarthApi api;

  const AdminEmailDeliveriesDialog({super.key, required this.api});

  @override
  State<AdminEmailDeliveriesDialog> createState() => _AdminEmailDeliveriesDialogState();
}

class _AdminEmailDeliveriesDialogState extends State<AdminEmailDeliveriesDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchDeliveries();
  }

  Future<void> _fetchDeliveries() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.getEmailDeliveries();
      if (mounted) {
        setState(() {
          _data = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _data?['metrics'] as Map<dynamic, dynamic>? ?? {};
    final rawDeliveries = _data?['deliveries'] as List<dynamic>? ?? [];
    final bindingConfigured = _data?['bindingConfigured'] == true;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 820,
        height: 620,
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(150), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: EarthThemeController.instance.primaryAccent.withAlpha(35),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, color: EarthThemeController.instance.primaryAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'TRANSACTIONAL EMAIL OBSERVABILITY',
                                style: TextStyle(
                                  color: EarthThemeController.instance.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                  letterSpacing: 0.9,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: bindingConfigured ? const Color(0xFF00E676).withAlpha(25) : const Color(0xFFFFB300).withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: bindingConfigured ? const Color(0xFF00E676) : const Color(0xFFFFB300)),
                              ),
                              child: Text(
                                bindingConfigured ? 'BINDING HEALTHY' : 'EMAIL BINDING NOT CONFIGURED',
                                style: TextStyle(
                                  color: bindingConfigured ? const Color(0xFF00E676) : const Color(0xFFFFB300),
                                  fontSize: 8.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Operational audit logs, correlation IDs, and delivery metrics for identity verification & recovery.',
                          style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: EarthColors.textMuted, size: 18),
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      _fetchDeliveries();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),

            // Content Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12)))
                      : Column(
                          children: [
                            // Metrics Row
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                color: EarthColors.cardSurface,
                                border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                              ),
                              child: Row(
                                children: [
                                  _buildMetricCard('ACCEPTED', '${metrics['totalAccepted'] ?? 0}', const Color(0xFF00E676)),
                                  const SizedBox(width: 10),
                                  _buildMetricCard('FAILED', '${metrics['totalFailed'] ?? 0}', const Color(0xFFFF5252)),
                                  const SizedBox(width: 10),
                                  _buildMetricCard('SUCCESS RATE', '${metrics['successRatePct'] ?? 100}%', EarthThemeController.instance.primaryAccent),
                                  const SizedBox(width: 10),
                                  _buildMetricCard('LAST DISPATCH', metrics['lastDeliveryAt']?.toString().split('T').last.replaceAll('Z', '') ?? 'N/A', const Color(0xFF38BDF8)),
                                ],
                              ),
                            ),

                            // Deliveries Table
                            Expanded(
                              child: rawDeliveries.isEmpty
                                  ? const Center(
                                      child: Text('No email delivery events recorded yet.', style: TextStyle(color: EarthColors.textMuted, fontSize: 12)),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(14),
                                      itemCount: rawDeliveries.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final item = rawDeliveries[index] as Map<dynamic, dynamic>? ?? {};
                                        final isAccepted = item['status'] == 'accepted';
                                        return Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: EarthColors.cardSurface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isAccepted ? Colors.white10 : const Color(0xFFFF5252).withAlpha(80)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: isAccepted ? const Color(0xFF00E676).withAlpha(20) : const Color(0xFFFF5252).withAlpha(20),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: isAccepted ? const Color(0xFF00E676) : const Color(0xFFFF5252)),
                                                        ),
                                                        child: Text(
                                                          (item['status']?.toString() ?? 'UNKNOWN').toUpperCase(),
                                                          style: TextStyle(
                                                            color: isAccepted ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                                                            fontSize: 8.5,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        (item['action']?.toString() ?? '').replaceAll('_', ' ').toUpperCase(),
                                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    item['createdAt']?.toString().replaceFirst('T', ' ').substring(0, 19) ?? '',
                                                    style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Recipient: ${item['recipientMasked'] ?? '***'} • Human: ${item['humanId'] ?? 'N/A'}',
                                                      style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Correlation: ${item['correlationId'] ?? 'N/A'}',
                                                    style: TextStyle(color: EarthThemeController.instance.primaryAccent, fontSize: 9.5, fontFamily: 'monospace'),
                                                  ),
                                                ],
                                              ),
                                              if (item['errorMessage'] != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Error [${item['errorCode'] ?? 'ERR'}]: ${item['errorMessage']}',
                                                  style: const TextStyle(color: Color(0xFFFF5252), fontSize: 10),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: accent, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: .6)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
