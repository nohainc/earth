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
                  'Upgrade cost: 2,400 Credits. Business AI remains bounded to recommendations and machine maintenance; it cannot vote or hold authority.'),
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
                    await action(() => const EarthApi()
                        .upgradeAi(assistantId, otp: otp.text.trim()));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Upgrade')),
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
          ? const Text('No AI assistant is registered.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.aiAssistants.map((raw) {
                final assistant = raw as Map<String, dynamic>;
                final enabled = assistant['enabled'] == 1 ||
                    assistant['enabled'] == true;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${assistant['tier']} AI  ·  ${assistant['policy']}  ·  ${enabled ? 'enabled' : 'paused'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (assistant['tier'] != 'business')
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => showAiUpgradeDialog(
                                context, action, assistant['id'] as String),
                        child: const Text('UPGRADE · 2,400 C'),
                      ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi().setAiPolicy(
                              assistant['id'] as String,
                              assistant['policy'] == 'maintenance'
                                  ? 'recommend'
                                  : 'maintenance',
                              enabled: true)),
                      child: Text(assistant['policy'] == 'maintenance'
                          ? 'RECOMMEND'
                          : 'MAINTAIN'),
                    ),
                  ],
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
      child: state.aiRecommendations.isEmpty
          ? const Text(
              'No priority recommendations. The current state is within bounded operating conditions.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.aiRecommendations.take(6).map((raw) {
                final recommendation = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '${recommendation['priority']}  ·  ${recommendation['message']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
