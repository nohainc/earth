import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/onboarding_state.dart';
import '../../core/onboarding_controller.dart';
import '../../core/audio/earth_audio_engine.dart';

void showOnboardingWelcomeDialog(
  BuildContext context, {
  ValueChanged<String>? onNavigate,
}) {
  showDialog(
    context: context,
    builder: (context) => OnboardingWelcomeDialog(onNavigate: onNavigate),
  );
}

class OnboardingWelcomeDialog extends StatelessWidget {
  final ValueChanged<String>? onNavigate;

  const OnboardingWelcomeDialog({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final steps = OnboardingStep.steps;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 740),
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthColors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(
                    bottom: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: EarthThemeController.instance.primaryAccent
                          .withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: EarthThemeController.instance.primaryAccent),
                    ),
                    child: Icon(Icons.stars_rounded,
                        color: EarthThemeController.instance.primaryAccent,
                        size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ONBOARDING & OPERATIONS GUIDE',
                          style: TextStyle(
                            color: EarthThemeController.instance.primaryAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const Text(
                          'Six practical steps for understanding and acting in EARTH',
                          style: TextStyle(
                              color: EarthColors.textMuted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: EarthColors.textMuted, size: 18),
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

            // Content List
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome, Citizen. To establish your corporate footprint and secure generational longevity in the World, follow this 6-step orientation sequence:',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ...steps.map((s) => _buildStepPreviewCard(context, s)),
                  ],
                ),
              ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(13)),
                border: Border(
                    top: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      OnboardingController.instance.setDismissed(true);
                      Navigator.of(context).pop();
                    },
                    child: const Text('DISMISS & EXPLORE FREELY',
                        style: TextStyle(
                            color: EarthColors.textMuted, fontSize: 11)),
                  ),
                  FilledButton.icon(
                    key: const Key('btn-start-orientation-tour'),
                    onPressed: () {
                      EarthAudioEngine.instance.playChime();
                      OnboardingController.instance.setDismissed(false);
                      OnboardingController.instance.jumpToStep(0);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('START GUIDED ORIENTATION'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          EarthThemeController.instance.primaryAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11.5),
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

  Widget _buildStepPreviewCard(BuildContext context, OnboardingStep step) {
    final completed = OnboardingController.instance.progress.completedStepIds
        .contains(step.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      EarthThemeController.instance.primaryAccent.withAlpha(25),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: EarthThemeController.instance.primaryAccent
                          .withAlpha(80)),
                ),
                child: Text(
                  '${step.index + 1}',
                  style: TextStyle(
                    color: EarthThemeController.instance.primaryAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(step.icon,
                  color: EarthThemeController.instance.primaryAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5)),
                    Text(step.subtitle,
                        style: TextStyle(
                            color: EarthThemeController.instance.primaryAccent,
                            fontSize: 10)),
                  ],
                ),
              ),
              if (completed)
                const Icon(Icons.check_circle,
                    color: Color(0xFF00E676), size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(step.description,
              style: const TextStyle(
                  color: EarthColors.textMuted, fontSize: 11, height: 1.35)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onNavigate == null
                  ? null
                  : () {
                      EarthAudioEngine.instance.playClick();
                      OnboardingController.instance.completeStep(step.id);
                      Navigator.of(context).pop();
                      onNavigate!(step.targetSection);
                    },
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: Text(step.actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: EarthThemeController.instance.primaryAccent,
                textStyle:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
