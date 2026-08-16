import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

Future<void> showAiUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String assistantId) async {
  final otp = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: const Text('Upgrade to Business AI'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Upgrade cost: 2,400 Credits. Business AI unlocks automated routine maintenance and priority production recommendations. It remains strictly bounded and cannot vote or hold governance authority.'),
              const SizedBox(height: 12),
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Authenticator code (if enabled)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () async {
                    final otpCode = otp.text.trim();
                    Navigator.pop(dialogContext);
                    await action(() => const EarthApi()
                        .upgradeAi(assistantId, otp: otpCode));
                  },
                  child: const Text('Upgrade · 2,400 C')),
            ],
          ));
  otp.dispose();
}

class AiAssistantPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const AiAssistantPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'AI ASSISTANT / BOUNDED AUTOMATION',
      child: state.aiAssistants.isEmpty
          ? const Text('No AI assistant is registered for this citizen.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.aiAssistants.map((raw) {
                final assistant = raw as Map<String, dynamic>;
                final id = assistant['id']?.toString() ?? 'AI-01';
                final tier = (assistant['tier']?.toString() ?? 'basic').toUpperCase();
                final policy = (assistant['policy']?.toString() ?? 'recommend').toUpperCase();
                final enabled = assistant['enabled'] == 1 ||
                    assistant['enabled'] == true ||
                    assistant['status'] == 'active';
                final isBusiness = (assistant['tier']?.toString() ?? 'basic').toLowerCase() == 'business';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$tier AI ASSISTANT ($id)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                            ),
                          ),
                          Text(
                            enabled ? 'ACTIVE' : 'PAUSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: enabled ? cyanAccentColor : mutedColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Policy: $policy · Operating cost: ${isBusiness ? '50 C/day' : '10 C/day'}',
                        style: const TextStyle(color: mutedColor, fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Service effects: ${isBusiness ? 'Automated routine maintenance, capacity optimization' : 'Advisory monitoring, anomaly alerts'}',
                        style: const TextStyle(color: mutedColor, fontSize: 10),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (!isBusiness)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => showAiUpgradeDialog(context, action, id),
                              child: const Text('UPGRADE (2,400 C)', style: TextStyle(fontSize: 10)),
                            ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              backgroundColor: policy == 'RECOMMEND' ? Colors.white12 : null,
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      'recommend',
                                      enabled: true,
                                    )),
                            child: const Text('POLICY: RECOMMEND', style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              backgroundColor: policy == 'MAINTENANCE' ? Colors.white12 : null,
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      'maintenance',
                                      enabled: true,
                                    )),
                            child: const Text('POLICY: MAINTAIN', style: TextStyle(fontSize: 10)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      assistant['policy']?.toString() ?? 'recommend',
                                      enabled: !enabled,
                                    )),
                            child: Text(enabled ? 'PAUSE' : 'RESUME', style: const TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class AiRecommendationsPanel extends StatelessWidget {
  final EarthState state;

  const AiRecommendationsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'AI / EXPLAINABLE RECOMMENDATIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withAlpha(15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blueAccent.withAlpha(40)),
            ),
            child: const Text(
              'Advisory Notice: Recommendations are explainable suggestions and never mutate economic state without explicit player confirmation.',
              style: TextStyle(fontSize: 9, color: mutedColor),
            ),
          ),
          if (state.aiRecommendations.isEmpty)
            const Text(
              'No priority recommendations. The current state is within bounded operating conditions.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...state.aiRecommendations.take(6).map((raw) {
              final recommendation = raw as Map<String, dynamic>;
              final priority = (recommendation['priority']?.toString() ?? 'INFO').toUpperCase();
              final message = recommendation['message']?.toString() ?? '';
              final reason = recommendation['reason']?.toString() ?? recommendation['source']?.toString();

              Color prioColor = cyanAccentColor;
              if (priority == 'HIGH' || priority == 'CRITICAL') prioColor = Colors.orangeAccent;

              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          priority,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: prioColor),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (reason != null && reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 1),
                        child: Text(
                          'Source: $reason',
                          style: const TextStyle(fontSize: 9, color: mutedColor),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
