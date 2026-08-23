import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

Future<void> showAiUpgradeDialog(
    BuildContext context,
    Future<void> Function(Future<EarthState> Function()) action,
    String assistantId) async {
  final otp = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
        side: BorderSide(color: dialogContext.subtleBorderColor),
      ),
      title: Row(
        children: [
          Icon(Icons.upgrade_rounded, size: 18, color: dialogContext.primaryColor),
          const SizedBox(width: 8),
          Text(
            'Upgrade to Business AI',
            style: dialogContext.pageTitleStyle,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upgrade cost: 2,400 Credits. Business AI unlocks automated routine machine maintenance and priority production dispatch. Under constitutional law, AI systems remain strictly bounded tools and cannot vote, hold governance titles, or own legal personhood.',
            style: dialogContext.widgetFooterStyle,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Authenticator code (if enabled)',
            ),
          ),
        ],
      ),
      actions: [
        EarthButton(
          label: 'CANCEL',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        EarthButton(
          label: 'Upgrade · 2,400 C',
          variant: EarthButtonVariant.primary,
          onPressed: () async {
            final otpCode = otp.text.trim();
            Navigator.pop(dialogContext);
            await action(
                () => const EarthApi().upgradeAi(assistantId, otp: otpCode));
          },
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
    return EarthSection(
      title: 'AI ASSISTANT / BOUNDED AUTOMATION',
      showSurface: false,
      infoBulletPoints: const [
        'Bounded AI Assistants: Algorithmic decision engines designed to optimize industrial and economic operations.',
        'Constitutional Safeguards: All AI instances are strictly bounded tools under Planetary Law. They possess no legal personhood, cannot vote in governance referendums, and cannot hold corporate officer titles.',
        'Automation Tiers:\n  - BASIC ADVISORY: Telemetry monitoring, anomaly detection, and explainable recommendations (10 C/day).\n  - BUSINESS OPERATIONS: Automated machine preventative maintenance and production cycle optimization (50 C/day).',
        'Policy Modes:\n  - RECOMMEND: Advisory mode generating non-binding suggestions.\n  - MAINTAIN: Automated dispatch mode executing preventative maintenance on machines approaching critical wear.',
      ],
      child: state.aiAssistants.isEmpty
          ? const EarthEmptyState(
              message: 'No AI assistant is registered for this citizen.',
              icon: Icons.memory_outlined,
            )
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

                final tierColor = isBusiness ? context.secondaryColor : context.primaryColor;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.all(context.cardPadding),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    border: Border.all(
                      color: enabled
                          ? tierColor.withValues(alpha: .3)
                          : context.subtleBorderColor,
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
                              borderRadius: BorderRadius.circular(context.radiusControl),
                            ),
                            child: Icon(
                              isBusiness
                                  ? Icons.smart_toy_outlined
                                  : Icons.memory_outlined,
                              size: 16,
                              color: tierColor,
                            ),
                          ),
                          SizedBox(width: context.spacingInline),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$tier AI ASSISTANT ($id)',
                                  style: context.widgetTitleStyle,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Policy: $policy · Operating cost: ${isBusiness ? '50 CR/day' : '10 CR/day'}',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          EarthBadge(
                            label: enabled ? 'ACTIVE' : 'PAUSED',
                            variant: enabled ? EarthBadgeVariant.success : EarthBadgeVariant.warning,
                          ),
                        ],
                      ),
                      SizedBox(height: context.spacingControl),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.panelColor,
                          borderRadius: BorderRadius.circular(context.radiusControl),
                        ),
                        child: Text(
                          'Service effects: ${isBusiness ? 'Automated routine maintenance, capacity optimization' : 'Advisory monitoring, anomaly alerts'}',
                          style: context.widgetFooterStyle,
                        ),
                      ),
                      SizedBox(height: context.spacingControl),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (!isBusiness)
                            EarthButton(
                              icon: Icons.upgrade_rounded,
                              label: 'UPGRADE (2,400 C)',
                              variant: EarthButtonVariant.primary,
                              onPressed: busy
                                  ? null
                                  : () {
                                      EarthAudioEngine.instance.playClick();
                                      showAiUpgradeDialog(context, action, id);
                                    },
                            ),
                          EarthButton(
                            label: 'POLICY: RECOMMEND',
                            variant: policy == 'RECOMMEND'
                                ? EarthButtonVariant.primary
                                : EarthButtonVariant.neutral,
                            onPressed: busy
                                ? null
                                : () {
                                    EarthAudioEngine.instance.playClick();
                                    action(() => const EarthApi().setAiPolicy(
                                          id,
                                          'recommend',
                                          enabled: true,
                                        ));
                                  },
                          ),
                          EarthButton(
                            label: 'POLICY: MAINTAIN',
                            variant: policy == 'MAINTENANCE'
                                ? EarthButtonVariant.primary
                                : EarthButtonVariant.neutral,
                            onPressed: busy
                                ? null
                                : () {
                                    EarthAudioEngine.instance.playClick();
                                    action(() => const EarthApi().setAiPolicy(
                                          id,
                                          'maintenance',
                                          enabled: true,
                                        ));
                                  },
                          ),
                          EarthButton(
                            label: enabled ? 'PAUSE' : 'RESUME',
                            variant: enabled
                                ? EarthButtonVariant.warning
                                : EarthButtonVariant.primary,
                            onPressed: busy
                                ? null
                                : () {
                                    EarthAudioEngine.instance.playClick();
                                    action(() => const EarthApi().setAiPolicy(
                                          id,
                                          assistant['policy']?.toString() ?? 'recommend',
                                          enabled: !enabled,
                                        ));
                                  },
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
    return EarthSection(
      title: 'AI / EXPLAINABLE RECOMMENDATIONS',
      showSurface: false,
      infoBulletPoints: const [
        'Explainable Decision Engine: Real-time telemetry monitoring providing transparent, auditable optimization guidance across fleet maintenance, supply inventory, and market pricing.',
        'Player Sovereignty: Recommendations are purely advisory and strictly non-binding. No economic action or fund transfer occurs without explicit player instruction.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: context.primaryColor),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Text(
                    'Advisory Notice: Recommendations are explainable suggestions and never mutate economic state without explicit player confirmation.',
                    style: context.widgetFooterStyle,
                  ),
                ),
              ],
            ),
          ),
          if (state.aiRecommendations.isEmpty)
            const EarthEmptyState(
              message: 'No priority recommendations. The current state is within bounded operating conditions.',
              icon: Icons.check_circle_outline,
            )
          else
            EarthDataList(
              children: state.aiRecommendations.take(6).map((raw) {
                final recommendation = raw as Map<String, dynamic>;
                final priority =
                    (recommendation['priority']?.toString() ?? 'INFO')
                        .toUpperCase();
                final message = recommendation['message']?.toString() ?? '';
                final reason = recommendation['reason']?.toString() ??
                    recommendation['source']?.toString();

                EarthBadgeVariant badgeVariant = EarthBadgeVariant.primary;
                if (priority == 'HIGH' || priority == 'CRITICAL') {
                  badgeVariant = EarthBadgeVariant.warning;
                }

                return EarthDataRow(
                  title: message,
                  subtitle: reason != null && reason.isNotEmpty ? 'Source: $reason' : null,
                  badges: [
                    EarthBadge(label: priority, variant: badgeVariant),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
