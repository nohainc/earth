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
      backgroundColor: const Color(0xFF141A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      title: const Row(
        children: [
          Icon(Icons.upgrade_rounded, size: 18, color: cyanAccentColor),
          SizedBox(width: 8),
          Text(
            'Upgrade to Business AI',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: inkColor),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upgrade cost: 2,400 Credits. Business AI unlocks automated routine machine maintenance and priority production dispatch. Under constitutional law, AI systems remain strictly bounded tools and cannot vote, hold governance titles, or own legal personhood.',
            style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13, color: inkColor),
            decoration: InputDecoration(
              labelText: 'Authenticator code (if enabled)',
              labelStyle: const TextStyle(fontSize: 11, color: mutedColor),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: cyanAccentColor),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel',
              style: TextStyle(color: mutedColor, fontSize: 11)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cyanAccentColor,
            foregroundColor: Colors.black,
          ),
          onPressed: () async {
            final otpCode = otp.text.trim();
            Navigator.pop(dialogContext);
            await action(
                () => const EarthApi().upgradeAi(assistantId, otp: otpCode));
          },
          child: const Text('Upgrade · 2,400 C',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
        ),
      ],
    ),
  );
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
      infoDescription:
          '• Bounded AI Assistants: Algorithmic decision engines designed to optimize industrial and economic operations.\n\n• Constitutional Safeguards: All AI instances are strictly bounded tools under Planetary Law. They possess no legal personhood, cannot vote in governance referendums, and cannot hold corporate officer titles.\n\n• Automation Tiers:\n  - BASIC ADVISORY: Telemetry monitoring, anomaly detection, and explainable recommendations (10 C/day).\n  - BUSINESS OPERATIONS: Automated machine preventative maintenance and production cycle optimization (50 C/day).\n\n• Policy Modes:\n  - RECOMMEND: Advisory mode generating non-binding suggestions.\n  - MAINTAIN: Automated dispatch mode executing preventative maintenance on machines approaching critical wear.',
      child: state.aiAssistants.isEmpty
          ? const Text('No AI assistant is registered for this citizen.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.aiAssistants.map((raw) {
                final assistant = raw as Map<String, dynamic>;
                final id = assistant['id']?.toString() ?? 'AI-01';
                final tier =
                    (assistant['tier']?.toString() ?? 'basic').toUpperCase();
                final policy =
                    (assistant['policy']?.toString() ?? 'recommend')
                        .toUpperCase();
                final enabled = assistant['enabled'] == 1 ||
                    assistant['enabled'] == true ||
                    assistant['status'] == 'active';
                final isBusiness =
                    (assistant['tier']?.toString() ?? 'basic').toLowerCase() ==
                        'business';

                final tierColor = isBusiness ? violetColor : cyanAccentColor;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: enabled
                          ? tierColor.withValues(alpha: .3)
                          : Colors.white10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: tierColor.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isBusiness
                                  ? Icons.smart_toy_outlined
                                  : Icons.memory_outlined,
                              size: 16,
                              color: tierColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$tier AI ASSISTANT ($id)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: inkColor,
                                    letterSpacing: .4,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Policy: $policy · Operating cost: ${isBusiness ? '50 C/day' : '10 C/day'}',
                                  style: const TextStyle(
                                      color: mutedColor, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: (enabled
                                      ? cyanAccentColor
                                      : Colors.orangeAccent)
                                  .withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (enabled
                                        ? cyanAccentColor
                                        : Colors.orangeAccent)
                                    .withValues(alpha: .4),
                              ),
                            ),
                            child: Text(
                              enabled ? 'ACTIVE' : 'PAUSED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                                color: enabled
                                    ? cyanAccentColor
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .03),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Service effects: ${isBusiness ? 'Automated routine maintenance, capacity optimization' : 'Advisory monitoring, anomaly alerts'}',
                          style: const TextStyle(
                              color: mutedColor, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (!isBusiness)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: violetColor,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => showAiUpgradeDialog(
                                      context, action, id),
                              icon: const Icon(Icons.upgrade_rounded, size: 14),
                              label: const Text('UPGRADE (2,400 C)',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              backgroundColor: policy == 'RECOMMEND'
                                  ? cyanAccentColor.withValues(alpha: .15)
                                  : null,
                              side: BorderSide(
                                color: policy == 'RECOMMEND'
                                    ? cyanAccentColor
                                    : Colors.white24,
                              ),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      'recommend',
                                      enabled: true,
                                    )),
                            child: Text(
                              'POLICY: RECOMMEND',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: policy == 'RECOMMEND'
                                    ? cyanAccentColor
                                    : inkColor,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              backgroundColor: policy == 'MAINTENANCE'
                                  ? violetColor.withValues(alpha: .15)
                                  : null,
                              side: BorderSide(
                                color: policy == 'MAINTENANCE'
                                    ? violetColor
                                    : Colors.white24,
                              ),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      'maintenance',
                                      enabled: true,
                                    )),
                            child: Text(
                              'POLICY: MAINTAIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: policy == 'MAINTENANCE'
                                    ? violetColor
                                    : inkColor,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              side: const BorderSide(color: Colors.white24),
                            ),
                            onPressed: busy
                                ? null
                                : () => action(() => const EarthApi().setAiPolicy(
                                      id,
                                      assistant['policy']?.toString() ??
                                          'recommend',
                                      enabled: !enabled,
                                    )),
                            child: Text(
                              enabled ? 'PAUSE' : 'RESUME',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: enabled
                                    ? Colors.orangeAccent
                                    : cyanAccentColor,
                              ),
                            ),
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
      infoDescription:
          '• Explainable Decision Engine: Real-time telemetry monitoring providing transparent, auditable optimization guidance across fleet maintenance, supply inventory, and market pricing.\n\n• Player Sovereignty: Recommendations are purely advisory and strictly non-binding. No economic action or fund transfer occurs without explicit player instruction.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: cyanAccentColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Advisory Notice: Recommendations are explainable suggestions and never mutate economic state without explicit player confirmation.',
                    style: TextStyle(
                        fontSize: 10, color: mutedColor, height: 1.35),
                  ),
                ),
              ],
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
              final priority =
                  (recommendation['priority']?.toString() ?? 'INFO')
                      .toUpperCase();
              final message = recommendation['message']?.toString() ?? '';
              final reason = recommendation['reason']?.toString() ??
                  recommendation['source']?.toString();

              Color prioColor = cyanAccentColor;
              if (priority == 'HIGH' || priority == 'CRITICAL') {
                prioColor = Colors.orangeAccent;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: prioColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: prioColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            priority,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: prioColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: inkColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (reason != null && reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 4),
                        child: Text(
                          'Source: $reason',
                          style:
                              const TextStyle(fontSize: 9.5, color: mutedColor),
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
