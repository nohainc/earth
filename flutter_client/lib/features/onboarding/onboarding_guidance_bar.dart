import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/onboarding_state.dart';
import '../../core/onboarding_controller.dart';
import '../../core/audio/earth_audio_engine.dart';
import 'onboarding_completion_dialog.dart';

class OnboardingGuidanceBar extends StatefulWidget {
  final void Function(String section) onNavigate;

  const OnboardingGuidanceBar({
    super.key,
    required this.onNavigate,
  });

  @override
  State<OnboardingGuidanceBar> createState() => _OnboardingGuidanceBarState();
}

class _OnboardingGuidanceBarState extends State<OnboardingGuidanceBar> {
  bool _isMinimized = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OnboardingController.instance,
      builder: (context, _) {
        final ctrl = OnboardingController.instance;
        if (ctrl.isDismissed) return const SizedBox.shrink();

        final step = ctrl.currentStep;
        final totalSteps = OnboardingStep.steps.length;
        final completedCount = ctrl.progress.completedStepIds.length;
        final progressRatio = (completedCount / totalSteps).clamp(0.0, 1.0);
        final isCurrentCompleted = ctrl.progress.completedStepIds.contains(step.id);

        if (_isMinimized) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(140), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: EarthThemeController.instance.primaryAccent.withAlpha(30),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: InkWell(
              key: const Key('btn-onboarding-expand'),
              onTap: () {
                EarthAudioEngine.instance.playClick();
                setState(() => _isMinimized = false);
              },
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(step.icon, color: EarthThemeController.instance.primaryAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'ORIENTATION: STEP ${step.index + 1}/$totalSteps • ${step.title}',
                      style: TextStyle(
                        color: EarthThemeController.instance.primaryAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EarthThemeController.instance.primaryAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(progressRatio * 100).toInt()}%',
                        style: TextStyle(
                          color: EarthThemeController.instance.primaryAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.expand_more, size: 16, color: EarthColors.textMuted),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: EarthColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(160), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: EarthThemeController.instance.primaryAccent.withAlpha(40),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Progress Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: EarthColors.panelSurface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EarthThemeController.instance.primaryAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: EarthThemeController.instance.primaryAccent),
                          ),
                          child: Text(
                            'ORIENTATION STEP ${step.index + 1} OF $totalSteps',
                            style: TextStyle(
                              color: EarthThemeController.instance.primaryAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrentCompleted)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF00E676), size: 13),
                              SizedBox(width: 4),
                              Text(
                                'COMPLETED',
                                style: TextStyle(color: Color(0xFF00E676), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          key: const Key('btn-onboarding-skip'),
                          onPressed: () {
                            ctrl.setDismissed(true);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('DISMISS', style: TextStyle(color: EarthColors.textMuted, fontSize: 9.5)),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          key: const Key('btn-onboarding-minimize'),
                          icon: const Icon(Icons.expand_less, size: 16, color: EarthColors.textMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            EarthAudioEngine.instance.playClick();
                            setState(() => _isMinimized = true);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Progress Bar
              LinearProgressIndicator(
                value: progressRatio,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(EarthThemeController.instance.primaryAccent),
                minHeight: 2.5,
              ),

              // Body Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: EarthThemeController.instance.primaryAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(80)),
                      ),
                      child: Icon(step.icon, color: EarthThemeController.instance.primaryAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: .6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.subtitle,
                            style: TextStyle(
                              color: EarthThemeController.instance.primaryAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            step.description,
                            style: const TextStyle(color: EarthColors.textMuted, fontSize: 11, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          key: Key('btn-onboarding-action-${step.id}'),
                          onPressed: () {
                            EarthAudioEngine.instance.playClick();
                            ctrl.completeStep(step.id);
                            widget.onNavigate(step.targetSection);

                            if (ctrl.isCompleted) {
                              showOnboardingCompletionDialog(context);
                            }
                          },
                          icon: const Icon(Icons.arrow_forward, size: 13),
                          label: Text(step.actionLabel),
                          style: FilledButton.styleFrom(
                            backgroundColor: EarthThemeController.instance.primaryAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const Key('btn-onboarding-prev'),
                              icon: const Icon(Icons.chevron_left, size: 18),
                              color: step.index > 0 ? Colors.white70 : Colors.white24,
                              onPressed: step.index > 0 ? ctrl.previousStep : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              key: const Key('btn-onboarding-next'),
                              icon: const Icon(Icons.chevron_right, size: 18),
                              color: step.index < totalSteps - 1 ? Colors.white70 : Colors.white24,
                              onPressed: step.index < totalSteps - 1 ? ctrl.nextStep : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
